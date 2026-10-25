import 'package:flutter/material.dart';

import 'app_state.dart';
import 'auth_sheet.dart';
import 'explore_page.dart';
import 'logo.dart';
import 'messages_page.dart';
import 'profile_page.dart';
import 'sell_page.dart';
import 'theme.dart';

/// Navegación principal: Inicio, Explorar, Vender, Mensajes y Perfil.
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
          const ExplorePage(),
          const CategoriesPage(),
          SellPage(
              state: widget.state,
              onPublished: () => setState(() => _index = 0)),
          const MessagesPage(),
          const ProfilePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Inicio'),
          NavigationDestination(
              icon: Icon(Icons.grid_view_rounded), label: 'Explorar'),
          NavigationDestination(
              icon: Icon(Icons.add_circle_outline), label: 'Vender'),
          NavigationDestination(
              icon: Icon(Icons.mail_outline), label: 'Mensajes'),
          NavigationDestination(
              icon: Icon(Icons.person_outline), label: 'Perfil'),
        ],
      ),
    );
  }
}
