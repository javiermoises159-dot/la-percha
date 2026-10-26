import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'listing.dart';
import 'orders_page.dart';
import 'theme.dart';

SupabaseClient get _db => Supabase.instance.client;

/// Panel del administrador: confirmar pagos, resolver problemas, denuncias y usuarios.
/// La seguridad real está en el servidor: sin ser admin, estas consultas no devuelven nada.
class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 8,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administración'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Dinero'),
            Tab(text: 'Pagos'),
            Tab(text: 'Problemas'),
            Tab(text: 'Pagar a vendedores'),
            Tab(text: 'Reembolsos'),
            Tab(text: 'Denuncias'),
            Tab(text: 'Usuarios'),
            Tab(text: 'Destacados y tasa'),
          ]),
        ),
        body: const TabBarView(children: [
          _MoneyTab(),
          _OrdersTab(status: 'revision'),
          _OrdersTab(status: 'disputa'),
          _PayoutsTab(),
          _RefundsTab(),
          _ReportsTab(),
          _UsersTab(),
          _PromosTab(),
        ]),
      ),
    );
  }
}

class _OrdersTab extends StatefulWidget {
  const _OrdersTab({required this.status});
  final String status;
  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db
          .from('orders')
          .select(
              'id, price, fee, status, pay_ref, tracking, bundle_id, listings(title), seller:profiles!orders_seller_id_fkey(username), buyer:profiles!orders_buyer_id_fkey(username)')
          .eq('status', widget.status)
          .order('created_at');
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(r);
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'No se pudo cargar.';
        });
      }
    }
  }

  Future<void> _set(String id, String status) async {
    try {
      // En un lote se cambian todos los artículos a la vez.
      final r = _rows.firstWhere((x) => x['id'] == id, orElse: () => const {});
      final b = r['bundle_id'] as String?;
      b == null
          ? await _db.from('orders').update({'status': status}).eq('id', id)
          : await _db
              .from('orders')
              .update({'status': status}).eq('bundle_id', b);
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final pagos = widget.status == 'revision';
    if (_rows.isEmpty) {
      return Center(
          child: Text(
              _error ??
                  (pagos
                      ? 'No hay pagos por revisar.'
                      : 'No hay problemas abiertos.'),
              style: TextStyle(color: context.muted)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        for (final r in _rows)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (r['bundle_id'] != null)
                    const Text(
                        'LOTE: se confirma junto con sus otros artículos',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                  Text(field(r['listings'], 'title', 'Prenda'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                      'Compra @${field(r['buyer'], 'username', '?')} a @${field(r['seller'], 'username', '?')}',
                      style: TextStyle(color: context.muted)),
                  const SizedBox(height: 4),
                  Text(
                      'Total cobrado: \$${((r['price'] as num) + (r['fee'] as num)).toStringAsFixed(2)}  ·  Vendedor recibe: \$${(r['price'] as num).toStringAsFixed(2)}'),
                  if (pagos)
                    Text('Referencia del pago: ${r['pay_ref'] ?? '-'}'),
                  if (!pagos && r['tracking'] != null)
                    Text('Seguimiento: ${r['tracking']}'),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _set(
                            r['id'] as String, pagos ? 'retenido' : 'liberado'),
                        child: Text(pagos ? 'Pago llegó' : 'Pagar al vendedor'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _set(r['id'] as String, 'cancelado'),
                        child: Text(pagos ? 'No llegó' : 'Devolver'),
                      ),
                    ),
                  ]),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                OrderPage(orderId: r['id'] as String))),
                    child: const Text('Ver pedido completo'),
                  ),
                ],
              ),
            ),
          ),
      ]),
    );
  }
}

class _ReportsTab extends StatefulWidget {
  const _ReportsTab();
  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
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
          .from('reports')
          .select(
              'id, reason, created_at, reporter:profiles!reports_reporter_id_fkey(username), listings(title), target:profiles!reports_user_id_fkey(username)')
          .eq('status', 'abierta')
          .order('created_at', ascending: false)
          .limit(50);
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
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_rows.isEmpty) {
      return Center(
          child: Text('No hay denuncias.',
              style: TextStyle(color: context.muted)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(children: [
        for (final r in _rows)
          ListTile(
            title: Text('${r['reason']}'),
            subtitle: Text(_detalle(r)),
            trailing: TextButton(
              onPressed: () async {
                try {
                  await _db
                      .rpc('admin_close_report', params: {'p_id': r['id']});
                } catch (_) {}
                _load();
              },
              child: const Text('Revisada'),
            ),
          ),
      ]),
    );
  }
}

String _detalle(Map<String, dynamic> r) {
  final partes = <String>['De @${field(r['reporter'], 'username', '?')}'];
  if (r['listings'] != null) {
    partes.add('Prenda: ${field(r['listings'], 'title', '')}');
  }
  if (r['target'] != null) {
    partes.add('Usuario: @${field(r['target'], 'username', '')}');
  }
  return partes.join(' · ');
}

class _UsersTab extends StatefulWidget {
  const _UsersTab();
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
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
          .from('profiles')
          .select('id, username, city, blocked, is_admin')
          .order('created_at', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(r);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _block(String id, bool flag) async {
    try {
      await _db.rpc('admin_set_blocked', params: {'uid': id, 'flag': flag});
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(children: [
        for (final r in _rows)
          ListTile(
            title: Text(
                '@${r['username']}${r['is_admin'] == true ? '  (admin)' : ''}'),
            subtitle: Text(
                '${r['city']}${r['blocked'] == true ? ' · BLOQUEADO' : ''}'),
            trailing: r['is_admin'] == true
                ? null
                : TextButton(
                    onPressed: () =>
                        _block(r['id'] as String, r['blocked'] != true),
                    child:
                        Text(r['blocked'] == true ? 'Desbloquear' : 'Bloquear'),
                  ),
          ),
      ]),
    );
  }
}

/// Aprobar pagos de anuncios destacados y fijar la tasa BCV a mano.
class _PromosTab extends StatefulWidget {
  const _PromosTab();
  @override
  State<_PromosTab> createState() => _PromosTabState();
}

class _PromosTabState extends State<_PromosTab> {
  List<Map<String, dynamic>> _rows = [];
  double? _tasa;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await _db
          .from('promotions')
          .select(
              'id, days, amount, pay_ref, created_at, listings(title), profiles(username)')
          .eq('status', 'revision')
          .order('created_at');
      final t = await _db
          .from('ajustes')
          .select('valor, actualizado')
          .eq('clave', 'tasa_bs')
          .single();
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(r);
        _tasa = (t['valor'] as num).toDouble();
      });
    } catch (_) {}
  }

  Future<void> _do(Future<void> Function() f) async {
    try {
      await f();
      await _load();
      listingsStore.load();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(
            'Tasa BCV actual: ${_tasa == null ? '…' : 'Bs ${_tasa!.toStringAsFixed(2)}'}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const Text(
            'Se actualiza sola cada hora. Cámbiala solo si la fuente falla.',
            style: TextStyle(fontSize: 12)),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Nueva tasa (Bs por dólar)'),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(_ctrl.text.trim().replaceAll(',', '.'));
              if (v == null || v <= 0) return;
              _do(() => _db.rpc('admin_set_tasa', params: {'v': v}));
              _ctrl.clear();
            },
            child: const Text('Guardar'),
          ),
        ]),
        const Divider(height: 32),
        Text(
            _rows.isEmpty
                ? 'No hay destacados por revisar.'
                : 'Destacados por revisar',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        for (final r in _rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(field(r['listings'], 'title', 'Anuncio'),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                        '@${field(r['profiles'], 'username', '')} · ${r['days']} días · '
                        '\$${(r['amount'] as num).toStringAsFixed(2)}'),
                    Text('Referencia: ${r['pay_ref']}'),
                    const SizedBox(height: 8),
                    Row(children: [
                      OutlinedButton(
                          onPressed: () => _do(() => _db.rpc(
                              'admin_review_promotion',
                              params: {'p_id': r['id'], 'p_ok': false})),
                          child: const Text('Rechazar')),
                      const SizedBox(width: 8),
                      FilledButton(
                          onPressed: () => _do(() => _db.rpc(
                              'admin_review_promotion',
                              params: {'p_id': r['id'], 'p_ok': true})),
                          child: const Text('Pago recibido: activar')),
                    ]),
                  ]),
            ),
          ),
      ]),
    );
  }
}

/// Ventas completadas que falta pagar al vendedor, con sus datos de Pago Móvil.
class _PayoutsTab extends StatefulWidget {
  const _PayoutsTab();
  @override
  State<_PayoutsTab> createState() => _PayoutsTabState();
}

class _PayoutsTabState extends State<_PayoutsTab> {
  List<Map<String, dynamic>>? _rows;
  Map<String, Map> _payout = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db
          .from('orders')
          .select(
              'id, price, seller_id, bundle_id, updated_at, released_at, listings(title), seller:profiles!orders_seller_id_fkey(username)')
          .eq('status', 'liberado')
          .isFilter('paid_out_at', null)
          .order('updated_at');
      final ids = {for (final x in r) x['seller_id'] as String}.toList();
      final p = ids.isEmpty
          ? <Map<String, dynamic>>[]
          : await _db
              .from('private_profiles')
              .select('id, payout')
              .inFilter('id', ids);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(r);
        _payout = {
          for (final x in p)
            x['id'] as String: (x['payout'] as Map?) ?? const {}
        };
      });
    } catch (_) {
      if (mounted) setState(() => _rows = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows == null) return const Center(child: CircularProgressIndicator());
    if (rows.isEmpty) {
      return Center(
          child: Text('No hay pagos pendientes a vendedores.',
              style: TextStyle(color: context.muted)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        for (final r in rows)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(field(r['listings'], 'title', 'Artículo'),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      if (_atrasado(r['released_at'] ?? r['updated_at'], 2))
                        const _Atrasado(),
                    ]),
                    Text(
                        '@${field(r['seller'], 'username', '?')} recibe \$${(r['price'] as num).toStringAsFixed(2)}'
                        '${r['bundle_id'] != null ? ' (parte de un lote)' : ''}'),
                    const SizedBox(height: 4),
                    Builder(builder: (_) {
                      final p = _payout[r['seller_id']] ?? const {};
                      return Text(p.isEmpty
                          ? 'El vendedor no ha puesto sus datos de cobro (Perfil → Saldo).'
                          : 'Pago Móvil: ${p['banco']} · ${p['cedula']} · ${p['telefono']}');
                    }),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () async {
                        try {
                          await _db.rpc('admin_mark_paid',
                              params: {'p_order': r['id']});
                        } catch (_) {}
                        _load();
                      },
                      child: const Text('Ya le pagué'),
                    ),
                  ]),
            ),
          ),
      ]),
    );
  }
}


/// ¿Ya pasaron [dias] días hábiles (lunes a viernes) desde [desde]?
bool _atrasado(Object? desde, int dias) {
  final t = DateTime.tryParse('${desde ?? ''}');
  if (t == null) return false;
  var d = t.toUtc().subtract(const Duration(hours: 4)); // hora de Venezuela
  var k = 0;
  while (k < dias) {
    d = d.add(const Duration(days: 1));
    if (d.weekday <= 5) k++;
  }
  return DateTime.now().toUtc().subtract(const Duration(hours: 4)).isAfter(d);
}

class _Atrasado extends StatelessWidget {
  const _Atrasado();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: const Color(0xFFFDE8E4), borderRadius: BorderRadius.circular(20)),
        child: const Text('Atrasado',
            style: TextStyle(
                color: LP.clayText, fontWeight: FontWeight.w700, fontSize: 12)),
      );
}

String _usd(Object? v) => '\$${((v as num?) ?? 0).toStringAsFixed(2)}';
num _n(Object? v) => (v is num) ? v : num.tryParse('${v ?? ''}') ?? 0;

/// Cuadre del dinero: lo que debe haber en la cuenta de Pavito y el registro diario.
class _MoneyTab extends StatefulWidget {
  const _MoneyTab();
  @override
  State<_MoneyTab> createState() => _MoneyTabState();
}

class _MoneyTabState extends State<_MoneyTab> {
  Map<String, dynamic>? _c;
  List<Map<String, dynamic>> _hist = [];
  final _saldo = TextEditingController();
  final _nota = TextEditingController();
  String? _msg;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saldo.dispose();
    _nota.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await _db.rpc('admin_cuadre');
      final h = await _db
          .from('cuadres')
          .select('dia, saldo_bs, saldo_usd, esperado_usd, diferencia_usd, nota')
          .order('creado', ascending: false)
          .limit(14);
      if (!mounted) return;
      setState(() {
        _c = Map<String, dynamic>.from(c as Map);
        _hist = List<Map<String, dynamic>>.from(h);
      });
    } catch (_) {
      if (mounted) setState(() => _c = {});
    }
  }

  Future<void> _guardar() async {
    final v = num.tryParse(_saldo.text.replaceAll('.', '').replaceAll(',', '.').trim());
    if (v == null || v < 0) {
      setState(() => _msg = 'Escribe el saldo de la cuenta en bolívares.');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = Map<String, dynamic>.from(await _db.rpc('admin_guardar_cuadre',
          params: {'p_saldo_bs': v, 'p_nota': _nota.text.trim()}) as Map);
      final dif = _n(r['diferencia_usd']);
      _saldo.clear();
      _nota.clear();
      _msg = dif.abs() < 0.5
          ? 'Cuadre guardado: la cuenta cuadra.'
          : dif < 0
              ? 'Cuadre guardado: faltan ${_usd(-dif)} en la cuenta. Revísalo hoy.'
              : 'Cuadre guardado: sobran ${_usd(dif)} (ganancias no retiradas o pagos sin registrar).';
      await _load();
    } catch (e) {
      _msg = 'No se pudo guardar: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return const Center(child: CircularProgressIndicator());
    if (c.isEmpty) {
      return Center(
          child: Text('No se pudo cargar el cuadre.',
              style: TextStyle(color: context.muted)));
    }
    final tasa = _n(c['tasa']);
    String bs(Object? v) => tasa > 0
        ? 'Bs ${(_n(v) * tasa).toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')}'
        : '';
    Widget fila(String t, Object? v, {bool fuerte = false, String? ayuda}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: TextStyle(fontWeight: fuerte ? FontWeight.w800 : FontWeight.w500)),
                if (ayuda != null)
                  Text(ayuda, style: TextStyle(color: context.muted, fontSize: 12.5)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_usd(_n(v)),
                  style: TextStyle(fontWeight: fuerte ? FontWeight.w800 : FontWeight.w600)),
              if (tasa > 0)
                Text(bs(v), style: TextStyle(color: context.muted, fontSize: 12.5)),
            ]),
          ]),
        );
    final alertas = <String>[
      if (_n(c['pagos_atrasados']) > 0)
        '${c['pagos_atrasados']} pago(s) a vendedores pasados de 2 días hábiles',
      if (_n(c['reembolsos_atrasados']) > 0)
        '${c['reembolsos_atrasados']} reembolso(s) pasados de 5 días hábiles',
      if (_n(c['disputas_atrasadas']) > 0)
        '${c['disputas_atrasadas']} problema(s) abiertos hace más de 5 días hábiles',
      if (_n(c['envios_por_vencer']) > 0)
        '${c['envios_por_vencer']} venta(s) sin enviar a punto de cancelarse',
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (alertas.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFFFDE8E4), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Atención', style: TextStyle(fontWeight: FontWeight.w800, color: LP.clayText)),
              for (final a in alertas) Text('• $a'),
            ]),
          ),
        Text('Dinero de otros', style: display(18, color: context.ink)),
        Text('Siempre tiene que estar en la cuenta de Pavito.',
            style: TextStyle(color: context.muted)),
        fila('Pedidos en curso', c['retenido'], ayuda: 'Pagos confirmados que aún no se liberan'),
        fila('Por pagar a vendedores', c['por_pagar'], ayuda: 'Ventas completadas sin pagar'),
        fila('Reembolsos pendientes', c['reembolsos'], ayuda: 'Pedidos cancelados ya pagados'),
        fila('Total de otros', c['terceros'], fuerte: true),
        const Divider(height: 28),
        Text('Ganancia de Pavito', style: display(18, color: context.ink)),
        fila('Tarifas de protección', c['tarifas'], ayuda: 'De ventas completadas'),
        fila('Destacados', c['destacados']),
        const Divider(height: 28),
        fila('Debe haber en la cuenta', c['esperado'],
            fuerte: true, ayuda: 'Si no has retirado ganancias'),
        fila('Pagos por verificar', c['por_verificar'],
            ayuda: 'Reportados por compradores, aún sin confirmar (no se suman)'),
        const SizedBox(height: 18),
        Text('Cuadre de hoy', style: display(18, color: context.ink)),
        const SizedBox(height: 8),
        TextField(
          controller: _saldo,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Saldo real de la cuenta (Bs)'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nota,
          maxLength: 300,
          decoration: const InputDecoration(labelText: 'Nota (opcional)'),
        ),
        FilledButton(
            onPressed: _busy ? null : _guardar, child: const Text('Guardar cuadre')),
        if (_msg != null) ...[
          const SizedBox(height: 8),
          Text(_msg!, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
        if (_hist.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('Últimos cuadres', style: display(16, color: context.ink)),
          for (final h in _hist)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${h['dia']} · cuenta ${_usd(_n(h['saldo_usd']))}'),
              subtitle: Text('Esperado ${_usd(_n(h['esperado_usd']))}'
                  '${h['nota'] != null ? ' · ${h['nota']}' : ''}'),
              trailing: Text(
                _n(h['diferencia_usd']).abs() < 0.5
                    ? 'Cuadra'
                    : '${_n(h['diferencia_usd']) > 0 ? '+' : ''}${_usd(_n(h['diferencia_usd']))}',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _n(h['diferencia_usd']) < -0.5 ? LP.clayText : LP.ok),
              ),
            ),
        ],
      ]),
    );
  }
}

/// Pedidos cancelados que ya estaban pagados: hay que devolver el dinero al comprador.
class _RefundsTab extends StatefulWidget {
  const _RefundsTab();
  @override
  State<_RefundsTab> createState() => _RefundsTabState();
}

class _RefundsTabState extends State<_RefundsTab> {
  List<Map<String, dynamic>>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db
          .from('orders')
          .select(
              'id, price, fee, bundle_id, pay_ref, cancelled_at, updated_at, delivery, listings(title), buyer:profiles!orders_buyer_id_fkey(username)')
          .eq('status', 'cancelado')
          .not('paid_at', 'is', null)
          .isFilter('refunded_at', null)
          .order('cancelled_at');
      // Un lote se devuelve de una vez: se agrupa por lote.
      final g = <String, Map<String, dynamic>>{};
      for (final x in r) {
        final k = (x['bundle_id'] ?? x['id']) as String;
        final t = _n(x['price']) + _n(x['fee']);
        if (g.containsKey(k)) {
          g[k]!['total'] = _n(g[k]!['total']) + t;
          g[k]!['n'] = (g[k]!['n'] as int) + 1;
        } else {
          g[k] = {...x, 'total': t, 'n': 1};
        }
      }
      if (mounted) setState(() => _rows = g.values.toList());
    } catch (_) {
      if (mounted) setState(() => _rows = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows == null) return const Center(child: CircularProgressIndicator());
    if (rows.isEmpty) {
      return Center(
          child: Text('No hay reembolsos pendientes.',
              style: TextStyle(color: context.muted)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        for (final r in rows)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                        r['n'] == 1
                            ? field(r['listings'], 'title', 'Artículo')
                            : 'Lote de ${r['n']} artículos',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  if (_atrasado(r['cancelled_at'] ?? r['updated_at'], 5)) const _Atrasado(),
                ]),
                Text('Devolver ${_usd(r['total'])} a @${field(r['buyer'], 'username', '?')}'),
                Text('Referencia de su pago: ${r['pay_ref'] ?? '—'}',
                    style: TextStyle(color: context.muted)),
                if (r['delivery'] is Map && (r['delivery'] as Map)['phone'] != null)
                  Text('Teléfono: ${(r['delivery'] as Map)['phone']}',
                      style: TextStyle(color: context.muted)),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () async {
                    try {
                      await _db.rpc('admin_mark_refunded', params: {'p_order': r['id']});
                    } catch (_) {}
                    _load();
                  },
                  child: const Text('Ya le devolví el dinero'),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
