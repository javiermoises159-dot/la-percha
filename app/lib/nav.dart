import 'package:flutter/material.dart';

/// Navegador principal de la app, para mostrar diálogos desde fuera de las pantallas.
final navKey = GlobalKey<NavigatorState>();

/// Para mostrar avisos (por ejemplo, un error al volver de Google) desde cualquier parte.
final mensajeroKey = GlobalKey<ScaffoldMessengerState>();

void avisoGlobal(String texto) {
  mensajeroKey.currentState?.showSnackBar(
      SnackBar(content: Text(texto), duration: const Duration(seconds: 12), showCloseIcon: true));
}

/// Pide a la barra principal que abra la pestaña "Vender" (sube el contador para avisar).
final irAVender = ValueNotifier<int>(0);
