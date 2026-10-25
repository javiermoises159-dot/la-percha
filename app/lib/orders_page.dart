import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'auth_sheet.dart';
import 'config.dart';
import 'listing.dart';
import 'listing_detail.dart';
import 'theme.dart';

SupabaseClient get _db => Supabase.instance.client;

const _statusLabel = {
  'esperando_pago': 'Esperando tu pago',
  'revision': 'Verificando el pago',
  'retenido': 'Pago retenido: el vendedor debe enviar',
  'enviado': 'Enviado: confirma cuando lo recibas',
  'liberado': 'Completado',
  'disputa': 'En revisión por un problema',
  'cancelado': 'Cancelado',
};

String _money(num v) => '\$${v.toStringAsFixed(2)}';

/// Punto de entrada del botón "Comprar".
void startCheckout(BuildContext context, Listing item) {
  if (appState.account == null) {
    showAuthSheet(context, appState,
        message: 'Crea tu cuenta para comprar con protección.');
    return;
  }
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => CheckoutPage(item: item)));
}

/// Datos de entrega y creación del pedido.
class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key, required this.item});
  final Listing item;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final address = _address.text.trim();
    if (name.length < 3 || phone.length < 7 || address.length < 6) {
      setState(() => _error = 'Completa tu nombre, teléfono y dirección.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final row = await _db
          .from('orders')
          .insert({
            'listing_id': widget.item.id,
            'price': widget.item.price,
            'delivery': {'name': name, 'phone': phone, 'address': address},
          })
          .select('id')
          .single();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => OrderPage(orderId: row['id'] as String)));
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No se pudo crear el pedido. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final fee = buyerFee(item.price);
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar compra')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(item.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        _Box(children: [
          _Line('Prenda', _money(item.price)),
          _Line('Protección al comprador', _money(fee)),
          _Line('Total (sin envío)', _money(item.price + fee), bold: true),
        ]),
        const SizedBox(height: 20),
        Text('¿Dónde te la enviamos?',
            style: display(20, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 10),
        TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre completo')),
        const SizedBox(height: 10),
        TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Teléfono')),
        const SizedBox(height: 10),
        TextField(
            controller: _address,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Dirección o punto de entrega')),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: Text(_busy ? 'Creando pedido...' : 'Continuar al pago'),
        ),
        const SizedBox(height: 8),
        Text(
            'Tu dinero queda retenido hasta que confirmes que recibiste la prenda.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.muted, fontSize: 13)),
      ]),
    );
  }
}

/// Un pedido: estado y las acciones que le tocan a cada persona.
class OrderPage extends StatefulWidget {
  const OrderPage({super.key, required this.orderId});
  final String orderId;

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  Map<String, dynamic>? _o;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final _ref = TextEditingController();
  final _tracking = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ref.dispose();
    _tracking.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await _db
          .from('orders')
          .select(
              '*, listings(title), seller:profiles!orders_seller_id_fkey(username), buyer:profiles!orders_buyer_id_fkey(username)')
          .eq('id', widget.orderId)
          .single();
      if (!mounted) return;
      setState(() {
        _o = row;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar el pedido.';
      });
    }
  }

  Future<void> _update(Map<String, dynamic> values) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _db.from('orders').update(values).eq('id', widget.orderId);
      await _load();
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No se pudo actualizar. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    return Scaffold(
      appBar: AppBar(title: const Text('Pedido')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : o == null
              ? Center(child: Text(_error ?? 'Pedido no encontrado.'))
              : _body(context, o),
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> o) {
    final me = appState.account?.id;
    final isBuyer = o['buyer_id'] == me;
    final status = o['status'] as String;
    final price = (o['price'] as num).toDouble();
    final fee = (o['fee'] as num).toDouble();
    final title = (o['listings'] as Map?)?['title'] ?? 'Prenda';
    final other = isBuyer
        ? (o['seller'] as Map?)?['username']
        : (o['buyer'] as Map?)?['username'];
    final delivery = (o['delivery'] as Map?) ?? const {};
    final ink = Theme.of(context).colorScheme.onSurface;

    final actions = <Widget>[];
    if (isBuyer && status == 'esperando_pago') {
      actions.addAll([
        Text('Paga por Pago Móvil', style: display(20, color: ink)),
        const SizedBox(height: 8),
        _Box(children: [
          _Line('Banco', pagoMovilBanco),
          _Line('Cédula / RIF', pagoMovilCedula),
          _Line('Teléfono', pagoMovilTelefono),
          _Line('Monto en dólares', _money(price + fee), bold: true),
        ]),
        const SizedBox(height: 10),
        Text(
            'Haz el pago desde tu banco, luego escribe aquí el número de referencia y toca "Ya pagué".',
            style: TextStyle(color: context.muted, fontSize: 13)),
        const SizedBox(height: 10),
        TextField(
            controller: _ref,
            keyboardType: TextInputType.number,
            decoration:
                const InputDecoration(labelText: 'Número de referencia')),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  final r = _ref.text.trim();
                  if (r.length < 4) {
                    setState(() => _error = 'Escribe la referencia del pago.');
                    return;
                  }
                  _update({'status': 'revision', 'pay_ref': r});
                },
          child: const Text('Ya pagué'),
        ),
      ]);
    }
    if (status == 'esperando_pago') {
      actions.addAll([
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : () => _update({'status': 'cancelado'}),
          child: const Text('Cancelar pedido'),
        ),
      ]);
    }
    if (!isBuyer && status == 'retenido') {
      actions.addAll([
        Text('Envía la prenda', style: display(20, color: ink)),
        const SizedBox(height: 8),
        TextField(
            controller: _tracking,
            decoration: const InputDecoration(
                labelText: 'Guía o dato de seguimiento (empresa y número)')),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  final t = _tracking.text.trim();
                  if (t.length < 3) {
                    setState(() => _error = 'Escribe el dato de seguimiento.');
                    return;
                  }
                  _update({'status': 'enviado', 'tracking': t});
                },
          child: const Text('Marcar como enviado'),
        ),
      ]);
    }
    if (isBuyer && status == 'enviado') {
      actions.addAll([
        FilledButton(
          onPressed: _busy ? null : () => _update({'status': 'liberado'}),
          child: const Text('Ya la recibí, liberar el pago'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _busy ? null : () => _update({'status': 'disputa'}),
          child: const Text('Tuve un problema'),
        ),
      ]);
    }

    String hint = '';
    if (status == 'revision') {
      hint = 'Estamos verificando tu pago. Te avisamos cuando quede retenido.';
    } else if (status == 'retenido' && isBuyer) {
      hint = 'Pago confirmado. El vendedor ya puede enviarte la prenda.';
    } else if (status == 'enviado' && !isBuyer) {
      hint = 'Esperando que el comprador confirme que la recibió.';
    } else if (status == 'liberado' && !isBuyer) {
      hint = 'Completado. El pago de ${_money(price)} es tuyo.';
    } else if (status == 'disputa') {
      hint = 'Nuestro equipo revisará el caso y te contactará.';
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Text(title.toString(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(isBuyer ? 'Vendedor: @$other' : 'Comprador: @$other',
            style: TextStyle(color: context.muted)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: context.leafSoft, borderRadius: BorderRadius.circular(12)),
          child: Text(_statusLabel[status] ?? status,
              style: TextStyle(fontWeight: FontWeight.w700, color: context.leaf)),
        ),
        if (hint.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(hint, style: TextStyle(color: context.muted)),
        ],
        const SizedBox(height: 14),
        _Box(children: [
          _Line('Prenda', _money(price)),
          if (isBuyer) _Line('Protección', _money(fee)),
          _Line(isBuyer ? 'Total' : 'Recibes', _money(isBuyer ? price + fee : price),
              bold: true),
        ]),
        if (!isBuyer && delivery.isNotEmpty) ...[
          const SizedBox(height: 14),
          _Box(children: [
            _Line('Enviar a', '${delivery['name'] ?? ''}'),
            _Line('Teléfono', '${delivery['phone'] ?? ''}'),
            _Line('Dirección', '${delivery['address'] ?? ''}'),
          ]),
        ],
        if (o['tracking'] != null) ...[
          const SizedBox(height: 14),
          _Box(children: [_Line('Seguimiento', '${o['tracking']}')]),
        ],
        const SizedBox(height: 18),
        ...actions,
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
        ],
      ]),
    );
  }
}

/// Lista de compras y ventas.
class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db
          .from('orders')
          .select('id, price, fee, status, buyer_id, listings(title)')
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(r);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = appState.account?.id;
    final buys = [for (final r in _rows) if (r['buyer_id'] == me) r];
    final sells = [for (final r in _rows) if (r['buyer_id'] != me) r];
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mis pedidos'),
          bottom: const TabBar(tabs: [Tab(text: 'Compras'), Tab(text: 'Ventas')]),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [_list(buys, true), _list(sells, false)]),
      ),
    );
  }

  Widget _list(List<Map<String, dynamic>> rows, bool buying) {
    if (rows.isEmpty) {
      return Center(
          child: Text(buying ? 'Aún no has comprado nada.' : 'Aún no has vendido nada.',
              style: TextStyle(color: context.muted)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(children: [
        for (final r in rows)
          ListTile(
            title: Text('${(r['listings'] as Map?)?['title'] ?? 'Prenda'}'),
            subtitle: Text(_statusLabel[r['status']] ?? '${r['status']}'),
            trailing: Text(_money(buying
                ? (r['price'] as num) + (r['fee'] as num)
                : r['price'] as num)),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => OrderPage(orderId: r['id'] as String)));
              _load();
            },
          ),
      ]),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: context.chip, borderRadius: BorderRadius.circular(12)),
        child: Column(children: children),
      );
}

class _Line extends StatelessWidget {
  const _Line(this.a, this.b, {this.bold = false});
  final String a;
  final String b;
  final bool bold;
  @override
  Widget build(BuildContext context) {
    final s = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(a, style: s),
            const SizedBox(width: 12),
            Flexible(child: Text(b, style: s, textAlign: TextAlign.right)),
          ]),
    );
  }
}
