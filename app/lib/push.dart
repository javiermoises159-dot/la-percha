/// Notificaciones al teléfono. En la web usa Web Push; en Android (app) por ahora no.
export 'push_stub.dart' if (dart.library.js_interop) 'push_web.dart';
