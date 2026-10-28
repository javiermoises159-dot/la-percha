import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'extras.dart';
import 'features.dart';
import 'fundador.dart';
import 'mas.dart';
import 'explore_page.dart';
import 'listing.dart';
import 'listing_detail.dart';
import 'theme.dart';

/// Perfil público de una persona: sus datos, valoración y prendas a la venta.
class SellerProfilePage extends StatefulWidget {
  const SellerProfilePage(
      {super.key, required this.sellerId, required this.username});
  final String sellerId;
  final String username;

  @override
  State<SellerProfilePage> createState() => _SellerProfilePageState();
}

class _SellerProfilePageState extends State<SellerProfilePage> {
  Map<String, dynamic>? _p;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Supabase.instance.client
          .from('profiles')
          .select('username, city, rating_avg, rating_count, created_at')
          .eq('id', widget.sellerId)
          .maybeSingle();
      if (mounted) setState(() => _p = r);
    } catch (_) {}
  }

  static const _meses = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre'
  ];

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final p = _p;
    final count = (p?['rating_count'] as num?)?.toInt() ?? 0;
    final avg = (p?['rating_avg'] as num?)?.toDouble() ?? 0;
    final since = DateTime.tryParse('${p?['created_at'] ?? ''}')?.toLocal();
    final isMe = appState.account?.id == widget.sellerId;
    return Scaffold(
      appBar: AppBar(title: Text('@${widget.username}'), actions: [
        IconButton(
            tooltip: isMe ? 'Compartir mi tienda' : 'Compartir tienda',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => compartirTienda(context, widget.username, mia: isMe)),
        if (!isMe)
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (_) =>
                showReportSheet(context, userId: widget.sellerId),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'denunciar', child: Text('Denunciar usuario')),
            ],
          ),
      ]),
      body: ListenableBuilder(
        listenable: listingsStore,
        builder: (context, _) {
          final items = [
            for (final l in listingsStore.all)
              if (l.sellerId == widget.sellerId) l
          ];
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: context.chip,
                  child: Text(widget.username.substring(0, 1).toUpperCase(),
                      style: display(30, color: ink)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.username, style: display(22, color: ink)),
                      Wrap(children: [
                        FundadorChip(sellerId: widget.sellerId, grande: true),
                        VerificadoChip(userId: widget.sellerId, grande: true),
                      ]),
                      if (p != null)
                        Text('${p['city']}',
                            style: TextStyle(color: context.muted)),
                      const SizedBox(height: 4),
                      InkWell(
                          onTap: count == 0
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                      builder: (_) => ReviewsPage(
                                          userId: widget.sellerId,
                                          username: widget.username))),
                          child: Row(children: [
                            const Icon(Icons.star_rounded,
                                size: 18, color: Color(0xFFE8A317)),
                            const SizedBox(width: 4),
                            Text(count == 0
                                ? 'Aún sin valoraciones'
                                : '${avg.toStringAsFixed(1)} · $count valoraciones ›'),
                          ])),
                      if (isMe) ...[
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () => compartirTienda(context, widget.username, mia: true),
                          icon: const Icon(Icons.storefront_rounded, size: 18),
                          label: const Text('Compartir mi tienda'),
                        ),
                      ],
                      if (!isMe) ...[
                        const SizedBox(height: 8),
                        FollowButton(sellerId: widget.sellerId),
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          onPressed: () => openBundle(
                              context, widget.sellerId, widget.username),
                          icon:
                              const Icon(Icons.shopping_bag_outlined, size: 18),
                          label: const Text('Comprar varios (lote)'),
                        ),
                      ],
                      if (since != null)
                        Text(
                            'En Pavito desde ${_meses[since.month - 1]} de ${since.year}',
                            style:
                                TextStyle(color: context.muted, fontSize: 13)),
                    ],
                  ),
                ),
              ]),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    isMe ? 'Mis prendas' : 'Prendas de @${widget.username}',
                    style: display(18, color: ink)),
              ),
            ),
            Expanded(
              child: ListingGrid(
                  items: items,
                  emptyText: 'Todavía no tiene prendas a la venta.'),
            ),
          ]);
        },
      ),
    );
  }
}
