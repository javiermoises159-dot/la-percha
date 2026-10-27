import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Versión de la app que se guarda con cada error (súbela al publicar cambios grandes).
const versionApp = '2026.10.27';

final _enviados = <String>{};

/// Guarda en el servidor un error de la app, para verlo en el panel. Nunca falla.
Future<void> reportarError(Object error, StackTrace? pila) async {
  try {
    final msg = '$error'.split('\n').first;
    if (msg.isEmpty || !_enviados.add(msg) || _enviados.length > 30) return;
    await Supabase.instance.client.rpc('reportar_error', params: {
      'p_mensaje': msg,
      'p_pila': pila?.toString().split('\n').take(12).join('\n'),
      'p_plataforma': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'p_version': versionApp,
      'p_url': kIsWeb ? Uri.base.path : null,
    });
  } catch (_) {}
}

/// Atrapa los errores de Flutter y los que se escapan, y los reporta.
void vigilarErrores() {
  final anterior = FlutterError.onError;
  FlutterError.onError = (d) {
    anterior?.call(d);
    unawaited(reportarError(d.exception, d.stack));
  };
  PlatformDispatcher.instance.onError = (e, s) {
    unawaited(reportarError(e, s));
    return true;
  };
}
