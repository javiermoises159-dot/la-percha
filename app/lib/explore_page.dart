import 'package:flutter/material.dart';

import 'app_state.dart';
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

/// Tarjeta de una prenda.
class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.item});
  final Listing item;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ListingDetail(item: item))),
      child: Container(
        decoration: BoxDecoration(
            color: surface, borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(children: [
                Positioned.fill(child: ListingPhoto(item: item)),
                Positioned(
                  right: 6,
                  top: 6,
                  child: ListenableBuilder(
                    listenable: appState,
                    builder: (context, _) {
                      final fav = appState.favs.contains(item.id);
                      return Material(
                        color: surface,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => toggleFavorite(context, item.id),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                                fav ? Icons.favorite : Icons.favorite_border,
                                size: 18,
                                color: fav
                                    ? Theme.of(context).colorScheme.primary
                                    : context.muted),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('\$${item.price.toStringAsFixed(0)}',
                      style: display(18,
                          color: Theme.of(context).colorScheme.onSurface)),
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${item.size} · ${item.city}',
                      style: TextStyle(color: context.muted, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
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
                  'No encontramos prendas con ese filtro.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.muted)),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.72),
      itemCount: items.length,
      itemBuilder: (_, i) => ListingCard(item: items[i]),
    );
  }
}

/// Inicio: búsqueda, categorías rápidas y prendas recientes.
class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  String _q = '';
  String _cat = 'Todo';

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
    final items = listingsStore.all.where((l) {
      final okCat = _cat == 'Todo' || l.category == _cat;
      final okQ = _q.isEmpty || l.title.toLowerCase().contains(_q.toLowerCase());
      return okCat && okQ;
    }).toList();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: TextField(
          onChanged: (v) => setState(() => _q = v.trim()),
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar prendas',
              contentPadding: EdgeInsets.symmetric(vertical: 0)),
        ),
      ),
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final c in categories)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(c),
                  selected: _cat == c,
                  onSelected: (_) => setState(() => _cat = c),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: listingsStore.load,
          child: ListingGrid(
              items: items,
              emptyText: listingsStore.all.isEmpty
                  ? 'Todavía no hay prendas. ¡Sé el primero en publicar!'
                  : null),
        ),
      ),
    ]);
  }
}

const _categoryIcons = {
  'Mujer': Icons.woman,
  'Hombre': Icons.man,
  'Niños': Icons.child_care,
  'Zapatos': Icons.hiking,
  'Accesorios': Icons.watch_outlined,
};

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
                    Text(c, style: display(18,
                        color: Theme.of(context).colorScheme.onSurface)),
                    Text('$n prendas',
                        style: TextStyle(color: context.muted, fontSize: 12)),
                    const Spacer(),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Icon(_categoryIcons[c] ?? Icons.checkroom,
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
