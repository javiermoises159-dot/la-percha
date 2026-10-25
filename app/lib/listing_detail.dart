import 'package:flutter/material.dart';

import 'listing.dart';
import 'theme.dart';

/// Comisión de protección al comprador (la paga quien compra).
double buyerFee(double price) => 0.5 + price * 0.05;

class ListingDetail extends StatefulWidget {
  const ListingDetail(
      {super.key, required this.item, required this.fav, required this.onFav});
  final Listing item;
  final bool fav;
  final VoidCallback onFav;

  @override
  State<ListingDetail> createState() => _ListingDetailState();
}

class _ListingDetailState extends State<ListingDetail> {
  late bool _fav = widget.fav;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final ink = Theme.of(context).colorScheme.onSurface;
    final fee = buyerFee(item.price);
    return Scaffold(
      appBar: AppBar(actions: [
        IconButton(
          icon: Icon(_fav ? Icons.favorite : Icons.favorite_border),
          color: _fav ? Theme.of(context).colorScheme.primary : null,
          onPressed: () {
            widget.onFav();
            setState(() => _fav = !_fav);
          },
        ),
      ]),
      body: ListView(children: [
        AspectRatio(
          aspectRatio: 1,
          child: Container(
              color: item.color,
              child: const Icon(Icons.checkroom, size: 96, color: Colors.white70)),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('\$${item.price.toStringAsFixed(0)}',
                  style: display(32, color: ink)),
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
              Text(item.description),
              const SizedBox(height: 16),
              Row(children: [
                CircleAvatar(
                    backgroundColor: context.chip,
                    child: Text(item.seller[0].toUpperCase())),
                const SizedBox(width: 10),
                Text('@${item.seller}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
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
                            fontWeight: FontWeight.w700, color: context.leaf)),
                    const SizedBox(height: 6),
                    _Row('Prenda', '\$${item.price.toStringAsFixed(2)}'),
                    _Row('Protección al comprador', '\$${fee.toStringAsFixed(2)}'),
                    _Row('Total (sin envío)',
                        '\$${(item.price + fee).toStringAsFixed(2)}',
                        bold: true),
                    const SizedBox(height: 6),
                    Text(
                        'Tu dinero queda retenido hasta que confirmes que recibiste la prenda. El vendedor no paga comisión.',
                        style: TextStyle(color: context.muted, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('La compra protegida llega en la etapa 4.'))),
                child: const Text('Comprar'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('El chat y las ofertas llegan en la etapa 3.'))),
                child: const Text('Hacer una oferta'),
              ),
            ],
          ),
        ),
      ]),
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
