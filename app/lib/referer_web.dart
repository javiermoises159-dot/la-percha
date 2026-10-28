import 'dart:js_interop';

@JS('document.referrer')
external JSString get _referer;

String refererDelNavegador() {
  try {
    return _referer.toDart;
  } catch (_) {
    return '';
  }
}
