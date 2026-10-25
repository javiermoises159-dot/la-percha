import 'package:flutter/material.dart';

import 'app_state.dart';
import 'auth_sheet.dart';
import 'logo.dart';
import 'theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const LogoMark(size: 56),
                    const SizedBox(width: 12),
                    Text('La Percha', style: display(28, color: ink)),
                  ]),
                  const SizedBox(height: 28),
                  Text('Dale otra vida a tu ropa',
                      style: display(40, color: ink, height: 1.02)),
                  const SizedBox(height: 12),
                  Text('Compra y vende ropa usada en toda Venezuela.',
                      style: TextStyle(fontSize: 18, color: context.muted)),
                  const SizedBox(height: 24),
                  const _Perk('Pagas protegido',
                      'Tu dinero espera hasta que recibes la prenda.'),
                  const _Perk('Vendes sin comisión',
                      'Cobras el precio completo de cada prenda.'),
                  const _Perk('Envíos a todo el país',
                      'MRW, Zoom, Tealca o entrega en persona.'),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => showAuthSheet(context, state),
                    child: const Text('Crear cuenta'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => showAuthSheet(context, state, login: true),
                    child: const Text('Ya tengo cuenta'),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: state.continueAsGuest,
                      child: const Text('Explorar sin cuenta'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk(this.title, this.text);
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: context.leafSoft, shape: BoxShape.circle),
            child: Icon(Icons.check, size: 15, color: context.leaf),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(text, style: TextStyle(color: context.muted, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
