import 'package:flutter/material.dart';

import 'listing.dart';
import 'listing_detail.dart';
import 'theme.dart';

/// Tarjeta con la "foto" de la prenda. Se reemplaza por la foto real en la etapa 2.
class ListingCard extends StatelessWidget {
  const ListingCard(
      {super.key, required this.item, required this.fav, required this.onFav});
  final Listing item;
  final bool fav;
  final VoidCallback onFav;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ListingDetail(item: item, fav: fav, onFav: onFav))),
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
                  child: Material(
                    color: surface,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onFav,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(fav ? Icons.favorite : Icons.favorite_border,
                            size: 18,
                            color: fav
                                ? Theme.of(context).colorScheme.primary
                                : context.muted),
                      ),
                    ),
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

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key, required this.favs, required this.onFav});
  final Set<String> favs;
  final void Function(String id) onFav;

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
        child: items.isEmpty
            ? Center(
                child: Text('No encontramos prendas con ese filtro.',
                    style: TextStyle(color: context.muted)))
            : GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.72),
                itemCount: items.length,
                itemBuilder: (_, i) => ListingCard(
                  item: items[i],
                  fav: widget.favs.contains(items[i].id),
                  onFav: () => widget.onFav(items[i].id),
                ),
              ),
      ),
    ]);
  }
}
