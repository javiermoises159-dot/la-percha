import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'auth_sheet.dart';
import 'chat_page.dart';
import 'listing.dart';
import 'orders_page.dart';
import 'theme.dart';

SupabaseClient get _db => Supabase.instance.client;

String _usd(num v) => '\$${v.toStringAsFixed(2)}';

String _errorText(Object e, String fallback) =>
    e is PostgrestException ? e.message : fallback;

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

// ===================== Ofertas =====================

/// Pide un monto entre el 50 % y el precio. Devuelve null si se cancela.
Future<double?> askOfferAmount(BuildContext context,
    {required double price, required String title}) {
  final ctrl = TextEditingController();
  final min = (price * 0.5 * 100).ceil() / 100;
  String? error;
  return showDialog<double>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Precio: ${_usd(price)}. Puedes ofrecer desde ${_usd(min)}.'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'Tu oferta en dólares', prefixText: '\$ ', errorText: error),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
              if (v == null || v < min || v >= price) {
                setState(() => error = 'Entre ${_usd(min)} y menos de ${_usd(price)}');
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('Enviar oferta'),
          ),
        ],
      ),
    ),
  );
}

/// Botón "Hacer una oferta" desde el anuncio: envía la oferta y abre el chat.
Future<void> makeOfferFor(BuildContext context, Listing item) async {
  if (appState.account == null) {
    showAuthSheet(context, appState, message: 'Crea tu cuenta para hacer ofertas.');
    return;
  }
  final amount = await askOfferAmount(context, price: item.price, title: 'Hacer una oferta');
  if (amount == null || !context.mounted) return;
  try {
    await _db.rpc('make_offer', params: {'p_listing': item.id, 'p_amount': amount});
    if (!context.mounted) return;
    _snack(context, 'Oferta enviada. Te avisamos en el chat.');
    await openChatFor(context, item);
  } catch (e) {
    if (context.mounted) _snack(context, _errorText(e, 'No se pudo enviar la oferta.'));
  }
}

/// Barra de ofertas dentro de un chat: responder, contraofertar o comprar al precio acordado.
class OfferBar extends StatefulWidget {
  const OfferBar({super.key, required this.threadId, this.onChanged});
  final String threadId;
  final VoidCallback? onChanged;

  @override
  State<OfferBar> createState() => _OfferBarState();
}

class _OfferBarState extends State<OfferBar> {
  Map<String, dynamic>? _thread;
  Listing? _listing;
  Map<String, dynamic>? _offer;
  bool _busy = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = _thread ??= await _db
          .from('threads')
          .select('listing_id, buyer_id, seller_id')
          .eq('id', widget.threadId)
          .single();
      final l = await _db
          .from('listings')
          .select('*, profiles(username)')
          .eq('id', t['listing_id'] as String)
          .maybeSingle();
      final offers = await _db
          .from('offers')
          .select()
          .eq('listing_id', t['listing_id'] as String)
          .eq('buyer_id', t['buyer_id'] as String)
          .inFilter('status', ['pendiente', 'aceptada'])
          .order('created_at', ascending: false)
          .limit(1);
      if (!mounted) return;
      setState(() {
        _listing = l == null ? null : Listing.fromMap(l);
        _offer = offers.isEmpty ? null : offers.first;
      });
    } catch (_) {}
  }

  Future<void> _run(Future<void> Function() action, String fail) async {
    setState(() => _busy = true);
    try {
      await action();
      widget.onChanged?.call();
      await _load();
    } catch (e) {
      if (mounted) _snack(context, _errorText(e, fail));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _propose() async {
    final l = _listing;
    final t = _thread;
    if (l == null || t == null) return;
    final iAmSeller = appState.account?.id == t['seller_id'];
    final amount = await askOfferAmount(context,
        price: l.price, title: iAmSeller ? 'Hacer una contraoferta' : 'Hacer una oferta');
    if (amount == null) return;
    await _run(
        () => _db.rpc('make_offer', params: {
              'p_listing': l.id,
              'p_amount': amount,
              if (iAmSeller) 'p_buyer': t['buyer_id'],
            }),
        'No se pudo enviar la oferta.');
  }

  @override
  Widget build(BuildContext context) {
    final me = appState.account?.id;
    final t = _thread;
    final l = _listing;
    if (t == null || l == null || me == null) return const SizedBox.shrink();
    final o = _offer;
    final iAmBuyer = me == t['buyer_id'];
    final scheme = Theme.of(context).colorScheme;

    Widget? content;
    if (o != null && o['status'] == 'pendiente') {
      final amount = (o['amount'] as num).toDouble();
      if (o['proposer_id'] == me) {
        content = Text('Esperando respuesta a tu oferta de ${_usd(amount)}.');
      } else {
        content = Row(children: [
          Expanded(
              child: Text('${iAmBuyer ? 'Contraoferta' : 'Oferta'}: ${_usd(amount)}',
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => _db.rpc('respond_offer',
                          params: {'p_offer': o['id'], 'p_accept': false}),
                      'No se pudo responder.'),
              child: const Text('Rechazar')),
          FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => _db.rpc('respond_offer',
                          params: {'p_offer': o['id'], 'p_accept': true}),
                      'No se pudo responder.'),
              child: const Text('Aceptar')),
        ]);
      }
    } else if (o != null && o['status'] == 'aceptada' && l.price > 0) {
      final amount = (o['amount'] as num).toDouble();
      content = iAmBuyer
          ? Row(children: [
              Expanded(child: Text('Oferta aceptada: ${_usd(amount)} (48 h).')),
              FilledButton(
                  onPressed: () => startCheckout(context, l),
                  child: Text('Comprar a ${_usd(amount)}')),
            ])
          : Text('Aceptaste ${_usd(amount)}. Esperando que el comprador pague.');
    }

    final canPropose = (o == null || o['status'] != 'aceptada');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${l.title} · ${_usd(l.price)}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.muted)),
          ),
          if (canPropose)
            TextButton.icon(
              onPressed: _busy ? null : _propose,
              icon: const Icon(Icons.local_offer_outlined, size: 18),
              label: Text(iAmBuyer ? 'Ofertar' : 'Contraoferta'),
            ),
        ]),
        if (content != null) content,
      ]),
    );
  }
}

/// Precio que paga el usuario (oferta aceptada o el del anuncio).
Future<double> myPriceFor(Listing item) async {
  try {
    final v = await _db.rpc('my_price', params: {'p_listing': item.id});
    if (v is num) return v.toDouble();
  } catch (_) {}
  return item.price;
}

// ===================== Reseñas =====================

/// Botón para dejar reseña cuando el pedido está completado.
class ReviewButton extends StatefulWidget {
  const ReviewButton({super.key, required this.orderId, required this.otherName});
  final String orderId;
  final String otherName;

  @override
  State<ReviewButton> createState() => _ReviewButtonState();
}

class _ReviewButtonState extends State<ReviewButton> {
  bool? _done;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final r = await _db
          .from('reviews')
          .select('order_id')
          .eq('order_id', widget.orderId)
          .eq('author_id', appState.account?.id ?? '')
          .maybeSingle();
      if (mounted) setState(() => _done = r != null);
    } catch (_) {}
  }

  Future<void> _open() async {
    var stars = 5;
    final text = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('¿Cómo fue con @${widget.otherName}?',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  iconSize: 36,
                  onPressed: () => setState(() => stars = i),
                  icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: const Color(0xFFE8A317)),
                ),
            ]),
            TextField(
              controller: text,
              maxLength: 300,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Comentario (opcional)',
                  hintText: 'Envío rápido, tal como en las fotos…'),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Publicar reseña')),
            ),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _db.rpc('leave_review', params: {
        'p_order': widget.orderId,
        'p_stars': stars,
        'p_text': text.text.trim(),
      });
      if (!mounted) return;
      setState(() => _done = true);
      _snack(context, '¡Gracias! Tu reseña ayuda a toda la comunidad.');
    } catch (e) {
      if (mounted) _snack(context, _errorText(e, 'No se pudo guardar la reseña.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done == null) return const SizedBox.shrink();
    if (_done!) {
      return Text('Ya dejaste tu reseña. ¡Gracias!', style: TextStyle(color: context.muted));
    }
    return FilledButton.icon(
        onPressed: _open,
        icon: const Icon(Icons.star_rounded),
        label: Text('Valorar a @${widget.otherName}'));
  }
}

/// Lista de reseñas que ha recibido una persona.
class ReviewsPage extends StatefulWidget {
  const ReviewsPage({super.key, required this.userId, required this.username});
  final String userId;
  final String username;

  @override
  State<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage> {
  List<Map<String, dynamic>>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db
          .from('reviews')
          .select('stars, text, created_at, author:profiles!reviews_author_id_fkey(username)')
          .eq('target_id', widget.userId)
          .order('created_at', ascending: false)
          .limit(100);
      if (mounted) setState(() => _rows = List<Map<String, dynamic>>.from(r));
    } catch (_) {
      if (mounted) setState(() => _rows = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: Text('Valoraciones de @${widget.username}')),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
              ? Center(
                  child: Text('Aún no tiene valoraciones.',
                      style: TextStyle(color: context.muted)))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    final stars = (r['stars'] as num).toInt();
                    final text = '${r['text'] ?? ''}';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Row(children: [
                        for (var s = 1; s <= 5; s++)
                          Icon(s <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                              size: 18, color: const Color(0xFFE8A317)),
                        const SizedBox(width: 8),
                        Text('@${field(r['author'], 'username', 'usuario')}',
                            style: TextStyle(color: context.muted, fontSize: 13)),
                      ]),
                      subtitle: text.isEmpty ? null : Text(text),
                    );
                  },
                ),
    );
  }
}

// ===================== Modo vacaciones =====================

class VacationPage extends StatefulWidget {
  const VacationPage({super.key});

  @override
  State<VacationPage> createState() => _VacationPageState();
}

class _VacationPageState extends State<VacationPage> {
  bool? _on;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db
          .from('profiles')
          .select('vacation')
          .eq('id', appState.account?.id ?? '')
          .single();
      if (mounted) setState(() => _on = r['vacation'] == true);
    } catch (_) {
      if (mounted) setState(() => _on = false);
    }
  }

  Future<void> _set(bool v) async {
    setState(() => _busy = true);
    try {
      await _db.from('profiles').update({'vacation': v}).eq('id', appState.account!.id);
      setState(() => _on = v);
      listingsStore.load();
    } catch (_) {
      if (mounted) _snack(context, 'No se pudo cambiar. Revisa tu conexión.');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final on = _on;
    return Scaffold(
      appBar: AppBar(title: const Text('Modo vacaciones')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(
            'Si vas a estar fuera, activa el modo vacaciones: tus anuncios se ocultan '
            'y nadie puede comprarlos ni hacerte ofertas. Al volver, desactívalo y '
            'aparecen otra vez, tal como estaban.',
            style: TextStyle(color: context.muted)),
        const SizedBox(height: 16),
        if (on == null)
          const Center(child: CircularProgressIndicator())
        else
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Estoy de vacaciones'),
            subtitle: Text(on ? 'Tus anuncios están ocultos' : 'Tus anuncios están visibles'),
            value: on,
            onChanged: _busy ? null : _set,
          ),
      ]),
    );
  }
}
