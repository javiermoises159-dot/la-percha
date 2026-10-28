import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'auth_sheet.dart';
import 'chat_page.dart';
import 'config.dart';
import 'listing.dart';
import 'listing_detail.dart';
import 'mas.dart';
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
                labelText: 'Tu oferta en dólares',
                prefixText: '\$ ',
                errorText: error),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
              if (v == null || v < min || v >= price) {
                setState(() =>
                    error = 'Entre ${_usd(min)} y menos de ${_usd(price)}');
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
    showAuthSheet(context, appState,
        message: 'Crea tu cuenta para hacer ofertas.');
    return;
  }
  final amount = await askOfferAmount(context,
      price: item.price, title: 'Hacer una oferta');
  if (amount == null || !context.mounted) return;
  try {
    await _db
        .rpc('make_offer', params: {'p_listing': item.id, 'p_amount': amount});
    if (!context.mounted) return;
    _snack(context, 'Oferta enviada. Te avisamos en el chat.');
    await openChatFor(context, item);
  } catch (e) {
    if (context.mounted)
      _snack(context, _errorText(e, 'No se pudo enviar la oferta.'));
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
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
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
          .select('*, profiles!listings_seller_id_fkey(username)')
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
        price: l.price,
        title: iAmSeller ? 'Hacer una contraoferta' : 'Hacer una oferta');
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
              child: Text(
                  '${iAmBuyer ? 'Contraoferta' : 'Oferta'}: ${_usd(amount)}',
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => _db.rpc('respond_offer',
                          params: {'p_offer': o['id'], 'p_accept': false}),
                      'No se pudo responder.'),
              child: const Text('Rechazar')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), 
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
              FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), 
                  onPressed: () => startCheckout(context, l),
                  child: Text('Comprar a ${_usd(amount)}')),
            ])
          : Text(
              'Aceptaste ${_usd(amount)}. Esperando que el comprador pague.');
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
  const ReviewButton(
      {super.key, required this.orderId, required this.otherName});
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
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('¿Cómo fue con @${widget.otherName}?',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  iconSize: 36,
                  onPressed: () => setState(() => stars = i),
                  icon: Icon(
                      i <= stars
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
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
      if (mounted)
        _snack(context, _errorText(e, 'No se pudo guardar la reseña.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done == null) return const SizedBox.shrink();
    if (_done!) {
      return Text('Ya dejaste tu reseña. ¡Gracias!',
          style: TextStyle(color: context.muted));
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
          .select(
              'stars, text, created_at, author:profiles!reviews_author_id_fkey(username)')
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
                          Icon(
                              s <= stars
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 18,
                              color: const Color(0xFFE8A317)),
                        const SizedBox(width: 8),
                        Text('@${field(r['author'], 'username', 'usuario')}',
                            style:
                                TextStyle(color: context.muted, fontSize: 13)),
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
      await _db
          .from('profiles')
          .update({'vacation': v}).eq('id', appState.account!.id);
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
            subtitle: Text(on
                ? 'Tus anuncios están ocultos'
                : 'Tus anuncios están visibles'),
            value: on,
            onChanged: _busy ? null : _set,
          ),
      ]),
    );
  }
}

// ===================== Seguir vendedores =====================

/// A quién sigo (ids de vendedores).
class FollowStore extends ChangeNotifier {
  Set<String> ids = {};

  Future<void> load() async {
    if (appState.account == null) {
      ids = {};
      notifyListeners();
      return;
    }
    try {
      final r = await _db.from('follows').select('seller_id');
      ids = {for (final x in r) x['seller_id'] as String};
      notifyListeners();
    } catch (_) {}
  }

  Future<String?> toggle(String sellerId) async {
    final me = appState.account?.id;
    if (me == null) return 'Inicia sesión para seguir vendedores.';
    try {
      if (ids.contains(sellerId)) {
        await _db
            .from('follows')
            .delete()
            .eq('follower_id', me)
            .eq('seller_id', sellerId);
        ids.remove(sellerId);
      } else {
        await _db.from('follows').insert({'seller_id': sellerId});
        ids.add(sellerId);
      }
      notifyListeners();
      return null;
    } catch (e) {
      return _errorText(e, 'No se pudo. Revisa tu conexión.');
    }
  }
}

final followStore = FollowStore();

/// Botón Seguir / Siguiendo con el número de seguidores.
class FollowButton extends StatefulWidget {
  const FollowButton({super.key, required this.sellerId});
  final String sellerId;

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  int? _count;

  @override
  void initState() {
    super.initState();
    if (followStore.ids.isEmpty) followStore.load();
    _loadCount();
  }

  Future<void> _loadCount() async {
    try {
      final n =
          await _db.rpc('followers_count', params: {'p_user': widget.sellerId});
      if (mounted) setState(() => _count = (n as num).toInt());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: followStore,
      builder: (context, _) {
        final on = followStore.ids.contains(widget.sellerId);
        final label = on ? 'Siguiendo' : 'Seguir';
        return Row(mainAxisSize: MainAxisSize.min, children: [
          on
              ? OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: _tap, child: Text(label))
              : FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: _tap, child: Text(label)),
          if (_count != null) ...[
            const SizedBox(width: 10),
            Text('$_count seguidores',
                style: TextStyle(color: context.muted, fontSize: 13)),
          ],
        ]);
      },
    );
  }

  Future<void> _tap() async {
    if (appState.account == null) {
      showAuthSheet(context, appState,
          message: 'Crea tu cuenta para seguir vendedores.');
      return;
    }
    final err = await followStore.toggle(widget.sellerId);
    if (!mounted) return;
    if (err != null) {
      _snack(context, err);
    } else {
      _loadCount();
    }
  }
}

// ===================== Destacar anuncios =====================

const _planes = {3: 1.0, 7: 2.0};

class PromotePage extends StatefulWidget {
  const PromotePage({super.key});

  @override
  State<PromotePage> createState() => _PromotePageState();
}

class _PromotePageState extends State<PromotePage> {
  List<Listing>? _mine;
  List<Map<String, dynamic>> _requests = [];
  String? _listingId;
  int _days = 7;
  final _ref = TextEditingController();
  bool _busy = false;
  int _gratis = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final me = appState.account?.id;
    if (me == null) return;
    try {
      final l = await _db
          .from('listings')
          .select('*, profiles!listings_seller_id_fkey(username)')
          .eq('seller_id', me)
          .eq('status', 'active')
          .order('created_at', ascending: false);
      final p = await _db
          .from('promotions')
          .select('days, amount, status, created_at, listings(title)')
          .order('created_at', ascending: false)
          .limit(20);
      Map<String, dynamic>? g;
      try {
        g = await _db.from('profiles').select('destacados_gratis').eq('id', me).maybeSingle();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _gratis = ((g?['destacados_gratis'] as num?) ?? 0).toInt();
        _mine = [for (final r in l) Listing.fromMap(r)];
        _requests = List<Map<String, dynamic>>.from(p);
        _listingId ??= _mine!.isEmpty ? null : _mine!.first.id;
      });
    } catch (_) {
      if (mounted) setState(() => _mine = []);
    }
  }

  Future<void> _send() async {
    if (pagosCerrados(context)) return;
    final ref = _ref.text.trim();
    if (_listingId == null || ref.length < 4) {
      _snack(context, 'Elige el anuncio y escribe la referencia del pago.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _db.rpc('request_promotion',
          params: {'p_listing': _listingId, 'p_days': _days, 'p_pay_ref': ref});
      _ref.clear();
      if (mounted)
        _snack(context, 'Recibido. Lo activamos cuando confirmemos el pago.');
      await _load();
    } catch (e) {
      if (mounted) _snack(context, _errorText(e, 'No se pudo enviar.'));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _usarGratis() async {
    if (_listingId == null) return;
    setState(() => _busy = true);
    try {
      await _db.rpc('usar_destacado_gratis', params: {'p_listing': _listingId});
      if (mounted) _snack(context, '¡Listo! Tu anuncio sale destacado los próximos 7 días.');
      await _load();
    } catch (e) {
      if (mounted) _snack(context, _errorText(e, 'No se pudo destacar.'));
    }
    if (mounted) setState(() => _busy = false);
  }

  static const _estado = {
    'revision': 'Verificando pago',
    'activa': 'Activo',
    'rechazada': 'Rechazado',
  };

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    final ink = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(title: const Text('Destacar anuncios')),
      body: mine == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(20), children: [
              Text('Sale primero en Inicio con la etiqueta "Destacado".',
                  style: TextStyle(color: context.muted)),
              const SizedBox(height: 16),
              if (mine.isEmpty)
                const Text('Necesitas un anuncio activo para destacarlo.')
              else ...[
                DropdownButtonFormField<String>(
                  initialValue: _listingId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Anuncio'),
                  items: [
                    for (final l in mine)
                      DropdownMenuItem(
                          value: l.id,
                          child:
                              Text(l.title, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _listingId = v),
                ),
                if (_gratis > 0) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFFFFF1C7), borderRadius: BorderRadius.circular(14)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_gratis == 1 ? 'Te queda 1 destacado gratis de fundador' : 'Tienes $_gratis destacados gratis de fundador',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF3D2800))),
                      const Text('7 días arriba en Inicio, sin pagar nada.', style: TextStyle(color: Color(0xFF6B4500))),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                          onPressed: _busy ? null : _usarGratis,
                          icon: const Icon(Icons.workspace_premium_rounded),
                          label: const Text('Destacar gratis este anuncio')),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  Text('O paga un destacado', style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
                ],
                const SizedBox(height: 12),
                SegmentedButton<int>(
                  segments: [
                    for (final e in _planes.entries)
                      ButtonSegment(
                          value: e.key,
                          label: Text('${e.key} días · ${_usd(e.value)}')),
                  ],
                  selected: {_days},
                  onSelectionChanged: (s) => setState(() => _days = s.first),
                ),
                const SizedBox(height: 16),
                Text('1. Paga ${_usd(_planes[_days]!)} por Pago Móvil',
                    style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
                if (bsText(_planes[_days]!).isNotEmpty)
                  Text(bsText(_planes[_days]!)),
                const SizedBox(height: 4),
                Text(pagosAbiertos
                        ? '$pagoMovilBanco\n$pagoMovilCedula\n$pagoMovilTelefono'
                        : 'Los pagos abren muy pronto. No pagues todavía.',
                    style: TextStyle(color: context.muted)),
                const SizedBox(height: 12),
                Text('2. Escribe la referencia',
                    style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
                const SizedBox(height: 6),
                TextField(
                    controller: _ref,
                    maxLength: 40,
                    decoration: const InputDecoration(
                        labelText: 'Referencia del Pago Móvil')),
                FilledButton(
                    onPressed: _busy ? null : _send,
                    child: const Text('Enviar para revisión')),
              ],
              if (_requests.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Mis solicitudes', style: display(18, color: ink)),
                for (final r in _requests)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(field(r['listings'], 'title', 'Anuncio')),
                    subtitle:
                        Text('${r['days']} días · ${_usd(r['amount'] as num)}'),
                    trailing: Text(_estado[r['status']] ?? '${r['status']}'),
                  ),
              ],
            ]),
    );
  }
}

// ===================== Avisos (campanita) =====================

class AvisosStore extends ChangeNotifier {
  int sinLeer = 0;
  Timer? _timer;

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) => load());
    load();
  }

  Future<void> load() async {
    if (appState.account == null) return;
    try {
      final r =
          await _db.from('avisos').select('id').eq('leido', false).limit(100);
      if (r.length != sinLeer) {
        sinLeer = r.length;
        notifyListeners();
      }
    } catch (_) {}
  }
}

final avisosStore = AvisosStore();

/// Icono de campana con el número de avisos sin leer.
class AvisosButton extends StatefulWidget {
  const AvisosButton({super.key});

  @override
  State<AvisosButton> createState() => _AvisosButtonState();
}

class _AvisosButtonState extends State<AvisosButton> {
  @override
  void initState() {
    super.initState();
    avisosStore.start();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: avisosStore,
      builder: (context, _) {
        final n = avisosStore.sinLeer;
        return IconButton(
          tooltip: 'Avisos',
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => const AvisosPage()))
              .then((_) => avisosStore.load()),
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text(n > 99 ? '99+' : '$n'),
            child: const Icon(Icons.notifications_none),
          ),
        );
      },
    );
  }
}

class AvisosPage extends StatefulWidget {
  const AvisosPage({super.key});

  @override
  State<AvisosPage> createState() => _AvisosPageState();
}

class _AvisosPageState extends State<AvisosPage> {
  List<Map<String, dynamic>>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db
          .from('avisos')
          .select()
          .order('creado', ascending: false)
          .limit(60);
      if (mounted) setState(() => _rows = List<Map<String, dynamic>>.from(r));
    } catch (_) {
      if (mounted) setState(() => _rows = []);
    }
  }

  Future<void> _open(Map<String, dynamic> a) async {
    if (a['leido'] != true) {
      try {
        await _db
            .from('avisos')
            .update({'leido': true}).eq('id', a['id'] as int);
      } catch (_) {}
      avisosStore.load();
    }
    if (!mounted) return;
    final ref = a['ref_id'] as String?;
    Widget? page;
    if (a['tipo'] == 'pedido' && ref != null) page = OrderPage(orderId: ref);
    if (a['tipo'] == 'chat' && ref != null)
      page = ChatPage(threadId: ref, title: 'Conversación');
    if (a['tipo'] == 'anuncio' && ref != null) {
      try {
        final r = await _db
            .from('listings')
            .select('*, profiles!listings_seller_id_fkey(username)')
            .eq('id', ref)
            .maybeSingle();
        if (r != null) page = ListingDetail(item: Listing.fromMap(r));
      } catch (_) {}
      if (!mounted) return;
      if (page == null) _snack(context, 'Ese anuncio ya no está disponible.');
    }
    if (a['tipo'] == 'perfil' && appState.account != null) {
      page = ReviewsPage(
          userId: appState.account!.id, username: appState.account!.username);
    }
    if (page != null)
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => page!));
    _load();
  }

  Future<void> _allRead() async {
    try {
      await _db.from('avisos').update({'leido': true}).eq('leido', false);
    } catch (_) {}
    await _load();
    avisosStore.load();
  }

  static IconData _icon(String tipo) => switch (tipo) {
        'pedido' => Icons.receipt_long_outlined,
        'chat' => Icons.chat_bubble_outline,
        'anuncio' => Icons.local_offer_outlined,
        _ => Icons.star_outline_rounded,
      };

  String _cuando(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'ahora';
    if (d.inHours < 1) return 'hace ${d.inMinutes} min';
    if (d.inDays < 1) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Avisos'), actions: [
        if (rows != null && rows.any((a) => a['leido'] != true))
          TextButton(
              onPressed: _allRead, child: const Text('Marcar todo leído')),
      ]),
      body: Column(children: [
        const PushBanner(),
        Expanded(
          child: rows == null
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                      'Aquí verás mensajes nuevos, ofertas, pagos y envíos.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.muted)),
                ))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final a = rows[i];
                      final unread = a['leido'] != true;
                      return ListTile(
                        tileColor: unread
                            ? scheme.primary.withValues(alpha: 0.06)
                            : null,
                        leading: Icon(_icon('${a['tipo']}'),
                            color: unread ? scheme.primary : context.muted),
                        title: Text('${a['texto']}',
                            style: TextStyle(
                                fontWeight: unread
                                    ? FontWeight.w600
                                    : FontWeight.w400)),
                        subtitle: Text(_cuando('${a['creado']}')),
                        onTap: () => _open(a),
                      );
                    },
                  ),
                ),
        ),
      ]),
    );
  }
}

/// Botón pequeño de Seguir (para el anuncio).
class FollowButtonCompact extends StatelessWidget {
  const FollowButtonCompact({super.key, required this.sellerId});
  final String sellerId;

  @override
  Widget build(BuildContext context) {
    if (followStore.ids.isEmpty && appState.account != null) followStore.load();
    return ListenableBuilder(
      listenable: followStore,
      builder: (context, _) {
        final on = followStore.ids.contains(sellerId);
        return OutlinedButton(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          onPressed: () async {
            if (appState.account == null) {
              showAuthSheet(context, appState,
                  message: 'Crea tu cuenta para seguir vendedores.');
              return;
            }
            final err = await followStore.toggle(sellerId);
            if (err != null && context.mounted) _snack(context, err);
          },
          child: Text(on ? 'Siguiendo' : 'Seguir'),
        );
      },
    );
  }
}
