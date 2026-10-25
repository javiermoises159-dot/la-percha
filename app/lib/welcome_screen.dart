import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app_state.dart';
import 'auth_sheet.dart';
import 'listing.dart';
import 'logo.dart';
import 'theme.dart';

/// Bienvenida: dos filas de prendas que se deslizan solas en sentidos opuestos,
/// un titular y los botones de entrada.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(children: [
                const LogoMark(size: 30),
                const SizedBox(width: 8),
                Text('La Percha', style: display(20, color: ink)),
                const Spacer(),
                TextButton(
                  onPressed: state.continueAsGuest,
                  child: Text('Omitir', style: TextStyle(color: context.muted)),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                // Las filas se adaptan a la altura disponible.
                final tileH = math.min(170.0, (c.maxHeight - 24) / 2);
                return ListenableBuilder(
                  listenable: listingsStore,
                  builder: (context, _) {
                    final photos = [
                      for (final l in listingsStore.all)
                        if (l.photos.isNotEmpty) l.photos.first
                    ];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        MarqueeRow(
                            height: tileH,
                            tiles: _tiles(photos, 0),
                            reverse: false,
                            speed: 26),
                        const SizedBox(height: 12),
                        MarqueeRow(
                            height: tileH,
                            tiles: _tiles(photos, 3),
                            reverse: true,
                            speed: 26),
                      ],
                    );
                  },
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                'Lo que ya no usas, otra persona lo va a querer.',
                textAlign: TextAlign.center,
                style: display(28, color: ink, height: 1.12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(children: [
                FilledButton(
                  onPressed: () => showAuthSheet(context, state),
                  child: const Text('Únete a La Percha'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => showAuthSheet(context, state, login: true),
                  child: const Text('Ya tengo una cuenta'),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: Text(
                'Compra y vende ropa usada en toda Venezuela. Pago protegido y sin comisión para quien vende.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mezcla fotos reales (si ya hay anuncios) con ilustraciones de prendas.
  List<Widget> _tiles(List<String> photos, int offset) {
    final out = <Widget>[];
    for (var i = 0; i < 8; i++) {
      final k = i + offset;
      if (photos.isNotEmpty && i % 2 == 1) {
        out.add(_PhotoTile(url: photos[(k ~/ 2) % photos.length]));
      } else {
        out.add(_GarmentTile(kind: k % 6, color: _pastels[k % _pastels.length]));
      }
    }
    return out;
  }
}

const _pastels = [
  Color(0xFFF2D4DC), Color(0xFFCFE0EE), Color(0xFFE9E1C4),
  Color(0xFFD3E6D6), Color(0xFFF1D9C8), Color(0xFFDCD3EC),
];

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.72,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: context.chip)),
      ),
    );
  }
}

class _GarmentTile extends StatelessWidget {
  const _GarmentTile({required this.kind, required this.color});
  final int kind;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.72,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          color: color,
          child: CustomPaint(painter: _GarmentPainter(kind)),
        ),
      ),
    );
  }
}

/// Siluetas sencillas de prendas.
class _GarmentPainter extends CustomPainter {
  _GarmentPainter(this.kind);
  final int kind;

  static const _shapes = <List<Offset>>[
    // camiseta
    [Offset(.30, .15), Offset(.42, .15), Offset(.50, .22), Offset(.58, .15),
     Offset(.70, .15), Offset(.88, .32), Offset(.78, .42), Offset(.70, .36),
     Offset(.70, .88), Offset(.30, .88), Offset(.30, .36), Offset(.22, .42),
     Offset(.12, .32)],
    // vestido
    [Offset(.38, .10), Offset(.44, .10), Offset(.50, .20), Offset(.56, .10),
     Offset(.62, .10), Offset(.60, .34), Offset(.76, .88), Offset(.24, .88),
     Offset(.40, .34)],
    // pantalón
    [Offset(.28, .10), Offset(.72, .10), Offset(.78, .90), Offset(.55, .90),
     Offset(.50, .38), Offset(.45, .90), Offset(.22, .90)],
    // bolso (se dibuja aparte)
    [],
    // zapato
    [Offset(.12, .56), Offset(.40, .40), Offset(.55, .50), Offset(.88, .60),
     Offset(.90, .76), Offset(.12, .76)],
    // chaqueta
    [Offset(.30, .12), Offset(.42, .12), Offset(.50, .20), Offset(.58, .12),
     Offset(.70, .12), Offset(.90, .40), Offset(.90, .82), Offset(.78, .82),
     Offset(.74, .44), Offset(.70, .42), Offset(.70, .88), Offset(.30, .88),
     Offset(.30, .42), Offset(.26, .44), Offset(.22, .82), Offset(.10, .82),
     Offset(.10, .40)],
  ];

  @override
  void paint(Canvas canvas, Size s) {
    final fill = Paint()..color = Colors.white.withAlpha(170);
    Offset p(Offset o) => Offset(o.dx * s.width, o.dy * s.height);
    if (kind == 3) {
      final body = RRect.fromRectAndRadius(
          Rect.fromLTRB(.18 * s.width, .42 * s.height, .82 * s.width, .86 * s.height),
          Radius.circular(s.width * .08));
      canvas.drawRRect(body, fill);
      final handle = Paint()
        ..color = Colors.white.withAlpha(170)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.width * .05
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
          Rect.fromLTRB(.32 * s.width, .18 * s.height, .68 * s.width, .62 * s.height),
          math.pi, math.pi, false, handle);
      return;
    }
    final pts = _shapes[kind];
    final path = Path()..moveTo(p(pts.first).dx, p(pts.first).dy);
    for (final o in pts.skip(1)) {
      path.lineTo(p(o).dx, p(o).dy);
    }
    path.close();
    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(_GarmentPainter old) => old.kind != kind;
}

/// Fila que se desliza sola y sin fin.
class MarqueeRow extends StatefulWidget {
  const MarqueeRow(
      {super.key,
      required this.height,
      required this.tiles,
      required this.reverse,
      required this.speed});
  final double height;
  final List<Widget> tiles;
  final bool reverse;
  final double speed; // píxeles por segundo

  @override
  State<MarqueeRow> createState() => _MarqueeRowState();
}

class _MarqueeRowState extends State<MarqueeRow>
    with SingleTickerProviderStateMixin {
  final _ctrl = ScrollController();
  late final Ticker _ticker;
  static const _gap = 10.0;

  double get _tileW => widget.height * 0.72;
  double get _setW => widget.tiles.length * (_tileW + _gap);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (!_ctrl.hasClients) return;
      final off = (elapsed.inMicroseconds / 1e6 * widget.speed) % _setW;
      _ctrl.jumpTo(widget.reverse ? _setW - off : off);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // El conjunto se repite 4 veces para que nunca se vea un hueco.
    final all = [for (var r = 0; r < 4; r++) ...widget.tiles];
    return SizedBox(
      height: widget.height,
      child: ListView.separated(
        controller: _ctrl,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: all.length,
        separatorBuilder: (_, __) => const SizedBox(width: _gap),
        itemBuilder: (_, i) => SizedBox(width: _tileW, child: all[i]),
      ),
    );
  }
}
