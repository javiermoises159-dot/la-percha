import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administración'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Pagos'),
            Tab(text: 'Problemas'),
            Tab(text: 'Denuncias'),
            Tab(text: 'Usuarios'),
          ]),
        ),
        body: const TabBarView(children: [
          _OrdersTab(status: 'revision'),
          _OrdersTab(status: 'disputa'),
          _ReportsTab(),
          _UsersTab(),
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
                  Text('${(r['listings'] as Map?)?['title'] ?? 'Prenda'}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                      'Compra @${(r['buyer'] as Map?)?['username']} a @${(r['seller'] as Map?)?['username']}',
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
            subtitle: Text(
                'De @${(r['reporter'] as Map?)?['username']}'
                '${r['listings'] != null ? ' · Prenda: ${(r['listings'] as Map)['title']}' : ''}'
                '${r['target'] != null ? ' · Usuario: @${(r['target'] as Map)['username']}' : ''}'),
          ),
      ]),
    );
  }
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
