import 'package:flutter/material.dart';
import 'constants.dart';

class RawJoystick extends StatelessWidget {
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

  bool isSmallJoystick(double size) => size < AppConstants.largeJoystickSize;

  @override
  Widget build(BuildContext context) {
    // Calcola dinamicamente la dimensione delle frecce in base alla grandezza del joystick
    final double iconSize = isSmallJoystick(joystickSize) ? 33.0 : 42.0;

    // Il centro geometrico dell'anello di fondo grigio
    double centroAnello = joystickSize / 2;
    
    // Definiamo il raggio massimo virtuale di calcolo
    // Questo è il limite oltre cui il dato inviato si satura a 100 o -100
    double raggioMassimoCalcolo = centroAnello * 0.75; 

    return GestureDetector(
      onVerticalDragUpdate: isVertical ? (details) {
        double offsetDito = details.localPosition.dy;
        double distanzaDalCentro = offsetDito - centroAnello;
        // Calcolo della coordinata normalizzata
        double normalized = SampleMath.compute(distanzaDalCentro, raggioMassimoCalcolo);
        onChanged(normalized);
      } : null,
      onHorizontalDragUpdate: !isVertical ? (details) {
        double offsetDito = details.localPosition.dx;
        double distanzaDalCentro = offsetDito - centroAnello;
        double normalized = SampleMath.compute(distanzaDalCentro, raggioMassimoCalcolo);
        onChanged(normalized);
      } : null,
      onVerticalDragEnd: isVertical ? (_) => onChanged(0.0) : null,
      onHorizontalDragEnd: !isVertical ? (_) => onChanged(0.0) : null,
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
          clipBehavior: Clip.none, // FONDAMENTALE: Impedisce a Flutter di tagliare il pomello quando esce dal cerchio grigio!
          children: [
            // Frecce direzionali di sottofondo nello stile industriale
            isVertical
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

            // Il pomello mobile (Thumb) sbloccato. Può debordare liberamente all'esterno.
            Align(
              // Moltiplichiamo l'allineamento visivo per permettere un'escursione visiva più ampia oltre l'anello
              alignment: isVertical ? Alignment(0, value * -1.4) : Alignment(value * 1.4, 0),
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
                      fontSize: isSmallJoystick(joystickSize) ? 14 : 18,
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

// Classe di utilità per isolare i calcoli matematici di saturazione
class SampleMath {
  static double compute(double distanza, double raggioMassimo) {
    double risultato = distanza / raggioMassimo;
    return risultato.clamp(-1.0, 1.0);
  }
}
