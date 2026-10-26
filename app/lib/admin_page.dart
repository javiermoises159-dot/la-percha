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
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administración'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Pagos'),
            Tab(text: 'Problemas'),
            Tab(text: 'Denuncias'),
            Tab(text: 'Usuarios'),
            Tab(text: 'Destacados y tasa'),
          ]),
        ),
        body: const TabBarView(children: [
          _OrdersTab(status: 'revision'),
          _OrdersTab(status: 'disputa'),
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
              'id, price, fee, status, pay_ref, tracking, listings(title), seller:profiles!orders_seller_id_fkey(username), buyer:profiles!orders_buyer_id_fkey(username)')
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
      await _db.from('orders').update({'status': status}).eq('id', id);
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
          child: Text(_error ?? (pagos ? 'No hay pagos por revisar.' : 'No hay problemas abiertos.'),
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
                  if (pagos) Text('Referencia del pago: ${r['pay_ref'] ?? '-'}'),
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
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => OrderPage(orderId: r['id'] as String))),
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
              'reason, created_at, reporter:profiles!reports_reporter_id_fkey(username), listings(title), target:profiles!reports_user_id_fkey(username)')
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
          child: Text('No hay denuncias.', style: TextStyle(color: context.muted)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(children: [
        for (final r in _rows)
          ListTile(
            title: Text('${r['reason']}'),
            subtitle: Text(_detalle(r)),
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
            title: Text('@${r['username']}${r['is_admin'] == true ? '  (admin)' : ''}'),
            subtitle: Text(
                '${r['city']}${r['blocked'] == true ? ' · BLOQUEADO' : ''}'),
            trailing: r['is_admin'] == true
                ? null
                : TextButton(
                    onPressed: () =>
                        _block(r['id'] as String, r['blocked'] != true),
                    child: Text(r['blocked'] == true ? 'Desbloquear' : 'Bloquear'),
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
          .select('id, days, amount, pay_ref, created_at, listings(title), profiles(username)')
          .eq('status', 'revision')
          .order('created_at');
      final t = await _db.from('ajustes').select('valor, actualizado').eq('clave', 'tasa_bs').single();
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Tasa BCV actual: ${_tasa == null ? '…' : 'Bs ${_tasa!.toStringAsFixed(2)}'}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const Text('Se actualiza sola cada hora. Cámbiala solo si la fuente falla.',
            style: TextStyle(fontSize: 12)),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Nueva tasa (Bs por dólar)'),
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
        Text(_rows.isEmpty ? 'No hay destacados por revisar.' : 'Destacados por revisar',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        for (final r in _rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(field(r['listings'], 'title', 'Anuncio'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('@${field(r['profiles'], 'username', '')} · ${r['days']} días · '
                    '\$${(r['amount'] as num).toStringAsFixed(2)}'),
                Text('Referencia: ${r['pay_ref']}'),
                const SizedBox(height: 8),
                Row(children: [
                  OutlinedButton(
                      onPressed: () => _do(() => _db.rpc('admin_review_promotion',
                          params: {'p_id': r['id'], 'p_ok': false})),
                      child: const Text('Rechazar')),
                  const SizedBox(width: 8),
                  FilledButton(
                      onPressed: () => _do(() => _db.rpc('admin_review_promotion',
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
