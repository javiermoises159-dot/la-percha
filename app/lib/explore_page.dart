import 'package:flutter/material.dart';

import 'app_state.dart';
import 'extras.dart';
import 'features.dart';
import 'auth_sheet.dart';
import 'listing.dart';
import 'listing_detail.dart';
import 'theme.dart';

/// Marca o desmarca favorito; si no hay sesión, pide crear cuenta.
void toggleFavorite(BuildContext context, String id) {
  if (appState.account == null) {
    showAuthSheet(context, appState,
        message: 'Crea tu cuenta para guardar favoritos.');
    return;
  }
  appState.toggleFav(id);
}

/// Tarjeta de un artículo: la foto manda; precio, título y detalles debajo.
class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.item});
  final Listing item;

  @override
  Widget build(BuildContext context) {
    final bs = bsText(item.price).replaceFirst('≈ ', '');
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ListingDetail(item: item))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(children: [
                Positioned.fill(child: ListingPhoto(item: item)),
                Positioned(
                  left: 8,
                  top: 8,
                  child: ListenableBuilder(
                    listenable: appState,
                    builder: (context, _) {
                      final before = appState.favPriceAt[item.id];
                      final drop = before != null && before > item.price;
                      final label = item.featured
                          ? 'Destacado'
                          : drop
                              ? 'Bajó de \$${before.toStringAsFixed(0)}'
                              : null;
                      if (label == null) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                            color: item.featured ? Colors.white : context.leaf,
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(label,
                            style: TextStyle(
                                color: item.featured ? LP.ink : Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      );
                    },
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: ListenableBuilder(
                    listenable: appState,
                    builder: (context, _) {
                      final fav = appState.favs.contains(item.id);
                      return Material(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => toggleFavorite(context, item.id),
                          child: Padding(
                            padding: const EdgeInsets.all(7),
                            child: Icon(
                                fav ? Icons.favorite : Icons.favorite_border,
                                size: 17,
                                color: fav
                                    ? Theme.of(context).colorScheme.primary
                                    : LP.ink),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 7),
          Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('\$${item.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2)),
                if (bs.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(bs,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.muted, fontSize: 12)),
                  ),
                ],
              ]),
          Text(item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
          Text(
              [if (item.size != 'No aplica') item.size, item.condition]
                  .join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Cuadrícula de prendas (2 columnas).
class ListingGrid extends StatelessWidget {
  const ListingGrid({super.key, required this.items, this.emptyText});
  final List<Listing> items;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    if (listingsStore.loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
              listingsStore.error ??
                  emptyText ??
                  'No encontramos nada con ese filtro.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.muted)),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      // 2 columnas en móvil; más en pantallas anchas.
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          mainAxisSpacing: 18,
          crossAxisSpacing: 10,
          childAspectRatio: 0.6),
      itemCount: items.length,
      itemBuilder: (_, i) => ListingCard(item: items[i]),
    );
  }
}

const _siguiendo = 'Siguiendo';

/// Inicio: búsqueda, categorías rápidas y prendas recientes.
class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  String _q = '';
  String _cat = 'Todo';
  Filtros _f = const Filtros();

  @override
  void initState() {
    super.initState();
    listingsStore.addListener(_refresh);
    followStore.addListener(_refresh);
  }

  @override
  void dispose() {
    listingsStore.removeListener(_refresh);
    followStore.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final items = listingsStore.all.where((l) {
      final okCat = _cat == 'Todo' ||
          (_cat == _siguiendo
              ? followStore.ids.contains(l.sellerId)
              : l.category == _cat);
      final okQ =
          _q.isEmpty || l.title.toLowerCase().contains(_q.toLowerCase());
      return okCat && okQ && _f.ok(l);
    }).toList();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar en Pavito',
                  contentPadding: EdgeInsets.symmetric(vertical: 0)),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Filtros',
            onPressed: () async {
              final f = await showFiltros(context, _f);
              if (f != null) setState(() => _f = f);
            },
            icon: Badge(
              isLabelVisible: _f.activos,
              label: Text('${_f.cuantos}'),
              child: const Icon(Icons.tune),
            ),
          ),
        ]),
      ),
      SizedBox(
        height: 92,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          children: [
            for (final c in [
              categories.first,
              if (appState.account != null) _siguiendo,
              ...categories.skip(1),
            ])
              _CatTile(
                label: c,
                icon: c == 'Todo'
                    ? Icons.grid_view_rounded
                    : c == _siguiendo
                        ? Icons.favorite_border_rounded
                        : (categoryIcons[c] ?? Icons.checkroom),
                selected: _cat == c,
                onTap: () {
                  if (c == _siguiendo) followStore.load();
                  setState(() => _cat = c);
                },
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(children: [
          Text(
              _cat == 'Todo'
                  ? (prefsStore.prefs.city != null
                      ? 'Cerca de ti'
                      : 'Recién colgado')
                  : _cat,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3)),
          const Spacer(),
          Text('${items.length} artículos',
              style: TextStyle(color: context.muted, fontSize: 13)),
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: listingsStore.load,
          child: ListingGrid(
              items: items,
              emptyText: listingsStore.all.isEmpty
                  ? 'Todavía no hay nada colgado. ¡Sé el primero en publicar!'
                  : null),
        ),
      ),
    ]);
  }
}

/// Explorar: búsqueda y categorías en cuadrícula.
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  String _q = '';

  @override
  void initState() {
    super.initState();
    listingsStore.addListener(_refresh);
  }

  @override
  void dispose() {
    listingsStore.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (_q.isNotEmpty) {
      final items = listingsStore.all
          .where((l) =>
              l.title.toLowerCase().contains(_q.toLowerCase()) ||
              l.seller.toLowerCase().contains(_q.toLowerCase()))
          .toList();
      return Column(children: [
        _search(),
        Expanded(child: ListingGrid(items: items)),
      ]);
    }
    final cats = categories.where((c) => c != 'Todo').toList();
    return Column(children: [
      _search(),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.35),
          itemCount: cats.length,
          itemBuilder: (_, i) {
            final c = cats[i];
            final n = listingsStore.all.where((l) => l.category == c).length;
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => CategoryResults(category: c))),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c,
                        style: display(18,
                            color: Theme.of(context).colorScheme.onSurface)),
                    Text('$n prendas',
                        style: TextStyle(color: context.muted, fontSize: 12)),
                    const Spacer(),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Icon(categoryIcons[c] ?? Icons.checkroom,
                          size: 44, color: context.leaf),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _search() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: TextField(
          onChanged: (v) => setState(() => _q = v.trim()),
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar prendas o usuarios',
              contentPadding: EdgeInsets.symmetric(vertical: 0)),
        ),
      );
}

class CategoryResults extends StatelessWidget {
  const CategoryResults({super.key, required this.category});
  final String category;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(category)),
      body: ListenableBuilder(
        listenable: listingsStore,
        builder: (context, _) => ListingGrid(
          items:
              listingsStore.all.where((l) => l.category == category).toList(),
          emptyText: 'Todavía no hay prendas en esta categoría.',
        ),
      ),
    );
  }
}

/// Categoría como cuadro con icono (la seleccionada va en tinta).
class _CatTile extends StatelessWidget {
  const _CatTile(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 66,
          child: Column(children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                  color: selected ? context.ink : context.soft,
                  borderRadius: BorderRadius.circular(16)),
              child: Icon(icon,
                  size: 26,
                  color: selected
                      ? Theme.of(context).colorScheme.surface
                      : context.ink),
            ),
            const SizedBox(height: 5),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}
