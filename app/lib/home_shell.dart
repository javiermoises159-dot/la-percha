import 'package:flutter/material.dart';

import 'app_state.dart';
import 'auth_sheet.dart';
import 'logo.dart';
import 'theme.dart';

/// Navegación principal. Las pantallas se irán llenando por etapas.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state});
  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _select(int i) {
    if (i == 2 && widget.state.account == null) {
      showAuthSheet(context, widget.state,
          message: 'Crea tu cuenta para vender tus prendas.');
      return;
    }
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const LogoMark(size: 30),
          const SizedBox(width: 8),
          Text('La Percha', style: display(22, color: ink)),
        ]),
      ),
      body: IndexedStack(
        index: _index,
        children: [
          const _Soon(Icons.grid_view_rounded, 'Explorar',
              'Aquí aparecerán los anuncios con fotos, búsqueda y filtros. Llega en la etapa 3.'),
          const _Soon(Icons.favorite_border, 'Favoritos',
              'Las prendas que guardes estarán aquí. Llega en la etapa 3.'),
          const _Soon(Icons.add_circle_outline, 'Vender',
              'Publicar una prenda con fotos y precio. Llega en la etapa 3.'),
          const _Soon(Icons.chat_bubble_outline, 'Mensajes',
              'Chat con vendedores y compradores, y ofertas. Llega en la etapa 3.'),
          ProfilePage(state: widget.state),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.grid_view_rounded), label: 'Explorar'),
          NavigationDestination(
              icon: Icon(Icons.favorite_border), label: 'Favoritos'),
          NavigationDestination(
              icon: Icon(Icons.add_circle_outline), label: 'Vender'),
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline), label: 'Mensajes'),
          NavigationDestination(
              icon: Icon(Icons.person_outline), label: 'Perfil'),
        ],
      ),
    );
  }
}

class _Soon extends StatelessWidget {
  const _Soon(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: context.muted),
            const SizedBox(height: 12),
            Text(title,
                style: display(22, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 6),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.muted)),
          ],
        ),
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final a = state.account;
        final ink = Theme.of(context).colorScheme.onSurface;
        if (a == null) {
          return ListView(padding: const EdgeInsets.all(20), children: [
            Text('Crea tu cuenta', style: display(24, color: ink)),
            const SizedBox(height: 6),
            Text('La necesitas para vender, comprar y escribir a otros usuarios.',
                style: TextStyle(color: context.muted)),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: () => showAuthSheet(context, state),
                child: const Text('Crear cuenta')),
            const SizedBox(height: 10),
            OutlinedButton(
                onPressed: () => showAuthSheet(context, state, login: true),
                child: const Text('Ya tengo cuenta')),
          ]);
        }
        final digits = digitsOf(a.phone);
        final tail = digits.length >= 3 ? digits.substring(digits.length - 3) : '';
        return ListView(padding: const EdgeInsets.all(20), children: [
          Row(children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: context.chip,
              child: Text(a.username.substring(0, 1).toUpperCase(),
                  style: display(28, color: ink)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.username, style: display(24, color: ink)),
                  Text('${a.city} · Tel. ••••$tail',
                      style: TextStyle(color: context.muted)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 24),
          OutlinedButton(
              onPressed: state.signOut, child: const Text('Cerrar sesión')),
        ]);
      },
    );
  }
}
