import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Blocca lo schermo in Landscape (Orizzontale)
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // Attiva lo schermo intero totale nascondendo le barre di Android
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      //Forza il tema chiaro per disattivare la Dark Mode del telefono
      themeMode: ThemeMode.light, 
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF0F2F5), // Sfondo Grigio Chiaro / Bianco Ghiaccio
      ),
      //theme: ThemeData.dark().copyWith(
      //  scaffoldBackgroundColor: const Color(0xFF141519), // Grigio scuro di fondo hi-tech
      //),
      home: const RcControllerPage(),
    );
  }
}

class RcControllerPage extends StatefulWidget {
  const RcControllerPage({super.key});

  @override
  State<RcControllerPage> createState() => _RcControllerPageState();
}

class _RcControllerPageState extends State<RcControllerPage> {
  // Assi dei Joystick (-1.0 a 1.0)
  double _trazione = 0.0; // Speed (Verticale)
  double _sterzo = 0.0;    // Steering (Orizzontale)

  // Canali di controllo ausiliari (Piccoli)
  double _tilt = 0.0;     // Inclinazione (Orizzontale)
  double _lift = 0.0;     // Elevazione (Verticale)
  bool _isLightOn = false; // Controllato direttamente dal feedback dell'ESP32

  String _lastSentData = "";

  // Timer per l'invio periodico temporizzato (Rate Limiting)
  Timer? _transmissionTimer;

  // Configurazione Bluetooth BLE

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _rxCharacteristic;
  BluetoothCharacteristic? _txCharacteristic; 
  
  bool _isScanning = false;
  List<ScanResult> _scanResults = [];
  StreamSubscription? _scanSubscription;
  // Variabili per la gestione dinamica della batteria
  int _livelloBatteria = 100; // Valore numerico di default

// UUID del firmware
  final String _serviceUuid = "fc96f65e-318a-4001-84bd-77e9d12af44b";
  final String _characteristicUuidRx  = "94b43599-5ea2-41e7-9d99-6ff9b904ae3a";
  final String _characteristicUuidTx = "04d3552e-b9b3-4be6-a8b4-aa43c4507c4d";
  @override
  void initState() {
    super.initState();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _scanResults = results;
	});
    });
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _stopTransmissionTimer(); // Ferma il timer se si esce dalla pagina
    super.dispose();
  }

  // Avvia il loop di trasmissione periodica appena l'ESP32 è connesso
  void _startTransmissionTimer() {
    _stopTransmissionTimer();
    // Invia i dati aggregati dei joystick in modo fisso ogni 120 millisecondi
    _transmissionTimer = Timer.periodic(const Duration(milliseconds: 120), (timer) {
      _sendJoystickData();
    });
  }

  void _stopTransmissionTimer() {
    _transmissionTimer?.cancel();
    _transmissionTimer = null;
  }

  void _startScan() async {
    if (_isScanning) return;
    // Controllo di sicurezza: l'antenna del telefono è accesa?
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      print("Errore: Il Bluetooth del telefono è SPENTO!");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attiva il Bluetooth dello smartphone!')),
      );
      return;
    }

    setState(() {
     _scanResults.clear();
     _isScanning = true;
      });
    try {
      await FlutterBluePlus.stopScan(); 
      await Future.delayed(const Duration(milliseconds: 200)); // Pausa di sicurezza per il wrapper Android
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    } catch (e) {
      print("Errore scansione BT: $e");
    }
    setState(() {
      _isScanning = false;
      });
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: false, license: License.nonprofit);
      setState(() {
        _connectedDevice = device;
      });

      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == _serviceUuid.toLowerCase()) {
          for (var characteristic in service.characteristics) {
            String cUuid = characteristic.uuid.toString().toLowerCase();
            // 1. Aggancia la caratteristica di RICEZIONE dell'ESP32 (Scrittura del telefono)
            if (cUuid == _characteristicUuidTx.toLowerCase()) {
              setState(() {
                _txCharacteristic = characteristic;
              });
              print("Caratteristica TX (Scrittura) Agganciata!");
            }
            // 2. Aggancia la caratteristica di TRASMISSIONE dell'ESP32 (Ascolto del telefono)
            if (cUuid == _characteristicUuidRx.toLowerCase()) {
              setState(() {
                _rxCharacteristic = characteristic;
              });
              print("Caratteristica RX (Notifiche) Agganciata!");
              // Se l'ESP32 invia dati indietro (es. stato batteria, ...), li leggi qui:
              await characteristic.setNotifyValue(true);
              
              // ROUTINE DI RICEZIONE 
              characteristic.onValueReceived.listen((value) {
                String datoStringa = utf8.decode(value).trim();
                datoStringa = datoStringa.replaceAll('%', '');
                
                if (datoStringa.startsWith("LUCE_STATO:")) {
                  setState(() {
                    _isLightOn = (datoStringa == "LUCE_STATO:1");
                  });
                } else {
                  setState(() {
		    // Rimuove eventuali simboli '%' se inviati dall'ESP32 per estrarre solo il numero
                    _livelloBatteria = int.tryParse(datoStringa.replaceAll('%', '')) ?? 100;
                  });
                }
		print("Dati ricevuti dall'ESP32: $datoStringa");
              });
            }
          }
        }
      }
    } catch (e) {
      print("Errore connessione: $e");
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

    // Formato: L=Trazione, R=Sterzo, T=Tilt, V=leVazione (Elevazione)
     // Stringa super compatta (es: "L:85,R:-30,T:0,V:45")
    String dataString = "L:$trazioneInt,R:$sterzoInt,T:$tiltInt,V:$liftInt";
    //String dataString = "L:${_trazione.toStringAsFixed(2)},R:${_sterzo.toStringAsFixed(2)},T:${_tilt.toStringAsFixed(2)},V:${_lift.toStringAsFixed(2)}";
    // Se la stringa è identica (es: muletto fermo o stick bloccati nella stessa posizione), salta l'invio
    if (dataString == _lastSentData) return;
    _lastSentData = dataString;

    try {
      await _txCharacteristic!.write(utf8.encode(dataString), withoutResponse: true);
    } catch (e) {
      print("Errore trasmissione: $e");
    }
  }

  // Invia un comando speciale per i pulsanti (es. LUCE:1 o LUCE:0)
  void _sendAction(String action) async {
    if (_txCharacteristic == null) return;
    try {
      await _txCharacteristic!.write(utf8.encode(action), withoutResponse: false);
    } catch (e) {
      print("Errore pulsante: $e");
    }
  }

  // Calcola il colore della batteria dinamico in base alle soglie richieste
  Color _getBatteryColor(int valore) {
    if (valore >= 0 && valore <= 25) {
      return Colors.red; // Tra 0 e 25 -> Rosso
    } else if (valore > 25 && valore <= 70) {
      return Colors.orange; // Tra 25 e 70 -> Giallo/Arancione
    } else {
      return Colors.green; // Tra 70 e 100 -> Verde
    }
  }

  bool _isSmallJoystick(double size) => size < 130;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Forza lo sfondo chiaro su tutto lo schermo
      backgroundColor: const Color(0xFFF0F2F5),
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
              onPressed: _isScanning ? () => FlutterBluePlus.stopScan() : _startScan,
            )
          ],
        ),
        if (_isScanning) const LinearProgressIndicator(color: Colors.blue),
        Expanded(
          child: ListView.builder(
            itemCount: _scanResults.length,
            itemBuilder: (context, index) {
              final device = _scanResults[index].device;
              final name = device.platformName.isNotEmpty ? device.platformName : "Dispositivo Sconosciuto";
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
                color: Colors.white,
                elevation: 2,
                child: ListTile(
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                  subtitle: Text(device.remoteId.toString(), style: const TextStyle(color: Colors.black45)),
                  trailing: const Icon(Icons.link, color: Colors.blue),
                  onTap: () => _connectToDevice(device),
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
        // Barra superiore: Segnale di Connessione e Livello Batteria DINAMICO
        Positioned(
          top: 10,
          left: 20,
          right: 20,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.wifi, color: Colors.green, size: 12),
                  SizedBox(width: 8),
                  Text("CONNECTED", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace')),
                ],
              ),
              // --- INDICATORE GRAFICO DELLA BATTERIA A BARRA ---
              Row(
                children: [
                  // Contenitore esterno della batteria (Bordo nero/grigio)
                  Container(
                    width: 55,
                    height: 15,
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
            ],
          ),
        ),

        // ================= LATO SINISTRO (SFALSATO COERENTE) =================
        // 1. Tilt (Piccolo, Alto) -> Esterno (left: 20, top: 45)
        Positioned(
          left: 20,
          top: 45,
          child: _buildRawJoystick(
            joystickSize: 120.0, thumbSize: 46.0, value: _tilt, isVertical: false, color: Colors.green, 
            embeddedLabel: "T", 
            onChanged: (val) { setState(() { _tilt = val; }); }
          ),
        ),

        // 2. Steering (Grande, Basso) -> Rientrato a specchio (left: 110, bottom: 15) Dimensione aumentata a 180
        Positioned(
          left: 110,
          bottom: 15,
          child: _buildRawJoystick(
            joystickSize: 180.0, thumbSize: 64.0, value: _sterzo, isVertical: false, color: Colors.amber, 
            embeddedLabel: "S", 
            onChanged: (val) { setState(() { _sterzo = val; }); }
),
),
        // ================= SEZIONE CENTRALE (Pulsanti Home e Luci) =================
	Center(
	  child: Column(
	    mainAxisAlignment: MainAxisAlignment.center,
	    children: [
	      const SizedBox(height: 40),
	      IconButton(
	        icon: const Icon(Icons.home, size: 45, color: Colors.blueAccent),
		onPressed: () => _sendAction("HOME:1"),
	      ),
	      const SizedBox(height: 20),
	      IconButton(
	        icon: Icon(
		  _isLightOn ? Icons.lightbulb : Icons.lightbulb_outline,
		  size: 45,
		  color: _isLightOn ? Colors.yellow : Colors.blueAccent
		),
		onPressed: () {
		  _sendAction("LUCE:${_isLightOn ? 0 : 1}");
		},
	      ),
	    ],
	  ),
	),
        // ================= LATO DESTRO (SFALSATO COERENTE) =================
        // 3. Lift (Piccolo, Alto) -> Esterno (right: 20, top: 45) Dimensione aumentata a 120
        Positioned(
          right: 20,
          top: 45,
          child: _buildRawJoystick(
            joystickSize: 120.0, thumbSize: 46.0, value: _lift, isVertical: true, color: Colors.green,
            embeddedLabel: "L",
            onChanged: (val) { setState(() { _lift = val * -1; }); }
          ),
        ),
        // 4. Speed (Grande, Basso) -> Rientrato a specchio (right: 110, bottom: 15) Dimensione aumentata a 180
        Positioned(
          right: 110,
          bottom: 15,
          child: _buildRawJoystick(
            joystickSize: 180.0, thumbSize: 64.0, value: _trazione, isVertical: true, color: Colors.amber,
            embeddedLabel: "M",
            onChanged: (val) { setState(() { _trazione = val * -1; }); }
          ),
        ),
      ],
    );
  }
  // ================= COSTRUTTORE GRAFICO REALE DEI JOYSTICK CON TESTO EMBEDDED =================
  Widget _buildRawJoystick({
    required double joystickSize,
    required double thumbSize,
    required double value,
    required bool isVertical,
    required Color color,
    required String embeddedLabel,
    required ValueChanged onChanged,
    }) {
      return GestureDetector(
        onPanUpdate: (details) {
          double center = joystickSize / 2;
          double offset = isVertical ? details.localPosition.dy : details.localPosition.dx;
          double normalized = (offset - center) / center;
          onChanged(normalized.clamp(-1.0, 1.0));
        },
        onPanEnd: (_) => onChanged(0.0),
        child: Container(
          width: joystickSize,
          height: joystickSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFD1D5DB),
            border: Border.all(color: Colors.black12, width: 2),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Indicatori a freccia di direzione
              isVertical
              ? const Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.arrow_drop_up, color: Colors.black12, size: 18)),
                  Padding(padding: EdgeInsets.only(bottom: 4), child: Icon(Icons.arrow_drop_down, color: Colors.black12, size: 18)),
                ],
              )
              : const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.arrow_left, color: Colors.black12, size: 18)),
                  Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.arrow_right, color: Colors.black12, size: 18)),
                  ],
                ),
                // Pomello mobile (Thumb) completo di ombra 3D e mirino centrale
                Align(
                  alignment: isVertical ? Alignment(0, value * -1) : Alignment(value, 0),
                  child: Container(
                    width: thumbSize,
                    height: thumbSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      border: Border.all(color: Colors.white24, width: 2),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                    ),
                    child: Center(
                      child: Text(
                        embeddedLabel,
                        style: TextStyle(
                          color: const Color.fromARGB(103, 0, 0, 0),
                          fontSize: _isSmallJoystick(joystickSize) ? 14 : 18,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
}
