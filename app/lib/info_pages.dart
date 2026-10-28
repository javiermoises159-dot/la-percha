import 'package:flutter/material.dart';

import 'terminos.dart';

/// Página de texto simple (ayuda, legales, funciones próximas).
class InfoPage extends StatelessWidget {
  const InfoPage({super.key, required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(body, style: const TextStyle(fontSize: 16, height: 1.5)),
        const SizedBox(height: 24),
      ]),
    );
  }
}

const _draft =
    '\n\n(Borrador informativo. Será revisado por un abogado antes del lanzamiento oficial.)';

const guideText = '''Cómo funciona Pavito

Comprar
1. Busca una prenda y ábrela.
2. Escribe al vendedor si tienes dudas.
3. Compra con "Compra protegida": tu dinero queda retenido y solo se entrega al vendedor cuando confirmas que recibiste la prenda.

Vender
1. Ve a "Vender", sube una foto y rellena los datos.
2. Cuando alguien compre, envía la prenda y marca el envío.
3. Cobras el precio completo: el vendedor no paga comisión.

Consejos
- Toma fotos con buena luz y muestra los detalles.
- Describe el estado con honestidad.
- Nunca pagues ni cobres fuera de Pavito: así no tendrás protección.''';

const helpText = '''Centro de ayuda

¿Algún problema con una compra o una venta? Escríbenos y lo revisamos.

Importante para tu seguridad
- Pavito nunca te pedirá tu contraseña por mensaje.
- No pagues por fuera de la app ni compartas códigos.
- Si algo no parece normal, usa la opción de denunciar o escríbenos.

Contacto de soporte: se publicará aquí antes del lanzamiento.''';

const aboutText =
    '''Pavito es un mercado de ropa usada para toda Venezuela. Queremos que la ropa tenga una segunda vida, que vender sea gratis y que comprar sea seguro.

Versión de prueba.''';

const legalText = '''Notas legales

Pavito es una plataforma que conecta a personas que compran y venden ropa usada. Las prendas las venden usuarios particulares.$_draft''';

const privacyText = '''Política de privacidad

Qué datos guardamos
- Tu correo, nombre de usuario y ciudad.
- Tus anuncios, fotos, favoritos y mensajes.

Quién los ve
- Tu nombre de usuario, ciudad y anuncios son públicos.
- Tu correo y tus mensajes solo los ves tú y la persona con quien hablas.

Tus derechos
- Puedes cambiar tus datos o eliminar tu cuenta desde Ajustes.

Nunca vendemos tus datos.$_draft''';

const cookiesText = '''Cookies

Pavito usa cookies y almacenamiento en tu dispositivo para mantener tu sesión y que la app funcione, y, si lo aceptas, un identificador anónimo para contar visitas a los anuncios. No usamos cookies de publicidad. Puedes ver el detalle y cambiar tu elección en Yo → Cookies.''';

/// Términos completos de Pavito, con títulos, listas y tablas.
class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Términos y condiciones')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [MarkdownLite(terminosMd)],
        ),
      ),
    );
  }
}

/// Markdown mínimo: ##/### títulos, listas "1." y "-", **negrita** y tablas.
/// Las tablas se muestran como tarjetas apiladas para que se lean en el móvil.
class MarkdownLite extends StatelessWidget {
  const MarkdownLite(this.source, {super.key});
  final String source;

  static final _num = RegExp(r'^(\s*)(\d+)\.\s+(.*)$');
  static final _bul = RegExp(r'^(\s*)[-*]\s+(.*)$');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge!.copyWith(fontSize: 15.5, height: 1.5);
    final muted = theme.colorScheme.onSurface.withValues(alpha: .65);
    final line = theme.dividerColor;
    final out = <Widget>[];
    final lines = source.split('\n');
    var i = 0;
    while (i < lines.length) {
      final l = lines[i];
      if (l.trim().isEmpty) {
        i++;
        continue;
      }
      if (l.startsWith('## ')) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 8),
          child: Text(l.substring(3),
              style: base.copyWith(fontSize: 20, fontWeight: FontWeight.w800, height: 1.25)),
        ));
        i++;
        continue;
      }
      if (l.startsWith('### ')) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(l.substring(4),
              style: base.copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
        ));
        i++;
        continue;
      }
      if (l.startsWith('|')) {
        final rows = <List<String>>[];
        while (i < lines.length && lines[i].startsWith('|')) {
          final cells = lines[i]
              .trim()
              .replaceAll(RegExp(r'^\||\|$'), '')
              .split('|')
              .map((c) => c.trim())
              .toList();
          if (!cells.every((c) => RegExp(r'^:?-{3,}:?$').hasMatch(c))) rows.add(cells);
          i++;
        }
        if (rows.isEmpty) continue;
        final head = rows.first;
        for (final r in rows.skip(1)) {
          out.add(Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var c = 0; c < r.length; c++)
                Padding(
                  padding: EdgeInsets.only(top: c == 0 ? 0 : 6),
                  child: c == 0
                      ? Text.rich(_inline(r[c], base.copyWith(fontWeight: FontWeight.w700)))
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c < head.length ? head[c] : '',
                              style: base.copyWith(fontSize: 12.5, color: muted, height: 1.3)),
                          Text.rich(_inline(r[c], base)),
                        ]),
                ),
            ]),
          ));
        }
        continue;
      }
      final n = _num.firstMatch(l);
      final b = _bul.firstMatch(l);
      if (n != null || b != null) {
        final indent = (n?.group(1) ?? b!.group(1)!).length;
        final mark = n != null ? '${n.group(2)}.' : '•';
        final text = n?.group(3) ?? b!.group(2)!;
        out.add(Padding(
          padding: EdgeInsets.only(left: indent > 0 ? 22 : 0, bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 24, child: Text(mark, style: base.copyWith(fontWeight: FontWeight.w700))),
            Expanded(child: Text.rich(_inline(text, base))),
          ]),
        ));
        i++;
        continue;
      }
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text.rich(_inline(l, base)),
      ));
      i++;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }

  static TextSpan _inline(String s, TextStyle style) {
    final parts = s.split('**');
    return TextSpan(style: style, children: [
      for (var k = 0; k < parts.length; k++)
        TextSpan(
            text: parts[k],
            style: k.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null),
    ]);
  }
}
