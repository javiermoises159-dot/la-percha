import 'package:flutter/material.dart';

import 'app_state.dart';
import 'auth_sheet.dart';
import 'explore_page.dart';
import 'extras.dart';
import 'features.dart';
import 'listing.dart';
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

  @override
  void initState() {
    super.initState();
    ListingsStore.prefScore = prefsStore.score;
    prefsStore.load().then((_) => listingsStore.resort());
  }

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
      (Icons.home_outlined, Icons.home_rounded, 'Inicio'),
      (Icons.search_rounded, Icons.search_rounded, 'Buscar'),
      (Icons.add_rounded, Icons.add_rounded, 'Vender'),
      (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Buzón'),
      (Icons.person_outline_rounded, Icons.person_rounded, 'Yo'),
    ];
    // Vender: botón rojo (o tinta cuando estás en Vender).
    Widget sellIcon(bool on) => Container(
          width: 40,
          height: 30,
          decoration: BoxDecoration(
              color: on ? context.ink : Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.add_rounded,
              color: on ? Theme.of(context).colorScheme.surface : Colors.white),
        );
    final city = prefsStore.prefs.city ?? widget.state.account?.city;
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
        title: const Wordmark(size: 25),
        actions: [
          if (city != null && !wide)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ActionChip(
                avatar: Icon(Icons.place_outlined, size: 16, color: ink),
                label: Text(city),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(
                        builder: (_) => const PrefsPage()))
                    .then((_) => setState(() {})),
              ),
            ),
          if (widget.state.account != null) const AvisosButton(),
          const SizedBox(width: 6),
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
                  for (final (icon, sel, label) in items)
                    NavigationRailDestination(
                        icon: label == 'Vender' ? sellIcon(false) : Icon(icon),
                        selectedIcon:
                            label == 'Vender' ? sellIcon(true) : Icon(sel),
                        label: Text(label)),
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
          : DecoratedBox(
              decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: context.line))),
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _select,
                destinations: [
                  for (final (icon, sel, label) in items)
                    NavigationDestination(
                        icon: label == 'Vender' ? sellIcon(false) : Icon(icon),
                        selectedIcon:
                            label == 'Vender' ? sellIcon(true) : Icon(sel),
                        label: label),
                ],
              ),
            ),
    );
  }
}
