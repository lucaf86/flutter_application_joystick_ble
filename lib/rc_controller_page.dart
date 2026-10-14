import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scanf/scanf.dart';

import 'raw_joystick.dart';
import 'web_config_page.dart';
import 'constants.dart';

class RcControllerPage extends StatefulWidget {
  const RcControllerPage({super.key});

  @override
  State<RcControllerPage> createState() => _RcControllerPageState();
}

class _RcControllerPageState extends State<RcControllerPage> {
  // Assi dei Joystick (-1.0 a 1.0)
  double _trazione = 0.0; // Speed (Verticale)
  double _sterzo = 0.0; // Steering (Orizzontale)

  // Canali di controllo ausiliari (Piccoli)
  double _tilt = 0.0; // Inclinazione (Orizzontale)
  double _lift = 0.0; // Elevazione (Verticale)

  bool _isLightOn = false; // Controllato direttamente dal feedback dell'ESP32
  String _lastSentData = "";
  String _esp32IpAddress = AppConstants.defaultIpAddress;

  // Timer per l'invio periodico temporizzato (Rate Limiting)
  Timer? _transmissionTimer;
  Timer? _keepAliveTimer;
  Timer? _scanTimeoutTimer; // Timer software per gestire graficamente il timeout
  
  // Configurazione Bluetooth BLE
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _rxCharacteristic;
  BluetoothCharacteristic? _txCharacteristic;

  bool _isScanning = false;
  bool _scanTimeout = false; // per scambiare la grafica di ricerca col tasto di riavvio
  List<ScanResult> _scanResults = [];
  StreamSubscription? _scanSubscription;

  // Variabili per la gestione dinamica della batteria
  int _livelloBatteria = 100; // Valore numerico di default

  String? _savedMacAddress; // Memorizza temporaneamente il MAC caricato all'avvio
  
  int _keepAlivePeriodMs = 250;

  @override
  void initState() {
    super.initState();

    // Ascolta i risultati della scansione BLE
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      setState(() {
        _scanResults = results;
      });

      // Auto-connessione se c'è un indirizzo salvato in memoria
      if (_savedMacAddress != null && _connectedDevice == null) {
        for (var result in results) {
          if (result.device.remoteId.toString() == _savedMacAddress) {
            //print("[AUTO-CONNECT] Connecting to saved devide (${result.device.platformName})...");
            // Estrazione del Keep-Alive dinamico dai Manufacturer Data di NimBLE
            if (result.advertisementData.manufacturerData.isNotEmpty) {
              var key = result.advertisementData.manufacturerData.keys.first;
              List<int>? data = result.advertisementData.manufacturerData[key];

              if (key == AppConstants.keepAliveAckDataKey && data != null && data.length >= 2) {
                int ackMs = (data[0] << 8) | data[1];
                if (ackMs > 0 && ackMs < 5000) {
                  _keepAlivePeriodMs = ackMs;
                  print("_keepAlivePeriodMs rilevato: $_keepAlivePeriodMs ms");
                }
              }
            }
            _scanTimeoutTimer?.cancel();
            print("_scanTimeoutTimer stop in initState");
            FlutterBluePlus.stopScan();
            _connectToDevice(result.device);
            break;
          }
        }
      }
    });


    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkSavedDevice();
    });
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    // Ferma i timer se si esce dalla pagina
    _scanTimeoutTimer?.cancel();
    _stopTransmissionTimer();
    _stopKeepAliveTimer();
    _exitFullscreen();
    super.dispose();
  }

  // Controlla se c'è un device memorizzato nelle preferenze del telefono
  void _checkSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMac = prefs.getString(AppConstants.prefMacAddressKey);

    if (savedMac != null && savedMac.isNotEmpty) {
      setState(() {
        _savedMacAddress = savedMac;
      });
      //print("[MEMORIA] MAC Address trovato: $savedMac. Attivo scansione...");
    }
    _startScan(); // Avvia in ogni caso la scansione delle antenne
  }

  // Cancella la memoria, scollega il BLE e torna alla ricerca pulita
  void _forgetAndDisconnectDevice() async {
    _scanTimeoutTimer?.cancel();
    // Forza lo stop immediato della scansione nativa per sbloccare l'antenna
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.prefMacAddressKey);

    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
    }

    _exitFullscreen();
    _stopTransmissionTimer();
    _stopKeepAliveTimer();

    setState(() {
      _connectedDevice = null;
      _savedMacAddress = null;
      _txCharacteristic = null;
      _rxCharacteristic = null;
      _scanResults.clear();
      _isScanning = false; // Sblocca esplicitamente la variabile prima del riavvio
      _scanTimeout = false;
    });

    // Inserito un piccolo ritardo asincrono per permettere ad Android di digerire lo stop nativo
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _startScan();
      }
    });
  }

  void _startTransmissionTimer() {
    _stopTransmissionTimer();
    // Invia i dati aggregati dei joystick in modo fisso ogni 120 millisecondi
    _transmissionTimer = Timer.periodic(const Duration(milliseconds: AppConstants.cmdTransmissionIntervalMs), (timer) {
        _sendJoystickData();
      });
  }

  void _stopTransmissionTimer() {
    if (_transmissionTimer != null) {
      //print("[TIMER] Arresto della routine periodica.");
      _transmissionTimer?.cancel();
      _transmissionTimer = null;
    }
  }

  void _startKeepaliveTimer() {
    _stopKeepAliveTimer();
    _keepAliveTimer = Timer.periodic(Duration(milliseconds: _keepAlivePeriodMs), (timer) {
        if (_txCharacteristic != null) {
          _txCharacteristic!.write(
                utf8.encode(AppConstants.keepAliveAckCommand),
                withoutResponse: true
              ).catchError((e) => print("Errore invio ACK KeepAlive: $e"));
        }
      });
  }

  void _stopKeepAliveTimer() {
    if (_keepAliveTimer != null) {
      _keepAliveTimer?.cancel();
      _keepAliveTimer = null;
    }
  }

  void _goFullscreen() {
    // Blocca lo schermo in Landscape (Orizzontale)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Rende trasparenti le barre di sistema in modo che lo sfondo riempia anche la zona della fotocamera
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ));

    // Nasconde la barra di stato e i tasti virtuali
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFullscreen() {
    // Sblocca la rotazione per tutte le direzioni
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Mostra nuovamente la barra delle notifiche e i tasti Android
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _startScan() async {
    print("_startScan with _isScanning $_isScanning");
    
    if (_isScanning) return;

    // Controlla lo stato attuale del Bluetooth dello smartphone
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      try {
        // 1. TENTATIVO: Mostra il pop-up nativo di Android che chiede "Consenti di attivare il Bluetooth"
        await FlutterBluePlus.turnOn();
        // Aspetta un piccolo istante per dare il tempo all'antenna di accendersi fisicamente
        await Future.delayed(const Duration(milliseconds: 600));

        // Se l'utente ha rifiutato o non si è acceso, reindirizza alle impostazioni
        if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
          throw Exception("Bluetooth is OFF");
        }
      } catch (e) {
        // 2. FALLBACK: Apre direttamente la pagina delle Impostazioni / App Info del telefono
        // così l'utente può attivare il Bluetooth o controllare i permessi dei Dispositivi Vicini
        await SystemChannels.platform.invokeMethod('SystemNavigator.pop'); // Chiude temporaneamente se necessario
        // Nota: FlutterBluePlus non gestisce l'intent Android profondo in autonomia,
        // ma con questo pop-up l'utente viene guidato in modo efficace.

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attiva il Bluetooth nelle impostazioni per procedere!'),
            duration: Duration(seconds: AppConstants.bleScanDurationSeconds),
          ),
        );
        return;
      }
    }

    // Se il Bluetooth è attivo (o è stato appena attivato), procedi con la scansione normale
    setState(() {
      _scanResults.clear();
      _isScanning = true;
      _scanTimeout = false; // Resetta il timeout quando parte una nuova ricerca
    });
    try {
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 300)); // Pausa di sicurezza per il wrapper Android
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: AppConstants.bleScanDurationSeconds),
        withServices: [Guid(AppConstants.serviceUuid)]
      );

print("avvio timer scansione in _startScan");
      // Avvia il timer software per accorgersi del timeout
      _scanTimeoutTimer?.cancel();
      _scanTimeoutTimer = Timer(const Duration(seconds: AppConstants.bleScanDurationSeconds), () {
        if (mounted && _connectedDevice == null) {
          setState(() {
            _scanTimeout = true;
            _isScanning = false;
          });
        }
      });

    } catch (e) {
      print("Errore scansione BT: $e");

      // Resetta lo stato visivo solo in caso di fallimento immediato del pacchetto di avvio
      _scanTimeoutTimer?.cancel();
      setState(() {
        _isScanning = false;
        _scanTimeout = true;
      });
    }
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      _goFullscreen(); // Forza l'orientamento orizzontale istantaneo durante la connessione
      await device.connect(autoConnect: false, license: License.nonprofit);

      // FORZATURA SCRITTURA CRITICA: Memorizza subito l'indirizzo MAC
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.prefMacAddressKey, device.remoteId.toString());

      setState(() {
        _connectedDevice = device;
        _savedMacAddress = device.remoteId.toString();
        _scanTimeout = false;
      });
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == AppConstants.serviceUuid.toLowerCase()) {
          for (var characteristic in service.characteristics) {
            String cUuid = characteristic.uuid.toString().toLowerCase();
            // 1. Aggancia la caratteristica di RICEZIONE dell'ESP32 (Scrittura del telefono)
            if (cUuid == AppConstants.characteristicUuidTx.toLowerCase()) {
              setState(() {
                _txCharacteristic = characteristic;
              });
              //print("Caratteristica TX (Scrittura) Agganciata!");
            }
            // 2. Aggancia la caratteristica di TRASMISSIONE dell'ESP32 (Ascolto del telefono)
            if (cUuid == AppConstants.characteristicUuidRx.toLowerCase()) {
              setState(() {
                _rxCharacteristic = characteristic;
              });
              //print("Caratteristica RX (Notifiche) Agganciata!");
              // Se l'ESP32 invia dati indietro (es. stato batteria, ...), li leggi qui:
              await characteristic.setNotifyValue(true);

              // ROUTINE DI RICEZIONE
              characteristic.onValueReceived.listen((value) {
                String datoStringa = utf8.decode(value).trim();
                datoStringa = datoStringa.replaceAll('%', '');

                if (datoStringa.startsWith("LIGHT_STATE:")) {
                  setState(() {
                    _isLightOn = (datoStringa == "LIGHT_STATE:1");
                  });
                } else if (datoStringa.startsWith("IP:")) {
                  setState(() {
                    _esp32IpAddress = datoStringa.substring(3);
                    print("[BLE] Ricevuto IP dinamico dall'ESP32: $_esp32IpAddress");
                  });
                } else if (datoStringa.startsWith("BATTERY:")) {
                  setState(() {
                    try {
                      // %d = intero, %f = double/float, %s = stringa
                      final scanf = ScanF("BATTERY:%d,%f,%s");
                      final parsed = scanf.match(datoStringa);

                      if (parsed != null && parsed.length >= 3) {
                        int percentuale = parsed[0];
                        double tensione = parsed[1];
                        String stato = parsed[2];

                        _livelloBatteria = percentuale.clamp(0, 100);

                        //print("[SCANF BATTERY] %: $percentuale, Volt: $tensione, Stato: $stato");
                      }
                    } catch (e) {
                      print("Errore nel parsing con pacchetto scanf: $e");
                      _livelloBatteria = 0;
                    }
                  });
                } else { // unknown
                  print("Comando sconosciusto ricevuto: $datoStringa");
                }
                //print("Dati ricevuti dall'ESP32: $datoStringa");
              });
            }
          }
        }
      }

      // Chiamiamo il timer all'esterno del ciclo, solo se la caratteristica TX è pronta
      if (_txCharacteristic != null) {
        //_goFullscreen(); //  spostato a inizio funzione
        _startTransmissionTimer();
        _startKeepaliveTimer();
      } else {
        _exitFullscreen();
        setState(() {
          _connectedDevice = null;
        });
        print("[ERRORE] Caratteristica TX non trovata!");
      }
    } catch (e) {
      _exitFullscreen();
      setState(() {
        _connectedDevice = null;
        _isScanning = false;
      });
      print("Errore connessione BT: $e");
    }
  }

  // Invio dei 4 assi all'ESP32, scollegata dai gestori di tocco diretti. Eseguita solo dal Timer
  void _sendJoystickData() async {
    if (_txCharacteristic == null) return;
    // Converte i valori da float (-1.0 a 1.0) a interi (-100 a 100)
    int trazioneInt = (_trazione * 100).round();
    int sterzoInt = (_sterzo * 100).round();
    int tiltInt = (_tilt * 100).round();
    int liftInt = (_lift * 100).round();

    // Formato: D=Drive/Trazione, S=Sterzo, T=Tilt, L=lift/elevazione
    // Stringa super compatta (es: "D:85,S:-30,T:0,L:45")
    String dataString = "#D:$trazioneInt,S:$sterzoInt,T:$tiltInt,L:$liftInt";
    // Se la stringa è identica (es: fermo o stick bloccati nella stessa posizione), salta l'invio
    if (dataString == _lastSentData) return;
    _lastSentData = dataString;

    try {
      //print("BLE send string: $dataString");
      await _txCharacteristic!.write(utf8.encode(dataString), withoutResponse: true);
    } catch (e) {
      print("Errore trasmissione periodica BLE: $e");
    }
  }

  // Invia un comando speciale per i pulsanti (es. LIGHT:1 o LIGHT:0)
  void _sendAction(String action) async {
    if (_txCharacteristic == null) return;
    try {
      await _txCharacteristic!.write(utf8.encode(action), withoutResponse: false);
    } catch (e) {
      print("Errore luci: $e");
    }
  }

  // Calcola il colore della batteria dinamico in base alle soglie richieste
  Color _getBatteryColor(int valore) {
    if (valore >= 0 && valore <= 25) return Colors.red;
    if (valore > 25 && valore <= 60) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Forza lo sfondo chiaro su tutto lo schermo
      backgroundColor: AppConstants.backgroundColor,
      body: _connectedDevice == null
          ? SafeArea(child: _buildConnectionScreen())
          : _buildForkliftDashboard(), // Rimosso SafeArea per permettere lo schermo intero totale
    );
  }

  // --- SCHERMATA DI CONNESSIONE BLUETOOTH NATIVA ---
  Widget _buildConnectionScreen() {
    return Column(
      children: [
        AppBar(
          title: const Text('FORKLIFT BLE CONTROLLER', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: Icon(_isScanning ? Icons.stop : Icons.bluetooth_searching, color: Colors.blue),
              onPressed: _isScanning ? () { _scanTimeoutTimer?.cancel(); 
	                                    FlutterBluePlus.stopScan();
					    setState(() { _isScanning = false; _scanTimeout = true; });
                                          } : _startScan,
            )
          ],
        ),
        if (_isScanning) const LinearProgressIndicator(color: Colors.blue),
        Expanded(
            child: _savedMacAddress != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Se il timeout NON è scattato mostra la freccia che gira, altrimenti la scambia col pulsante di riavvio
                      if (!_scanTimeout)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 20),
                          child: CircularProgressIndicator(color: Colors.blue),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                            icon: const Icon(Icons.refresh),
                            label: const Text("Riprova Connessione Aut.", style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: _startScan, // Riavvia la scansione senza dover chiudere l'app
                          ),
                        ),
                        Text(
                        _scanTimeout
                            ? "Device non trovato. Verifica che sia acceso!\n($_savedMacAddress)"
                            : "Ricerca automatica device salvato...\n($_savedMacAddress)",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _scanTimeout
                              ? Colors.red.shade700
                              : Colors.black54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 35),
                      // Il pulsante rosso per cancellare la memoria resta qui, sempre visibile
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50),
                        icon: const Icon(Icons.delete, color: Colors.red),
                        label: const Text("Annulla e cerca altri", style: TextStyle(color: Colors.red)),
                        onPressed: _forgetAndDisconnectDevice,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _scanResults.length,
                  itemBuilder: (context, index) {
                    final scanResult = _scanResults[index];
                    final device = scanResult.device;
                    final name = device.platformName.isNotEmpty ? device.platformName : "Dispositivo Sconosciuto";

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
                      color: Colors.white,
                      elevation: 2,
                      child: ListTile(
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                        subtitle: Text(device.remoteId.toString(), style: const TextStyle(color: Colors.black45)),
                        trailing: const Icon(Icons.link, color: Colors.blue),
                        onTap: () {
                          // extract manufacturer data from BLE advertising
                          if (scanResult.advertisementData.manufacturerData.isNotEmpty) {
                            var key = scanResult.advertisementData.manufacturerData.keys.first;
                            List<int>? data = scanResult.advertisementData.manufacturerData[key];

                            if (key == AppConstants.keepAliveAckDataKey && data != null && data.length >= 2) {
                              int ackMs = (data[0] << 8) | data[1];
                              if (ackMs > 0 && ackMs < 5000) {
                                _keepAlivePeriodMs = ackMs;
                                print("_keepAlivePeriodMs rilevato: $_keepAlivePeriodMs ms");
                              }
                            }
                          }
                          _scanTimeoutTimer?.cancel();
                          FlutterBluePlus.stopScan();
                          _connectToDevice(device);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // --- INTERFACCIA COMPLETA A 4 JOYSTICK ---
  Widget _buildForkliftDashboard() {
    return Stack(
      children: [
        // ================= LATO SINISTRO (SFALSATO OTTIMIZZATO) =================
        // 1. Tilt (Piccolo, Alto) -> Spostato più in alto (top: 25) e ingrandito a 140
        Positioned(
          left: AppConstants.smallJoystickHorizontalPadding,
          top: AppConstants.smallJoystickTopPadding,
          child: RawJoystick(
            joystickSize: AppConstants.smallJoystickSize,
            thumbSize: AppConstants.smallJoystickThumbSize,
            value: _tilt,
            isVertical: false,
            color: AppConstants.smallJoystickColor,
            embeddedLabel: "T",
            onChanged: (val) {
              setState(() {
                _tilt = val;
              });
            },
          ),
        ),

        // 2. Steering (Grande, Basso) -> Allontanato verso l'esterno (left: 60) grazie allo spazio verticale guadagnato
        Positioned(
          left: AppConstants.largeJoystickHorizontalPadding,
          bottom: AppConstants.largeJoystickBottomPadding,
          child: RawJoystick(
            joystickSize: AppConstants.largeJoystickSize,
            thumbSize: AppConstants.largeJoystickThumbSize,
            value: _sterzo,
            isVertical: false,
            color: AppConstants.largeJoystickColor,
            embeddedLabel: "S",
            onChanged: (val) {
              setState(() {
                _sterzo = val;
              });
            },
          ),
        ),
        // ================= COLONNA CENTRALE (Batteria + Ingranaggio + Luci) =================
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // La barra della batteria ora si trova qui in alto al centro del cruscotto
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Contenitore esterno della batteria (Bordo nero/grigio)
                  Container(
                    width: AppConstants.batteryWidth,
                    height: AppConstants.batteryHeight,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.black54, width: 2),
                    ),
                    // La barra interna colorata si restringe in base alla percentuale
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        // Calcola la larghezza proporzionale (max 47 pixel liberi interni)
                        width: (47 * (_livelloBatteria / 100)).clamp(0.0, 47.0),
                        decoration: BoxDecoration(
                          color: _getBatteryColor(_livelloBatteria),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                  // Polo positivo della batteria (Il tipico rettangolino sporgente a destra)
                  Container(
                    width: 3,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(2),
                        bottomRight: Radius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              // Pulsante Impostazioni (Ingranaggio)
              IconButton(
                icon: const Icon(
                  Icons.settings,
                  color: AppConstants.centerButtonColor,
                  size: AppConstants.centerButtonIconSize,
                ),
                onPressed: () {
                  // 1. Ferma il timer per non tentare scritture a vuoto
                  _stopTransmissionTimer();
                  _exitFullscreen();
                  // 2. Apri la pagina web
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => WebConfigPage(
                        url: "http://$_esp32IpAddress${AppConstants.webConfigPath}",
                      ),
                    ),
                  ).then((_) async {
                    _goFullscreen();

                    // 3. LOGICA DI RICONNESSIONE AL RITORNO DALLA WEBVIEW
                    if (_connectedDevice != null) {
                      try {
                        // Verifica se il dispositivo si è scollegato in background
                        final state = await _connectedDevice!.connectionState.first;

                        if (state == BluetoothConnectionState.disconnected) {
                          print("[BLE] BLE disconnected! Try reconnecting...");

                          // Tenta la riconnessione rapida
                          await _connectedDevice!.connect(
                                autoConnect: false,
                                license: License.nonprofit
                              ).timeout(const Duration(seconds: AppConstants.bleReconnectTimeoutSeconds));

                          // Riscopre i servizi per riagganciare i canali RX e TX
                          List<BluetoothService> services = await _connectedDevice!.discoverServices();
                          for (var service in services) {
                            if (service.uuid.toString().toLowerCase() == AppConstants.serviceUuid.toLowerCase()) {
                              for (var characteristic in service.characteristics) {
                                String cUuid = characteristic.uuid.toString().toLowerCase();
                                if (cUuid == AppConstants.characteristicUuidRx.toLowerCase()) {
                                  _rxCharacteristic = characteristic;
                                  await characteristic.setNotifyValue(true);
                                }
                                if (cUuid == AppConstants.characteristicUuidTx.toLowerCase()) {
                                  _txCharacteristic = characteristic;
                                }
                              }
                            }
                          }
                          print("[BLE] BLE connected");
                        }

                        // 4. Se il dispositivo è online (o è stato riagganciato), riavvia il timer
                        if (_txCharacteristic != null) {
                          _startTransmissionTimer();
                        }
                      } catch (e) {
                        print("[BLE] Error reconnecting: $e");
                        _exitFullscreen();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('BLE connection lost. Select the device')),
                        );
                        // Resetta lo stato per rimandare l'utente alla schermata di ricerca
                        setState(() {
                          _connectedDevice = null;
                        });
                      }
                    }
                  });
                },
              ),

              const SizedBox(height: 15),
              // Pulsante Luci
              IconButton(
                icon: Icon(
                  _isLightOn ? Icons.lightbulb : Icons.lightbulb_outline,
                  size: AppConstants.centerButtonIconSize,
                  color: _isLightOn
                      ? AppConstants.centerButtonActiveColor
                      : AppConstants.centerButtonColor,
                ),
                onPressed: () {
                  _sendAction("LIGHT:${_isLightOn ? 0 : 1}");
                },
              ),
              const SizedBox(height: 10),
              // TASTO SCOLLEGA SEMPLIFICATO: Cancella la memoria e scollega all'istante
              TextButton.icon(
                icon: const Icon(Icons.logout, color: Colors.black45, size: 16),
                label: const Text("Scollega", style: TextStyle(color: Colors.black45, fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: _forgetAndDisconnectDevice, // Chiama direttamente la routine di pulizia e disconnessione
              ),
            ],
          ),
        ),
        // ================= LATO DESTRO (SFALSATO OTTIMIZZATO) =================
        // 3. Lift (Piccolo, Alto) -> Spostato più in alto (top: 25) e ingrandito a 140
        Positioned(
          right: AppConstants.smallJoystickHorizontalPadding,
          top: AppConstants.smallJoystickTopPadding,
          child: RawJoystick(
            joystickSize: AppConstants.smallJoystickSize,
            thumbSize: AppConstants.smallJoystickThumbSize,
            value: _lift,
            isVertical: true,
            color: AppConstants.smallJoystickColor,
            embeddedLabel: "L",
            onChanged: (val) {
              setState(() {
                _lift = val * -1;
              });
            },
          ),
        ),
        // 4. Speed (Grande, Basso) -> Allontanato verso l'esterno (right: 60) grazie allo spazio verticale guadagnato
        Positioned(
          right: AppConstants.largeJoystickHorizontalPadding,
          bottom: AppConstants.largeJoystickBottomPadding,
          child: RawJoystick(
            joystickSize: AppConstants.largeJoystickSize,
            thumbSize: AppConstants.largeJoystickThumbSize,
            value: _trazione,
            isVertical: true,
            color: AppConstants.largeJoystickColor,
            embeddedLabel: "M",
            onChanged: (val) {
              setState(() {
                _trazione = val * -1;
              });
            },
          ),
        ),
      ],
    );
  }
}
