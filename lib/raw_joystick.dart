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

    return GestureDetector(
      onVerticalDragUpdate: isVertical ? (details) {
        double center = joystickSize / 2;
        double offset = details.localPosition.dy;
        double normalized = (offset - center) / center;
        onChanged(normalized.clamp(-1.0, 1.0));
      } : null,
      onHorizontalDragUpdate: !isVertical ? (details) {
        double center = joystickSize / 2;
        double offset = details.localPosition.dx;
        double normalized = (offset - center) / center;
        onChanged(normalized.clamp(-1.0, 1.0));
      } : null,
        // RISOLTO: Aggiunto il parametro (_) per renderlo compatibile con GestureDragEndCallback
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
          children: [
            // Frecce direzionali distanziate
            isVertical
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: 6), 
                        child: Icon(Icons.arrow_drop_up, color: Colors.black26, size: iconSize)
                      ),
                      Padding(
                        padding: EdgeInsets.only(bottom: 6), 
                        child: Icon(Icons.arrow_drop_down, color: Colors.black26, size: iconSize)
                      ),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(left: 6), 
                        child: Icon(Icons.arrow_left, color: Colors.black26, size: iconSize)
                      ),
                      Padding(
                        padding: EdgeInsets.only(right: 6), 
                        child: Icon(Icons.arrow_right, color: Colors.black26, size: iconSize)
                      ),
                    ],
                  ),

            // Pomello mobile (Thumb) con la lettera dell'asse
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
