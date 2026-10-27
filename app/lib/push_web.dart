import 'dart:convert';
import 'dart:js_interop';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';

@JS('pavitoPush.estado')
external JSPromise<JSString> _estado();
@JS('pavitoPush.activar')
external JSPromise<JSString> _activar(JSString vapid);
@JS('pavitoPush.desactivar')
external JSPromise<JSString> _desactivar();

/// 'activo' | 'pregunta' | 'bloqueado' | 'instalar_ios' | 'no_soportado'
Future<String> pushEstado() async {
  try {
    return (await _estado().toDart).toDart;
  } catch (_) {
    return 'no_soportado';
  }
}

/// Pide permiso y guarda este dispositivo. Devuelve null si salió bien o el motivo.
Future<String?> activarPush() async {
  try {
    final j = jsonDecode((await _activar(vapidPublica.toJS).toDart).toDart) as Map<String, dynamic>;
    if (j['error'] != null) {
      return j['error'] == 'denied'
          ? 'Bloqueaste las notificaciones. Actívalas en los ajustes del navegador para Pavito.'
          : 'No se pudieron activar las notificaciones en este dispositivo.';
    }
    final keys = (j['keys'] as Map?) ?? const {};
    await Supabase.instance.client.rpc('guardar_push',
        params: {'p_endpoint': j['endpoint'], 'p_p256dh': keys['p256dh'], 'p_auth': keys['auth']});
    return null;
  } catch (_) {
    return 'No se pudieron activar las notificaciones. Revisa tu conexión.';
  }
}

Future<void> desactivarPush() async {
  try {
    final ep = (await _desactivar().toDart).toDart;
    if (ep.isNotEmpty) await Supabase.instance.client.rpc('quitar_push', params: {'p_endpoint': ep});
  } catch (_) {}
}
