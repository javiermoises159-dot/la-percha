import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cookies.dart';
import 'mas.dart';
import 'referer_stub.dart' if (dart.library.js_interop) 'referer_web.dart';

/// Cuenta una visita por cada vez que se abre la app (sin nombre ni IP).
/// Si la persona inicia sesión en esa visita, se asocia a su cuenta para saber de dónde vino.
final String _sesion = () {
  final r = Random.secure();
  const c = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(20, (_) => c[r.nextInt(c.length)]).join();
}();

String _origen() {
  final q = Uri.base.queryParameters;
  final utm = (q['utm_source'] ?? q['o'] ?? '').toLowerCase().trim();
  if (utm.isNotEmpty) return _limpio(utm);
  final host = (q['src'] ?? _hostDe(kIsWeb ? refererDelNavegador() : '')).toLowerCase();
  if (host.isNotEmpty && !host.contains('pavito') && !host.contains('la-percha') && !host.contains('localhost')) {
    if (host.contains('instagram')) return 'instagram';
    if (host.contains('tiktok')) return 'tiktok';
    if (host.contains('whatsapp') || host == 'wa.me') return 'whatsapp';
    if (host.contains('facebook') || host == 'fb.com' || host.startsWith('lm.') || host.startsWith('l.')) return 'facebook';
    if (host.contains('google')) return 'google';
    if (host == 't.co' || host.contains('twitter') || host.contains('x.com')) return 'x';
    if (host.contains('t.me') || host.contains('telegram')) return 'telegram';
    return _limpio(host.replaceFirst('www.', ''));
  }
  if (q.containsKey('ref')) return 'invitación';
  if (q.containsKey('a')) return 'anuncio compartido';
  if (q.containsKey('t')) return 'tienda compartida';
  return 'directo';
}

String _hostDe(String url) {
  try {
    return url.isEmpty ? '' : Uri.parse(url).host;
  } catch (_) {
    return '';
  }
}

String _limpio(String s) {
  final t = s.replaceAll(RegExp(r'[^a-z0-9._ -]'), '');
  return t.isEmpty ? 'otro' : (t.length > 40 ? t.substring(0, 40) : t);
}

String _ruta() {
  final q = Uri.base.queryParameters;
  if (q.containsKey('a')) return 'anuncio';
  if (q.containsKey('t')) return 'tienda';
  return 'app';
}

String _plataforma() => kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();

String? _origenGuardado;

Future<void> registrarVisitaApp() async {
  try {
    _origenGuardado ??= _origen();
    await Supabase.instance.client.rpc('registrar_visita', params: {
      'p_sesion': _sesion,
      'p_disp': Cookies.estadisticas ? await dispositivoId() : null,
      'p_origen': _origenGuardado,
      'p_ruta': _ruta(),
      'p_plataforma': _plataforma(),
    });
  } catch (_) {}
}

/// Llamar una vez al arrancar: cuenta la visita y la vuelve a marcar al iniciar sesión.
void vigilarVisitas() {
  registrarVisitaApp();
  Supabase.instance.client.auth.onAuthStateChange.listen((e) {
    if (e.event == AuthChangeEvent.signedIn) registrarVisitaApp();
  }, onError: (_) {});
}
