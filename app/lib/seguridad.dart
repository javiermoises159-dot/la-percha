import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// Guía de seguridad: ejemplos reales de estafas y cómo cuidarse.
/// Se muestra una vez antes de la primera venta y siempre se puede abrir desde "Yo".
const _claveVisto = 'pv_seguridad_v1';

Future<void> mostrarSeguridadSiPrimeraVez(BuildContext context) async {
  try {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_claveVisto) == true) return;
    await p.setBool(_claveVisto, true);
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  await Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const SeguridadPage()));
}

class _Paso {
  const _Paso(this.icono, this.titulo, this.texto, {this.ejemplo, this.consejos});
  final IconData icono;
  final String titulo;
  final String texto;
  final String? ejemplo; // mensaje de estafa de muestra
  final List<String>? consejos;
}

const _pasos = <_Paso>[
  _Paso(
    Icons.shield_outlined,
    'Antes de empezar, aprende a usar Pavito con seguridad',
    'A veces los estafadores buscan a quienes venden por primera vez. Conoce sus trucos y cuídate.',
    consejos: [
      'Mira ejemplos reales de estafas',
      'Descubre cómo vender con seguridad',
      'Aprende a denunciar mensajes sospechosos',
    ],
  ),
  _Paso(
    Icons.chat_bubble_outline,
    'Quédate dentro de Pavito',
    'Los estafadores te piden hablar por WhatsApp o pagarte por fuera (Pago Móvil, Zinli, Binance) para saltarse la protección. En Pavito el pago queda retenido hasta que el comprador confirma que recibió su prenda.',
    ejemplo:
        'Hola, me interesa 😍 Escríbeme al WhatsApp y te pago directo, así nos ahorramos la comisión.',
    consejos: [
      'Conversa y negocia solo en el chat de Pavito',
      'Nunca aceptes pagos por fuera de la app',
    ],
  ),
  _Paso(
    Icons.receipt_long_outlined,
    'No envíes nada por una captura',
    'Un comprobante de pago puede ser falso. No entregues ni envíes la prenda hasta que Pavito te avise que el pago está retenido.',
    ejemplo:
        'Ya te pagué por Pago Móvil, mira el comprobante 📸 Envía hoy mismo que lo necesito urgente!!',
    consejos: [
      'Revisa el estado del pedido dentro de Pavito, no la captura',
      'Desconfía de la prisa: los estafadores presionan',
    ],
  ),
  _Paso(
    Icons.link_off,
    'Evita links y códigos QR',
    'Los estafadores envían links falsos de cobro que imitan a Pavito. Cuando vendes, tu dinero aparece dentro de la app: nadie necesita que abras un link para cobrar.',
    ejemplo:
        '🔔 ¡Tu artículo fue vendido! Cobra aquí: https://pavlto-cobro.info/8832114',
    consejos: [
      'Pavito solo vive en pavito.app',
      'No toques links ni escanees QR que te manda un comprador',
    ],
  ),
  _Paso(
    Icons.lock_outline,
    'No des datos personales',
    'Cuidado con quien te pide tu cédula, tu correo, tu teléfono, tus claves o el código que te llega para entrar. Con esos datos pueden quedarse con tu cuenta.',
    ejemplo:
        'Para confirmar la venta pásame tu cédula y el código que te llegó al correo.',
    consejos: [
      'Pavito nunca te pide tu clave ni códigos de verificación',
      'No compartas datos bancarios en el chat',
    ],
  ),
  _Paso(
    Icons.flag_outlined,
    '¿Algo te parece raro? Denúncialo',
    'Si ves un mensaje, un anuncio o a alguien sospechoso, avísanos para que lo revisemos.',
    consejos: [
      '1. Abre el anuncio o el perfil de la persona',
      '2. Toca «Denunciar»',
      '3. Elige el motivo, por ejemplo «Parece una estafa»',
    ],
  ),
];

class SeguridadPage extends StatefulWidget {
  const SeguridadPage({super.key});

  @override
  State<SeguridadPage> createState() => _SeguridadPageState();
}

class _SeguridadPageState extends State<SeguridadPage> {
  final _ctl = PageController();
  int _i = 0;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _siguiente() {
    if (_i >= _pasos.length - 1) {
      Navigator.of(context).maybePop();
      return;
    }
    _ctl.nextPage(
        duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ultimo = _i == _pasos.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seguridad'),
        actions: [
          if (!ultimo)
            TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Omitir')),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: PageView.builder(
            controller: _ctl,
            itemCount: _pasos.length,
            onPageChanged: (v) => setState(() => _i = v),
            itemBuilder: (_, k) => _Lamina(paso: _pasos[k]),
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var k = 0; k < _pasos.length; k++)
            Container(
              width: k == _i ? 10 : 7,
              height: k == _i ? 10 : 7,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: k == _i ? cs.primary : cs.onSurface.withOpacity(0.18),
              ),
            ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _siguiente,
              child: Text(_i == 0
                  ? 'Aprende a cuidarte'
                  : ultimo
                      ? 'Entendido'
                      : 'Siguiente'),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Lamina extends StatelessWidget {
  const _Lamina({required this.paso});
  final _Paso paso;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final soft = cs.surfaceContainerHighest;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      children: [
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(paso.icono, size: 46, color: cs.primary),
          ),
        ),
        const SizedBox(height: 22),
        Text(paso.titulo,
            textAlign: TextAlign.center,
            style: display(24, color: cs.onSurface)),
        const SizedBox(height: 12),
        Text(paso.texto,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 15.5, height: 1.4, color: cs.onSurface.withOpacity(0.7))),
        if (paso.ejemplo != null) ...[
          const SizedBox(height: 20),
          Text('Ejemplo de mensaje de estafa',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: cs.onSurface)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: soft, borderRadius: BorderRadius.circular(14)),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.primary.withOpacity(0.35))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.warning_amber_rounded, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(paso.ejemplo!,
                        style: TextStyle(
                            fontSize: 14.5,
                            height: 1.4,
                            color: cs.onSurface))),
              ]),
            ),
          ),
        ],
        if (paso.consejos != null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: soft, borderRadius: BorderRadius.circular(14)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final c in paso.consejos!)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 19, color: cs.primary),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(c,
                                    style: TextStyle(
                                        fontSize: 14.5,
                                        height: 1.35,
                                        color: cs.onSurface))),
                          ]),
                    ),
                ]),
          ),
        ],
      ],
    );
  }
}
