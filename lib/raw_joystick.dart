import 'package:flutter/material.dart';
import 'constants.dart';

class RawJoystick extends StatefulWidget {
  final double joystickSize;
  final double thumbSize;
  final double value;
  final bool isVertical;
  final Color color;
  final String embeddedLabel;
  final ValueChanged<double> onChanged;

  const RawJoystick({
    super.key,
    required this.joystickSize,
    required this.thumbSize,
    required this.value,
    required this.isVertical,
    required this.color,
    required this.embeddedLabel,
    required this.onChanged,
  });

  @override
  State<RawJoystick> createState() => _RawJoystickState();
}

class _RawJoystickState extends State<RawJoystick> {
  // Traccia la coordinata accumulata del trascinamento relativo
  double _accumulatedOffset = 0.0;

  // Coordinate dinamiche del centro del joystick
  double? _dynamicCenterX;
  double? _dynamicCenterY;

  bool isSmallJoystick(double size) => size < AppConstants.largeJoystickSize;

  @override
  Widget build(BuildContext context) {
    final double iconSize = isSmallJoystick(widget.joystickSize) ? 22.0 : 28.0;

    // Centro geometrico e raggio virtuale di calcolo per la saturazione a 100
    double circleCenter = widget.joystickSize / 2;
    double virtualRadiusMax = circleCenter * 0.75;

    // Calcolo del confine di sicurezza (margine per non far uscire l'anello dallo schermo)
    // Usiamo come limite la metà della dimensione del pomello (thumb), così l'anello non toccherà mai il bordo fisico
    double secureMargin = widget.thumbSize / 2;
    double limitMin = secureMargin;
    double limitMax = widget.joystickSize - secureMargin;

    // Applichiamo il costringimento geometrico (clamp) per tenere il centro sempre dentro i binari sicuri
    // Se non abbiamo ancora toccato lo schermo, il joystick sta nella sua posizione iniziale predefinita (0,0)
    double posX = (_dynamicCenterX ?? circleCenter).clamp(limitMin, limitMax);
    double posY = (_dynamicCenterY ?? circleCenter).clamp(limitMin, limitMax);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      
      // Al tocco iniziale, spostiamo il centro del joystick esattamente sotto il dito, stando nel suo perimetro
      onPanStart: (details) {
        setState(() {
          // Memorizza dove è stato premuto il dito all'interno dell'area circoscritta del widget
          _dynamicCenterX = details.localPosition.dx;
          _dynamicCenterY = details.localPosition.dy;
          
          // Sincronizziamo l'accumulatore partendo da zero (perché il dito è ora al centro)
          _accumulatedOffset = 0.0;
          widget.onChanged(0.0);
        });
      },
      
      // Durante il movimento, calcoliamo i delta progressivi (relativi al nuovo centro)
      onPanUpdate: (details) {
        setState(() {
          if (widget.isVertical) {
            // In Flutter l'asse Y verso il basso è positivo, quindi sommiamo il delta nativo
            _accumulatedOffset += details.delta.dy;
          } else {
            _accumulatedOffset += details.delta.dx;
          }

          // Normalizzazione e saturazione rigorosa tra -1.0 e 1.0
          double normalized = _accumulatedOffset / virtualRadiusMax;
          widget.onChanged(normalized.clamp(-1.0, 1.0));
        });
      },
      
      // Quando il dito si alza, azzeriamo i valori e facciamo ritornare il joystick nella sua posizione estetica di base
      onPanEnd: (_) {
        setState(() {
          _accumulatedOffset = 0.0;
          _dynamicCenterX = null; // Resetta la posizione dinamica
          _dynamicCenterY = null;
          widget.onChanged(0.0);
        });
      },
      
      // RISOLTO: Riportato a widget.joystickSize puro. L'ingombro fantasma scompare e i joystick piccoli sono liberi!
      child: SizedBox(
        width: widget.joystickSize, 
        height: widget.joystickSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // L'anello si sposta ma si ferma tassativamente prima di uscire dai confini dello schermo
            Positioned(
              left: posX - circleCenter,
              top: posY - circleCenter,
              child: Container(
                width: widget.joystickSize,
                height: widget.joystickSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFD1D5DB), 
                  border: Border.all(color: Colors.black12, width: 2),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none, // Mantiene lo sblocco per debordare all'esterno del cerchio grigio
                  children: [
                    // Frecce direzionali di sottofondo nello stile industriale
                    widget.isVertical
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6), 
                                child: Icon(Icons.arrow_drop_up, color: Colors.black26, size: iconSize)
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6), 
                                child: Icon(Icons.arrow_drop_down, color: Colors.black26, size: iconSize)
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 6), 
                                child: Icon(Icons.arrow_left, color: Colors.black26, size: iconSize)
                              ),
                              Padding(
                                padding: const EdgeInsets.only(right: 6), 
                                child: Icon(Icons.arrow_right, color: Colors.black26, size: iconSize)
                              ),
                            ],
                          ),

                    // Il pomello colorato si muove fluido rispetto all'anello centrato senza scattare all'inizio
                    Align(
                      // Moltiplichiamo l'allineamento visivo per permettere un'escursione visiva più ampia oltre l'anello
                      alignment: widget.isVertical 
                          ? Alignment(0, widget.value * -1.4) 
                          : Alignment(widget.value * 1.4, 0),
                      child: Container(
                        width: widget.thumbSize,
                        height: widget.thumbSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.color, 
                          border: Border.all(color: Colors.white24, width: 2),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                        ),
                        child: Center(
                          child: Text(
                            widget.embeddedLabel,
                            style: TextStyle(
                              color: const Color.fromARGB(103, 0, 0, 0),
                              fontSize: isSmallJoystick(widget.joystickSize) ? 14 : 18,
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
            ),
          ],
        ),
      ),
    );
  }
}
