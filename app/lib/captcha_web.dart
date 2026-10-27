import 'dart:js_interop';

@JS('pavitoCaptcha')
external JSPromise<JSString?> _pavitoCaptcha(JSString siteKey);

/// Pide a Turnstile un token (invisible para la persona). null si no se pudo.
Future<String?> obtenerCaptcha(String siteKey) async {
  try {
    final t = await _pavitoCaptcha(siteKey.toJS).toDart;
    return t?.toDart;
  } catch (_) {
    return null;
  }
}
