import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Logo de Pavito: una percha sobre un cuadrado redondeado.
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
      ..strokeWidth = 2.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Gancho: arco que sube desde el cuello y se curva a la izquierda.
    final hook = Path()
      ..arcTo(Rect.fromCircle(center: const Offset(24, 12.4), radius: 4.4),
          math.pi, 1.5 * math.pi, true);
    canvas.drawPath(hook, line);

    final body = Path()
      ..moveTo(24, 16.8)
      ..lineTo(24, 20.5)
      ..lineTo(10.9, 30.1)
      ..lineTo(11.5, 33.6)
      ..lineTo(36.5, 33.6)
      ..lineTo(37.1, 30.1)
      ..lineTo(24, 20.5);
    canvas.drawPath(body, line);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.bg != bg || old.fg != fg;
}
