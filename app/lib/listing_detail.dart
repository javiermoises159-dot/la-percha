import 'package:flutter/material.dart';

import 'app_state.dart';
import 'features.dart';
import 'chat_page.dart';
import 'explore_page.dart';
import 'extras.dart';
import 'listing.dart';
import 'orders_page.dart';
import 'seller_profile.dart';
import 'theme.dart';

/// Comisión de protección al comprador (la paga quien compra).
double buyerFee(double price) => 0.25 + price * 0.05;

class ListingDetail extends StatelessWidget {
  const ListingDetail({super.key, required this.item});
  final Listing item;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final fee = buyerFee(item.price);
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final fav = appState.favs.contains(item.id);
        final mine = appState.account?.id == item.sellerId;
        return Scaffold(
          appBar: AppBar(actions: [
            IconButton(
              icon: Icon(fav ? Icons.favorite : Icons.favorite_border),
              color: fav ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => toggleFavorite(context, item.id),
            ),
            if (!mine)
              PopupMenuButton<String>(
                tooltip: 'Más opciones',
                onSelected: (v) {
                  if (v == 'denunciar')
                    showReportSheet(context, listingId: item.id);
                  if (v == 'lote')
                    openBundle(context, item.sellerId, item.seller);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'lote',
                      child: Text('Comprar varios de este vendedor')),
                  PopupMenuItem(
                      value: 'denunciar', child: Text('Denunciar anuncio')),
                ],
              ),
          ]),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(children: [
                PhotoCarousel(item: item),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('\$${item.price.toStringAsFixed(0)}',
                          style: display(32, color: ink)),
                      if (bsText(item.price).isNotEmpty)
                        Text(bsText(item.price),
                            style: TextStyle(color: context.muted)),
                      const SizedBox(height: 4),
                      Text(item.title,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        _Tag('Talla ${item.size}'),
                        _Tag(item.condition),
                        _Tag(item.city),
                      ]),
                      const SizedBox(height: 16),
                      Text(item.description.isEmpty
                          ? 'Sin descripción.'
                          : item.description),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => SellerProfilePage(
                                    sellerId: item.sellerId,
                                    username: item.seller))),
                        child: Row(children: [
                          CircleAvatar(
                              backgroundColor: context.chip,
                              child: Text(item.seller.isEmpty
                                  ? '?'
                                  : item.seller[0].toUpperCase())),
                          const SizedBox(width: 10),
                          Text('@${item.seller}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          const Icon(Icons.chevron_right),
                        ]),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: context.leafSoft,
                            borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Compra protegida',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: context.leaf)),
                            const SizedBox(height: 6),
                            _Row(
                                'Prenda', '\$${item.price.toStringAsFixed(2)}'),
                            _Row('Protección al comprador',
                                '\$${fee.toStringAsFixed(2)}'),
                            _Row('Total (sin envío)',
                                '\$${(item.price + fee).toStringAsFixed(2)}',
                                bold: true),
                            const SizedBox(height: 6),
                            Text(
                                'Tu dinero queda retenido hasta que confirmes que recibiste la prenda. El vendedor no paga comisión.',
                                style: TextStyle(
                                    color: context.muted, fontSize: 13)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (mine)
                        Text('Este es tu anuncio.',
                            style: TextStyle(color: context.muted))
                      else ...[
                        FilledButton(
                          onPressed: () => startCheckout(context, item),
                          child: const Text('Comprar'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => makeOfferFor(context, item),
                          icon: const Icon(Icons.local_offer_outlined),
                          label: const Text('Hacer una oferta'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: () => openChatFor(context, item),
                          child: const Text('Escribir al vendedor'),
                        ),
                      ],
                    ],
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: context.chip, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: const TextStyle(fontSize: 13)),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.a, this.b, {this.bold = false});
  final String a;
  final String b;
  final bool bold;
  @override
  Widget build(BuildContext context) {
    final s = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(a, style: s), Text(b, style: s)]),
    );
  }
}
