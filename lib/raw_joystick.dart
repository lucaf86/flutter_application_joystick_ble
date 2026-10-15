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

  bool isSmallJoystick(double size) => size < AppConstants.largeJoystickSize;

  @override
  Widget build(BuildContext context) {
    // Calcola dinamicamente la dimensione delle frecce in base alla grandezza del joystick

    final double iconSize = isSmallJoystick(widget.joystickSize) ? 33.0 : 42.0;

    // Centro geometrico e raggio virtuale di calcolo per la saturazione a 100
    double centroAnello = widget.joystickSize / 2;
    double raggioMassimoCalcolo = centroAnello * 0.75;

    return GestureDetector(
      // 1. Quando il dito tocca lo schermo, sincronizziamo l'accumulatore sul valore corrente del joystick
      onPanStart: (_) {
        setState(() {
          _accumulatedOffset = widget.value * raggioMassimoCalcolo;
        });
      },
      // 2. Durante il movimento, sommiamo solo lo spostamento relativo (delta) senza fare salti assoluti
      onPanUpdate: (details) {
        setState(() {
          if (widget.isVertical) {
            // In Flutter l'asse Y verso il basso è positivo, quindi sommiamo il delta nativo
            _accumulatedOffset += details.delta.dy;
          } else {
            _accumulatedOffset += details.delta.dx;
          }

          // Normalizzazione e saturazione rigorosa tra -1.0 e 1.0
          double normalized = _accumulatedOffset / raggioMassimoCalcolo;
          widget.onChanged(normalized.clamp(-1.0, 1.0));
        });
      },
      // 3. Quando il dito si alza, azzeriamo tutto e il joystick ritorna al centro
      onPanEnd: (_) {
        setState(() {
          _accumulatedOffset = 0.0;
          widget.onChanged(0.0);
        });
      },
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

            // Il pomello si muoverà in modo fluido partendo dal centro senza più scattare all'inizio
            Align(
              // Moltiplichiamo l'allineamento visivo per permettere un'escursione visiva più ampia oltre l'anello
              alignment: widget.isVertical ? Alignment(0, widget.value * -1.4) : Alignment(widget.value * 1.4, 0),
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
    );
  }
}
