import 'package:flutter/material.dart';

import 'app_state.dart';
import 'auth_sheet.dart';
import 'explore_page.dart';
import 'features.dart';
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
    final wide = MediaQuery.sizeOf(context).width >= 900;
    const items = [
      (Icons.home_outlined, 'Inicio'),
      (Icons.grid_view_rounded, 'Explorar'),
      (Icons.add_circle_outline, 'Vender'),
      (Icons.mail_outline, 'Mensajes'),
      (Icons.person_outline, 'Perfil'),
    ];
    final pages = IndexedStack(
      index: _index,
      children: [
        const ExplorePage(),
        const CategoriesPage(),
        SellPage(
            state: widget.state, onPublished: () => setState(() => _index = 0)),
        const MessagesPage(),
        const ProfilePage(),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const LogoMark(size: 30),
          const SizedBox(width: 8),
          Text('La Percha', style: display(22, color: ink)),
        ]),
        actions: [
          if (widget.state.account != null) const AvisosButton(),
          const SizedBox(width: 4),
        ],
      ),
      // En ordenador: menú lateral y contenido centrado. En móvil: barra inferior.
      body: wide
          ? Row(children: [
              NavigationRail(
                extended: MediaQuery.sizeOf(context).width >= 1200,
                selectedIndex: _index,
                onDestinationSelected: _select,
                labelType: MediaQuery.sizeOf(context).width >= 1200
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                destinations: [
                  for (final (icon, label) in items)
                    NavigationRailDestination(
                        icon: Icon(icon), label: Text(label)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: pages),
                ),
              ),
            ])
          : pages,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _select,
              destinations: [
                for (final (icon, label) in items)
                  NavigationDestination(icon: Icon(icon), label: label),
              ],
            ),
    );
  }
}
