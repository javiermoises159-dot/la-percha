import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'config.dart';
import 'nav.dart';

/// Android: la comprobación anti-bots corre en una página de Pavito dentro de una
/// ventanita (Cloudflare Turnstile no funciona fuera de un navegador). La página
/// devuelve el token por un canal y la ventana se cierra sola.
Future<String?> obtenerCaptcha(String siteKey) async {
  final ctx = navKey.currentContext;
  if (ctx == null) return null;
  final listo = Completer<String?>();
  void fin(String? t) {
    if (!listo.isCompleted) listo.complete(t == null || t.isEmpty ? null : t);
  }

  final web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.white)
    ..addJavaScriptChannel('PavitoApp', onMessageReceived: (m) => fin(m.message))
    ..loadRequest(Uri.parse('$webBase/captcha-app.html?k=${Uri.encodeComponent(siteKey)}'));
  var abierto = true;
  showDialog<void>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: const Text('Comprobando que no eres un robot'),
      content: SizedBox(width: 320, height: 90, child: WebViewWidget(controller: web)),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar'))],
    ),
  ).then((_) {
    abierto = false;
    fin(null);
  });
  final t = await listo.future.timeout(const Duration(seconds: 45), onTimeout: () => null);
  if (abierto) navKey.currentState?.pop();
  return t;
}
