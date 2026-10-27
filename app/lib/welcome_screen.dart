import 'config.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app_state.dart';
import 'auth_sheet.dart';
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
                const Wordmark(size: 24),
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
                final tileH = math.min(210.0, (c.maxHeight - 24) / 2);
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    MarqueeRow(
                        height: tileH,
                        tiles: [for (final c in _categorias.take(5)) _CategoryTile(c)],
                        reverse: false,
                        speed: 26),
                    const SizedBox(height: 12),
                    MarqueeRow(
                        height: tileH,
                        tiles: [for (final c in _categorias.skip(5)) _CategoryTile(c)],
                        reverse: true,
                        speed: 26),
                  ],
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
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton(
                          onPressed: () => showAuthSheet(context, state),
                          child: const Text('Únete a Pavito'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: () =>
                              showAuthSheet(context, state, login: true),
                          child: const Text('Ya tengo una cuenta'),
                        ),
                      ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: Text(
                modoDirecto
                    ? 'Compra y vende ropa y cosas de casa en toda Venezuela. Publicar es gratis y sin comisiones.'
                    : 'Compra y vende ropa y cosas de casa en toda Venezuela. Pago protegido y sin comisión para quien vende.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// Una prenda o artículo por cada categoría de Pavito (fotos incluidas en la app).
const _categorias = [
  ('Mujer', 'mujer'),
  ('Zapatos', 'zapatos'),
  ('Niños', 'ninos'),
  ('Hogar', 'hogar'),
  ('Deportes', 'deportes'),
  ('Hombre', 'hombre'),
  ('Accesorios', 'accesorios'),
  ('Bebés', 'bebes'),
  ('Libros y juegos', 'libros'),
  ('Mascotas', 'mascotas'),
];

class _CategoryTile extends StatelessWidget {
  const _CategoryTile(this.c);
  final (String, String) c;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.72,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(fit: StackFit.expand, children: [
          Image.asset('assets/bienvenida/${c.$2}.jpg',
              fit: BoxFit.cover, gaplessPlayback: true),
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Text(c.$1,
                  style: const TextStyle(
                      color: LP.ink, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        ]),
      ),
    );
  }
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
    })
      ..start();
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
