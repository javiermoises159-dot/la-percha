import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// Consentimiento de cookies / almacenamiento en el dispositivo.
/// null = aún no eligió · 'todas' · 'necesarias'
class Cookies {
  static const _k = 'pv_cookies_v1';
  static final eleccion = ValueNotifier<String?>('cargando');

  static Future<void> cargar() async {
    try {
      final p = await SharedPreferences.getInstance();
      eleccion.value = p.getString(_k);
    } catch (_) {
      eleccion.value = null;
    }
  }

  static bool get estadisticas => eleccion.value == 'todas';

  static Future<void> elegir(String v) async {
    eleccion.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_k, v);
      if (v != 'todas') await p.remove('pv_dispositivo');
    } catch (_) {}
  }
}

const cookiesTabla = <(String, String, String, String)>[
  ('Sesión de Pavito', 'Necesaria', 'Mantener tu sesión iniciada de forma segura', 'Hasta que cierres sesión'),
  ('Tu elección de cookies', 'Necesaria', 'Recordar lo que elegiste en este aviso', 'Hasta que la cambies'),
  ('Código de invitación', 'Necesaria', 'Si llegaste con el link de un amigo, darle su premio al registrarte', 'Hasta que te registres'),
  ('Aviso "Instalar Pavito"', 'Necesaria', 'No mostrarte el aviso de instalar la app más de una vez por semana', '7 días'),
  ('Verificación anti-bots (Cloudflare Turnstile)', 'Necesaria', 'Comprobar que eres una persona al entrar o registrarte', 'La gestiona Cloudflare durante la verificación'),
  ('Inicio de sesión con Google', 'Necesaria (si lo usas)', 'Entrar con tu cuenta de Google; las cookies son de Google', 'Según Google'),
  ('Identificador anónimo del dispositivo', 'Estadística (opcional)', 'Contar las visitas a cada anuncio para que el vendedor vea cuántas tuvo, sin tu nombre', 'Hasta que borres los datos del navegador o lo rechaces'),
];

/// Página "Cookies" con la tabla y los botones para cambiar la elección.
class CookiesPage extends StatelessWidget {
  const CookiesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(title: const Text('Cookies')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text(
            'Pavito guarda algunos datos pequeños en tu dispositivo (cookies y almacenamiento local) para que la app funcione. '
            'No usamos cookies de publicidad ni de redes sociales, y no compartimos estos datos con anunciantes.',
            style: TextStyle(fontSize: 16, height: 1.5)),
        const SizedBox(height: 18),
        for (final (nombre, tipo, para, dura) in cookiesTabla)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(nombre, style: TextStyle(fontWeight: FontWeight.w800, color: ink))),
                  Text(tipo,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: tipo.startsWith('Necesaria') ? const Color(0xFF1F7A4D) : const Color(0xFF1F5FBF))),
                ]),
                const SizedBox(height: 4),
                Text(para, style: const TextStyle(height: 1.35)),
                const SizedBox(height: 2),
                Text('Duración: $dura', style: TextStyle(color: context.muted, fontSize: 13)),
              ]),
            ),
          ),
        const SizedBox(height: 10),
        const Text(
            'Las necesarias no se pueden desactivar porque sin ellas no podrías entrar ni usar la app. '
            'La estadística es opcional: si la rechazas, las visitas se cuentan solo durante esa visita y no se guarda nada.',
            style: TextStyle(height: 1.45)),
        const SizedBox(height: 18),
        ValueListenableBuilder<String?>(
          valueListenable: Cookies.eleccion,
          builder: (context, v, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                v == 'todas'
                    ? 'Tu elección actual: aceptaste todas.'
                    : v == 'necesarias'
                        ? 'Tu elección actual: solo las necesarias.'
                        : 'Aún no has elegido.',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            FilledButton(
                onPressed: v == 'todas' ? null : () => Cookies.elegir('todas'), child: const Text('Aceptar todas')),
            const SizedBox(height: 8),
            OutlinedButton(
                onPressed: v == 'necesarias' ? null : () => Cookies.elegir('necesarias'),
                child: const Text('Solo las necesarias')),
          ]),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}

/// Aviso abajo de la pantalla la primera vez. No bloquea la app.
class AvisoCookies extends StatelessWidget {
  const AvisoCookies({super.key, required this.child, required this.navigatorKey});
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      child,
      ValueListenableBuilder<String?>(
        valueListenable: Cookies.eleccion,
        builder: (context, v, _) {
          if (v != null) return const SizedBox.shrink();
          final ink = Theme.of(context).colorScheme.onSurface;
          return Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Material(
                    elevation: 8,
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('🍪 Cookies', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: ink)),
                        const SizedBox(height: 6),
                        Text(
                            'Usamos las necesarias para que puedas entrar y usar Pavito. Con tu permiso, también un identificador anónimo para contar visitas a los anuncios. Nada de publicidad.',
                            style: TextStyle(height: 1.4, color: ink)),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                              style: TextButton.styleFrom(padding: EdgeInsets.zero),
                              onPressed: () => navigatorKey.currentState
                                  ?.push(MaterialPageRoute<void>(builder: (_) => const CookiesPage())),
                              child: const Text('Ver detalles')),
                        ),
                        Row(children: [
                          Expanded(
                              child: OutlinedButton(
                                  onPressed: () => Cookies.elegir('necesarias'), child: const Text('Solo necesarias'))),
                          const SizedBox(width: 10),
                          Expanded(
                              child: FilledButton(
                                  onPressed: () => Cookies.elegir('todas'), child: const Text('Aceptar todas'))),
                        ]),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ]);
  }
}
