import 'package:flutter/material.dart';

/// Logo de La Percha: una percha sobre un cuadrado redondeado.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size.square(size),
      painter: _LogoPainter(scheme.primary, scheme.onPrimary),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.bg, this.fg);
  final Color bg;
  final Color fg;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 48;
    canvas.save();
    canvas.scale(k);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 48, 48), const Radius.circular(13)),
      Paint()..color = bg,
    );
    final line = Paint()
      ..color = fg
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final hook = Path()
      ..moveTo(24, 17.5)
      ..arcToPoint(const Offset(20.4, 13.9),
          radius: const Radius.circular(3.6), largeArc: true, clockwise: false);
    canvas.drawPath(hook, line);

    final body = Path()
      ..moveTo(24, 17.5)
      ..lineTo(24, 20.5)
      ..lineTo(10.5, 30.4)
      ..arcToPoint(const Offset(11.5, 33.5),
          radius: const Radius.circular(1.7), clockwise: false)
      ..lineTo(36.5, 33.5)
      ..arcToPoint(const Offset(37.5, 30.4),
          radius: const Radius.circular(1.7), clockwise: false)
      ..lineTo(24, 20.5)
      ..close();
    canvas.drawPath(body, line);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.bg != bg || old.fg != fg;
}
