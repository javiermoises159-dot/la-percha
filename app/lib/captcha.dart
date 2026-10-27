/// Comprobación anti-bots (Cloudflare Turnstile) antes de entrar o registrarse.
/// En la web pide un token invisible; en Android devuelve null por ahora.
export 'captcha_stub.dart' if (dart.library.js_interop) 'captcha_web.dart';
