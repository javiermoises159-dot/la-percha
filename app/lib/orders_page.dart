import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'features.dart';
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

/// Lee un campo de un objeto anidado de forma segura.
String field(Object? m, String key, String fallback) {
  if (m is Map && m[key] != null) return '${m[key]}';
  return fallback;
}

String _money(num v) => '\$${v.toStringAsFixed(2)}';

/// Fecha límite para enviar: 3 días desde que se confirmó el pago.
String? _limiteEnvio(Map o) {
  final p = DateTime.tryParse('${o['paid_at'] ?? ''}');
  if (p == null) return null;
  final d = p.add(const Duration(days: 3)).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)} a las ${two(d.hour)}:${two(d.minute)}';
}

/// Formas de entrega en Venezuela. La última siempre es en persona.
const metodosEntrega = [
  'MRW (cobro a destino)',
  'Zoom (cobro a destino)',
  'Tealca (cobro a destino)',
  'Entrega en persona (punto seguro)',
];

/// Envío el mismo día dentro de la ciudad con Yummy. Aparece solo cuando el admin
/// lo activa (ajustes.yummy_activo = 1), cuando la integración esté lista.
const metodoYummy = 'Envío Yummy (hoy, en tu ciudad)';
bool _yummyActivo = false;
List<String> metodosDisponibles() => _yummyActivo
    ? [...metodosEntrega.take(metodosEntrega.length - 1), metodoYummy, metodosEntrega.last]
    : metodosEntrega;
Future<void> cargarMetodosEntrega() async {
  try {
    final r = await _db.from('ajustes').select('valor').eq('clave', 'yummy_activo').maybeSingle();
    _yummyActivo = (r?['valor'] as num?) == 1;
  } catch (_) {}
}

/// Nota que acompaña al método elegido.
String? notaEntrega(String m) {
  if (m == metodoYummy) {
    return 'Un motorizado de Yummy retira el artículo con el vendedor y te lo entrega hoy. '
        'No tienes que verte con nadie. El costo del envío lo ves antes de pagar.';
  }
  if (m == metodosEntrega.last) {
    return 'Queden en un lugar público y concurrido (centro comercial, plaza con vigilancia), '
        'de día. Revisa el artículo ANTES de confirmar en la app. Nunca pagues en efectivo '
        'aparte: el pago va siempre por Pavito.';
  }
  return null;
}

/// Formas de pago. Pago Móvil en bolívares; Binance Pay y Zinli en dólares.
/// Binance y Zinli se ocultan si sus datos en config.dart están vacíos.
const pagoPagoMovil = 'Pago Móvil';
const pagoBinance = 'Binance Pay';
const pagoZinli = 'Zinli';
List<String> metodosPago() => [
      pagoPagoMovil,
      if (binancePayId.isNotEmpty) pagoBinance,
      if (zinliCorreo.isNotEmpty) pagoZinli,
    ];
String instruccionPago(String m) {
  if (m == pagoBinance) {
    return 'En Binance ve a Pay → Enviar, pega el Pay ID y envía el monto exacto en USDT. '
        'Luego copia aquí el "ID de la orden" y toca "Ya pagué".';
  }
  if (m == pagoZinli) {
    return 'En Zinli toca Enviar, escribe el correo y envía el monto exacto. '
        'Luego copia aquí el número de la transacción y toca "Ya pagué".';
  }
  return 'Haz el pago desde tu banco, luego escribe aquí el número de referencia y toca "Ya pagué".';
}
String etiquetaRefPago(String m) => m == pagoBinance
    ? 'ID de la orden de Binance'
    : m == pagoZinli
        ? 'Número de transacción Zinli'
        : 'Número de referencia';
/// La referencia guarda el método al inicio (p. ej. "Binance: 123…"), así el
/// equipo sabe dónde verificarla sin cambiar la base de datos.
String refConMetodo(String m, String r) =>
    m == pagoBinance ? 'Binance: $r' : m == pagoZinli ? 'Zinli: $r' : r;

/// Punto de entrada del botón "Comprar".
/// Si los pagos aún no están abiertos, lo explica y devuelve true.
bool pagosCerrados(BuildContext context) {
  if (pagosAbiertos) return false;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Los pagos abren muy pronto', style: display(22, color: ctx.ink)),
          const SizedBox(height: 8),
          Text(
              'Estamos terminando de preparar la compra protegida. Mientras tanto puedes guardar en '
              'favoritos lo que te guste, escribirle al vendedor y hacerle una oferta. Te avisaremos '
              'apenas puedas comprar.',
              style: TextStyle(color: ctx.muted, height: 1.4)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
          ),
        ]),
      ),
    ),
  );
  return true;
}

void startCheckout(BuildContext context, Listing item) {
  if (pagosCerrados(context)) return;
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
  double? _price; // precio acordado (oferta aceptada) o el del anuncio
  String _metodo = metodosEntrega.first;

  @override
  void initState() {
    super.initState();
    myPriceFor(widget.item).then((p) {
      if (mounted) setState(() => _price = p);
    });
    cargarMetodosEntrega().then((_) {
      if (mounted) setState(() {});
    });
  }

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
            // El precio y la tarifa los pone el servidor desde la base de datos
            // (y la oferta aceptada, si la hay); la app no los envía.
            'listing_id': widget.item.id,
            'delivery': {
              'name': name,
              'phone': phone,
              'address': address,
              'metodo': _metodo
            },
          })
          .select('id')
          .single();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => OrderPage(orderId: row['id'] as String)));
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(
          () => _error = 'No se pudo crear el pedido. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final price = _price ?? item.price;
    final fee = buyerFee(price);
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar compra')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(item.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        _Box(children: [
          if (price < item.price) _Line('Precio original', _money(item.price)),
          _Line(price < item.price ? 'Precio acordado' : 'Artículo',
              _money(price)),
          _Line('Protección al comprador', _money(fee)),
          _Line('Total (sin envío)', _money(price + fee), bold: true),
          if (bsText(price + fee).isNotEmpty) _Line('', bsText(price + fee)),
        ]),
        const SizedBox(height: 20),
        Text('¿Dónde te la enviamos?',
            style: display(20, color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _metodo,
          decoration: const InputDecoration(labelText: 'Cómo lo recibes'),
          items: [
            for (final m in metodosDisponibles())
              DropdownMenuItem(value: m, child: Text(m)),
          ],
          onChanged: (v) => setState(() => _metodo = v ?? _metodo),
        ),
        if (notaEntrega(_metodo) != null) ...[
          const SizedBox(height: 8),
          Text(notaEntrega(_metodo)!,
              style: TextStyle(color: context.muted, fontSize: 13)),
        ],
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
  String _pago = pagoPagoMovil;
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
              'id, listing_id, buyer_id, seller_id, price, fee, status, pay_ref, tracking, created_at, updated_at, bundle_id, paid_out_at, paid_at, refunded_at, listings(title), seller:profiles!orders_seller_id_fkey(username), buyer:profiles!orders_buyer_id_fkey(username)')
          .eq('id', widget.orderId)
          .single();
      // La dirección y el teléfono solo los entrega el servidor a quien puede verlos
      // (el vendedor, solo cuando el pago está confirmado).
      final delivery =
          await _db.rpc('order_delivery', params: {'oid': widget.orderId});
      // En un lote, se muestran y se actualizan todos los artículos juntos.
      List<Map<String, dynamic>> group = const [];
      if (row['bundle_id'] != null) {
        group = List<Map<String, dynamic>>.from(await _db
            .from('orders')
            .select('id, price, fee, listings(title)')
            .eq('bundle_id', row['bundle_id'] as String)
            .order('created_at'));
      }
      if (!mounted) return;
      setState(() {
        _o = {...row, 'delivery': delivery, 'group': group};
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
      final bundle = _o?['bundle_id'] as String?;
      bundle == null
          ? await _db.from('orders').update(values).eq('id', widget.orderId)
          : await _db.from('orders').update(values).eq('bundle_id', bundle);
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
    final group = (o['group'] as List?) ?? const [];
    double total(String k) => group.isEmpty
        ? (o[k] as num).toDouble()
        : group.fold(0.0, (a, r) => a + ((r as Map)[k] as num).toDouble());
    final price = total('price');
    final fee = total('fee');
    final title = group.isEmpty
        ? field(o['listings'], 'title', 'Artículo')
        : 'Lote de ${group.length} artículos';
    final reviewId = (o['bundle_id'] as String?) ?? widget.orderId;
    final other = field(isBuyer ? o['seller'] : o['buyer'], 'username', '');
    final delivery = (o['delivery'] as Map?) ?? const {};
    final ink = Theme.of(context).colorScheme.onSurface;

    final actions = <Widget>[];
    if (isBuyer && status == 'esperando_pago') {
      final metodos = metodosPago();
      if (!metodos.contains(_pago)) _pago = metodos.first;
      final m = _pago;
      actions.addAll([
        Text('¿Cómo quieres pagar?', style: display(20, color: ink)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final x in metodos)
            ChoiceChip(
              label: Text(x),
              selected: x == m,
              onSelected: _busy ? null : (_) => setState(() { _pago = x; _ref.clear(); }),
            ),
        ]),
        const SizedBox(height: 10),
        if (!pagosAbiertos)
          _Box(children: [
            Text('Los pagos abren muy pronto. No pagues todavía: te avisaremos cuando la compra protegida esté lista.',
                style: TextStyle(color: context.muted, height: 1.4)),
          ])
        else
        _Box(children: [
          if (m == pagoPagoMovil) ...[
            _Line('Banco', pagoMovilBanco),
            _Line('Cédula / RIF', pagoMovilCedula),
            _Line('Teléfono', pagoMovilTelefono),
          ],
          if (m == pagoBinance) ...[
            _Line('Pay ID', binancePayId),
            _Line('Nombre', binancePayNombre),
            _Line('Moneda', 'USDT'),
          ],
          if (m == pagoZinli) ...[
            _Line('Correo Zinli', zinliCorreo),
            _Line('Nombre', zinliNombre),
          ],
          _Line(m == pagoBinance ? 'Monto en USDT' : 'Monto en dólares', _money(price + fee), bold: true),
        ]),
        const SizedBox(height: 10),
        Text(instruccionPago(m), style: TextStyle(color: context.muted, fontSize: 13, height: 1.35)),
        const SizedBox(height: 10),
        TextField(
            controller: _ref,
            keyboardType: m == pagoPagoMovil ? TextInputType.number : TextInputType.text,
            maxLength: 30,
            decoration: InputDecoration(labelText: etiquetaRefPago(m), counterText: '')),
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
                  _update({'status': 'revision', 'pay_ref': refConMetodo(m, r)});
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
        if (_limiteEnvio(o) != null) ...[
          const SizedBox(height: 6),
          Text(
              'Tienes hasta el ${_limiteEnvio(o)} para enviarla y cargar la guía. '
              'Si no, el pedido se cancela y el dinero vuelve al comprador.',
              style: TextStyle(color: context.muted, height: 1.35)),
        ],
        const SizedBox(height: 8),
        TextField(
            controller: _tracking,
            decoration: const InputDecoration(
                labelText: 'Guía (empresa y número) o "Entregado en persona"')),
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
      final l = _limiteEnvio(o);
      hint = 'Pago confirmado. El vendedor ya puede enviarte la prenda.'
          '${l == null ? '' : ' Tiene hasta el $l; si no la envía, te devolvemos todo.'}';
    } else if (status == 'enviado' && !isBuyer) {
      hint = 'Esperando que el comprador confirme que la recibió.';
    } else if (status == 'liberado' && !isBuyer) {
      hint = 'Completado. El pago de ${_money(price)} es tuyo.';
    } else if (status == 'disputa') {
      hint = 'Nuestro equipo revisará el caso y te contactará.';
    } else if (status == 'cancelado' && isBuyer && o['paid_at'] != null) {
      hint = o['refunded_at'] != null
          ? 'Ya te devolvimos el dinero por el mismo medio con que pagaste.'
          : 'Te devolvemos todo lo que pagaste, por el mismo medio, en un máximo de 5 días hábiles.';
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
              style:
                  TextStyle(fontWeight: FontWeight.w700, color: context.leaf)),
        ),
        if (group.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final g in group)
            Text(
                '• ${field((g as Map)['listings'], 'title', 'Artículo')} · ${_money(g['price'] as num)}',
                style: TextStyle(color: context.muted)),
          if (!isBuyer)
            Text('Envía todo junto en un solo paquete.',
                style: TextStyle(color: context.muted, fontSize: 13)),
        ],
        if (hint.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(hint, style: TextStyle(color: context.muted)),
        ],
        const SizedBox(height: 14),
        _Box(children: [
          _Line('Prenda', _money(price)),
          if (isBuyer) _Line('Protección', _money(fee)),
          _Line(isBuyer ? 'Total' : 'Recibes',
              _money(isBuyer ? price + fee : price),
              bold: true),
        ]),
        if (!isBuyer && delivery.isNotEmpty) ...[
          const SizedBox(height: 14),
          _Box(children: [
            _Line('Entrega', field(delivery, 'metodo', 'Envío')),
            _Line('Enviar a', field(delivery, 'name', '')),
            _Line('Teléfono', field(delivery, 'phone', '')),
            _Line('Dirección', field(delivery, 'address', '')),
          ]),
        ],
        if (o['tracking'] != null) ...[
          const SizedBox(height: 14),
          _Box(children: [_Line('Seguimiento', '${o['tracking']}')]),
        ],
        const SizedBox(height: 18),
        ...actions,
        if (status == 'liberado' && other.isNotEmpty)
          ReviewButton(orderId: reviewId, otherName: other),
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
    final buys = [
      for (final r in _rows)
        if (r['buyer_id'] == me) r
    ];
    final sells = [
      for (final r in _rows)
        if (r['buyer_id'] != me) r
    ];
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mis pedidos'),
          bottom:
              const TabBar(tabs: [Tab(text: 'Compras'), Tab(text: 'Ventas')]),
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
          child: Text(
              buying ? 'Aún no has comprado nada.' : 'Aún no has vendido nada.',
              style: TextStyle(color: context.muted)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(children: [
        for (final r in rows)
          ListTile(
            title: Text(field(r['listings'], 'title', 'Prenda')),
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
