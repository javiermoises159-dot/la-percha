import 'dart:convert';
import 'package:flutter/material.dart';
import 'admin_chat.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'listing.dart';
import 'listing_detail.dart';
import 'orders_page.dart';
import 'pruebas.dart';
import 'theme.dart';

SupabaseClient get _db => Supabase.instance.client;

/// Panel del administrador, organizado como un back-office:
/// inicio con lo pendiente y las métricas, y una sección para cada tarea.
/// La seguridad real está en el servidor: sin ser admin (con verificación en dos pasos),
/// estas consultas no devuelven nada.
class _Seccion {
  const _Seccion(this.titulo, this.icono, this.contador, this.ayuda, this.pagina);
  final String titulo;
  final IconData icono;
  final String? contador; // clave en los contadores (pendientes)
  final String ayuda;
  final Widget Function() pagina;
}

final _secciones = <_Seccion>[
  _Seccion('Pagos por verificar', Icons.fact_check_outlined, 'revision',
      'Compradores que dicen haber pagado', () => const _OrdersTab(status: 'revision')),
  _Seccion('Problemas', Icons.report_problem_outlined, 'disputa',
      'Pedidos con un reclamo abierto', () => const _OrdersTab(status: 'disputa')),
  _Seccion('Retiros', Icons.payments_outlined, 'por_pagar',
      'Saldo que piden retirar a su Pago Móvil', () => const _RetirosTab()),
  _Seccion('Denuncias', Icons.flag_outlined, 'denuncias',
      'Anuncios o usuarios denunciados', () => const _ReportsTab()),
  _Seccion('Destacados y tasa', Icons.rocket_launch_outlined, 'destacados',
      'Destacados por aprobar y tasa del BCV', () => const _PromosTab()),
  _Seccion('Pedidos', Icons.receipt_long_outlined, null,
      'Buscar cualquier pedido', () => const _AllOrdersTab()),
  _Seccion('Anuncios', Icons.checkroom_outlined, null,
      'Revisar y ocultar anuncios', () => const _ListingsAdminTab()),
  _Seccion('Usuarios', Icons.people_alt_outlined, null,
      'Buscar y bloquear usuarios', () => const _UsersTab()),
  _Seccion('Dinero', Icons.account_balance_outlined, null,
      'Cuadre, ganancias y registro', () => const _MoneyTab()),
  _Seccion('Errores de la app', Icons.bug_report_outlined, 'errores_24h',
      'Fallos que vieron los usuarios (últimas 24 h)', () => const _ErroresTab()),
];

/// Cuenta lo pendiente y las métricas principales.
class _Contadores {
  static Future<Map<String, num>> cargar() async {
    // Cuenta pidiendo solo la columna id: los pedidos tienen permisos por columna y un
    // conteo "de todo" (select=*) sería rechazado por el servidor.
    Future<int> c(Future<PostgrestResponse<PostgrestList>> f) async {
      try {
        return (await f).count;
      } catch (_) {
        return 0;
      }
    }
    final semana = DateTime.now().toUtc().subtract(const Duration(days: 7)).toIso8601String();
    final mes = DateTime.now().toUtc().subtract(const Duration(days: 30)).toIso8601String();
    final r = await Future.wait([
      c(_db.from('orders').select('id').eq('status', 'revision').limit(1).count(CountOption.exact)),
      c(_db.from('orders').select('id').eq('status', 'disputa').limit(1).count(CountOption.exact)),
      c(_db.from('retiros').select('id').eq('estado', 'pendiente').limit(1).count(CountOption.exact)),
      Future.value(0),
      c(_db.from('reports').select('id').eq('status', 'abierta').limit(1).count(CountOption.exact)),
      c(_db.from('promotions').select('id').eq('status', 'revision').limit(1).count(CountOption.exact)),
      c(_db.from('listings').select('id').eq('status', 'active').limit(1).count(CountOption.exact)),
      c(_db.from('profiles').select('id').limit(1).count(CountOption.exact)),
      c(_db.from('orders').select('id').gte('created_at', semana).limit(1).count(CountOption.exact)),
      c(_db.from('profiles').select('id').gte('created_at', semana).limit(1).count(CountOption.exact)),
    ]);
    num gmv = 0, ganancia = 0;
    int ventas = 0;
    final alertas = <String, num>{};
    try {
      final a = await _db.rpc('admin_alertas');
      if (a is Map) {
        for (final k in ['errores_24h', 'tasa_horas', 'pagos_atascados', 'retiros_atrasados']) {
          final v = a[k];
          if (v is num) alertas[k] = v;
        }
      }
    } catch (_) {}
    try {
      final v = await _db.from('orders').select('price, fee').eq('status', 'liberado').gte('released_at', mes).limit(2000);
      for (final x in v) {
        gmv += _n(x['price']);
        ganancia += _n(x['fee']);
        ventas++;
      }
    } catch (_) {}
    return {
      'revision': r[0], 'disputa': r[1], 'por_pagar': r[2], 'reembolsos': r[3], 'denuncias': r[4],
      'destacados': r[5], 'anuncios': r[6], 'usuarios': r[7], 'pedidos_semana': r[8], 'nuevos_semana': r[9],
      'gmv': gmv, 'ganancia': ganancia, 'ventas': ventas,
      ...alertas,
    };
  }
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int _sel = -1; // -1 = inicio
  Map<String, num> _c = {};
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  Future<void> _recargar() async {
    setState(() => _cargando = true);
    final c = await _Contadores.cargar();
    if (mounted) setState(() {
      _c = c;
      _cargando = false;
    });
  }

  void _abrir(int i, bool ancho) {
    if (ancho) {
      setState(() => _sel = i);
      _recargar();
    } else {
      Navigator.of(context)
          .push(MaterialPageRoute<void>(
              builder: (_) => Scaffold(appBar: AppBar(title: Text(_secciones[i].titulo)), body: _secciones[i].pagina())))
          .then((_) => _recargar());
    }
  }

  Widget _badge(String? k) {
    final n = k == null ? 0 : (_c[k] ?? 0);
    if (n == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: LP.clay, borderRadius: BorderRadius.circular(20)),
      child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width >= 900;
    final inicio = _Inicio(c: _c, cargando: _cargando, onRecargar: _recargar, onAbrir: (i) => _abrir(i, ancho), badge: _badge);
    if (!ancho) {
      return Scaffold(appBar: AppBar(title: const Text('Administración')), body: inicio);
    }
    return Scaffold(
      appBar: AppBar(title: Text(_sel < 0 ? 'Administración' : _secciones[_sel].titulo)),
      body: Row(children: [
        SizedBox(
          width: 260,
          child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
            _ItemMenu(icono: Icons.space_dashboard_outlined, titulo: 'Inicio', activo: _sel < 0, onTap: () {
              setState(() => _sel = -1);
              _recargar();
            }),
            const Divider(height: 16),
            for (var i = 0; i < _secciones.length; i++)
              _ItemMenu(icono: _secciones[i].icono, titulo: _secciones[i].titulo, activo: _sel == i,
                  trailing: _badge(_secciones[i].contador), onTap: () => _abrir(i, true)),
          ]),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _sel < 0 ? inicio : KeyedSubtree(key: ValueKey(_sel), child: _secciones[_sel].pagina())),
      ]),
    );
  }
}

class _ItemMenu extends StatelessWidget {
  const _ItemMenu({required this.icono, required this.titulo, required this.activo, required this.onTap, this.trailing});
  final IconData icono;
  final String titulo;
  final bool activo;
  final VoidCallback onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Material(
          color: activo ? context.chip : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            dense: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: Icon(icono, size: 21),
            title: Text(titulo, style: TextStyle(fontWeight: activo ? FontWeight.w800 : FontWeight.w600)),
            trailing: trailing,
            onTap: onTap,
          ),
        ),
      );
}

/// Inicio del panel: lo pendiente primero, después las métricas y el resto de secciones.
class _Inicio extends StatelessWidget {
  const _Inicio({required this.c, required this.cargando, required this.onRecargar, required this.onAbrir, required this.badge});
  final Map<String, num> c;
  final bool cargando;
  final Future<void> Function() onRecargar;
  final void Function(int) onAbrir;
  final Widget Function(String?) badge;

  @override
  Widget build(BuildContext context) {
    final pendientes = [for (var i = 0; i < _secciones.length; i++) if (_secciones[i].contador != null) i];
    final otras = [for (var i = 0; i < _secciones.length; i++) if (_secciones[i].contador == null) i];
    final totalPend = pendientes.fold<num>(0, (a, i) => a + (c[_secciones[i].contador] ?? 0));
    Widget metrica(String t, String v, {String? sub}) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: context.chip, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: TextStyle(color: context.muted, fontSize: 12.5)),
            const SizedBox(height: 4),
            Text(v, style: display(24, color: context.ink)),
            if (sub != null) Text(sub, style: TextStyle(color: context.muted, fontSize: 12)),
          ]),
        );
    return RefreshIndicator(
      onRefresh: onRecargar,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(
            child: Text(totalPend == 0 ? 'Todo al día' : 'Tienes $totalPend cosas pendientes',
                style: display(22, color: context.ink)),
          ),
          if (cargando) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else IconButton(tooltip: 'Actualizar', onPressed: onRecargar, icon: const Icon(Icons.refresh_rounded)),
        ]),
        _Atencion(c: c, onAbrir: onAbrir),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, k) {
          final cols = k.maxWidth > 700 ? 3 : 2;
          final w = (k.maxWidth - 10 * (cols - 1)) / cols;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final i in pendientes)
              SizedBox(
                width: w,
                child: Material(
                  color: (c[_secciones[i].contador] ?? 0) > 0 ? const Color(0xFFFDE8E4) : context.chip,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onAbrir(i),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(_secciones[i].icono, size: 20),
                          const Spacer(),
                          Text('${c[_secciones[i].contador] ?? 0}', style: display(26, color: context.ink)),
                        ]),
                        const SizedBox(height: 6),
                        Text(_secciones[i].titulo, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(_secciones[i].ayuda, style: TextStyle(color: context.muted, fontSize: 12)),
                      ]),
                    ),
                  ),
                ),
              ),
          ]);
        }),
        const SizedBox(height: 22),
        Text('Cómo va Pavito', style: display(18, color: context.ink)),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, k) {
          final cols = k.maxWidth > 860 ? 5 : k.maxWidth > 560 ? 3 : 2;
          final w = (k.maxWidth - 10 * (cols - 1)) / cols;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            SizedBox(width: w, child: metrica('Anuncios activos', '${c['anuncios'] ?? 0}')),
            SizedBox(width: w, child: metrica('Usuarios', '${c['usuarios'] ?? 0}', sub: '+${c['nuevos_semana'] ?? 0} esta semana')),
            SizedBox(width: w, child: metrica('Pedidos (7 días)', '${c['pedidos_semana'] ?? 0}')),
            SizedBox(width: w, child: metrica('Ventas (30 días)', '${c['ventas'] ?? 0}', sub: 'Vendido ${_usd(c['gmv'] ?? 0)}')),
            SizedBox(width: w, child: metrica('Ganancia (30 días)', _usd(c['ganancia'] ?? 0), sub: 'Tarifas de protección')),
          ]);
        }),
        const SizedBox(height: 22),
        Text('Herramientas', style: display(18, color: context.ink)),
        const SizedBox(height: 6),
        for (final i in otras)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(backgroundColor: context.chip, child: Icon(_secciones[i].icono, color: context.ink, size: 20)),
            title: Text(_secciones[i].titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(_secciones[i].ayuda),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onAbrir(i),
          ),
      ]),
    );
  }
}

/// Todos los pedidos: buscar por referencia, guía o número de pedido y filtrar por estado.
/// Caja roja con lo que puede romper el negocio si nadie lo mira.
class _Atencion extends StatelessWidget {
  const _Atencion({required this.c, required this.onAbrir});
  final Map<String, num> c;
  final void Function(int) onAbrir;

  int _idx(String contador) => _secciones.indexWhere((s) => s.contador == contador);

  @override
  Widget build(BuildContext context) {
    final avisos = <(String, int)>[];
    final tasaH = c['tasa_horas'];
    if (tasaH == null || tasaH < 0) {
      if (c.containsKey('errores_24h')) avisos.add(('No hay tasa del BCV guardada: fíjala en Destacados y tasa.', _idx('destacados')));
    } else if (tasaH > 6) {
      avisos.add(('La tasa del BCV no se actualiza hace ${tasaH.round()} h: fíjala en Destacados y tasa.'
          '${tasaH > 24 ? ' Pago Móvil está oculto para los compradores hasta que la actualices.' : ''}', _idx('destacados')));
    }
    final atascados = c['pagos_atascados'] ?? 0;
    if (atascados > 0) {
      avisos.add(('$atascados ${atascados == 1 ? 'pago espera' : 'pagos esperan'} verificación hace más de 12 h.', _idx('revision')));
    }
    final retiros = c['retiros_atrasados'] ?? 0;
    if (retiros > 0) {
      avisos.add(('$retiros ${retiros == 1 ? 'retiro lleva' : 'retiros llevan'} más de 2 días hábiles sin pagarse.', _idx('por_pagar')));
    }
    final errores = c['errores_24h'] ?? 0;
    if (errores > 0) {
      avisos.add(('La app falló $errores ${errores == 1 ? 'vez' : 'veces'} en las últimas 24 h.', _idx('errores_24h')));
    }
    if (avisos.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFDE8E4),
        border: Border.all(color: const Color(0xFFD9534F)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFB3261E)),
          SizedBox(width: 8),
          Text('Atención', style: TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        for (final a in avisos)
          InkWell(
            onTap: a.$2 < 0 ? null : () => onAbrir(a.$2),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Expanded(child: Text(a.$1, style: const TextStyle(color: Color(0xFF5C1A15), fontWeight: FontWeight.w600))),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF5C1A15)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Errores que la app reportó desde los teléfonos de los usuarios.
class _ErroresTab extends StatefulWidget {
  const _ErroresTab();
  @override
  State<_ErroresTab> createState() => _ErroresTabState();
}

class _ErroresTabState extends State<_ErroresTab> {
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
          .from('errores_app')
          .select('id, mensaje, pila, plataforma, version, url, creado')
          .order('creado', ascending: false)
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_rows.isEmpty) {
      return Center(child: Text('Sin errores. Todo funciona.', style: TextStyle(color: context.muted)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(children: [
        for (final r in _rows)
          ExpansionTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: Text('${r['mensaje']}', maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text([
              _fecha(r['creado']),
              if ((r['plataforma'] ?? '') != '') '${r['plataforma']}',
              if ((r['version'] ?? '') != '') 'v${r['version']}',
            ].join(' · ')),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((r['url'] ?? '') != '') Text('Pantalla: ${r['url']}', style: TextStyle(color: context.muted)),
              const SizedBox(height: 6),
              SelectableText('${r['mensaje']}\n\n${r['pila'] ?? ''}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ],
          ),
      ]),
    );
  }
}

String _fecha(dynamic v) {
  final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
  if (d == null) return '';
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(d.day)}/${dos(d.month)} ${dos(d.hour)}:${dos(d.minute)}';
}

class _AllOrdersTab extends StatefulWidget {
  const _AllOrdersTab();
  @override
  State<_AllOrdersTab> createState() => _AllOrdersTabState();
}

class _AllOrdersTabState extends State<_AllOrdersTab> {
  final _q = TextEditingController();
  String? _estado;
  List<Map<String, dynamic>>? _rows;
  static const _estados = {
    'esperando_pago': 'Sin pagar', 'revision': 'Verificando', 'retenido': 'Retenido', 'enviado': 'Enviado',
    'liberado': 'Completado', 'disputa': 'Problema', 'devolucion': 'Devolución', 'cancelado': 'Cancelado',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      var f = _db.from('orders').select(
          'id, price, fee, status, pay_ref, tracking, created_at, listings(title), seller:profiles!orders_seller_id_fkey(username), buyer:profiles!orders_buyer_id_fkey(username)');
      if (_estado != null) f = f.eq('status', _estado!);
      final q = _q.text.trim().replaceAll(RegExp(r'[,()*%]'), '');
      if (q.isNotEmpty) {
        f = RegExp(r'^[0-9a-f-]{36}$').hasMatch(q) ? f.eq('id', q) : f.or('pay_ref.ilike.*$q*,tracking.ilike.*$q*');
      }
      final r = await f.order('created_at', ascending: false).limit(100);
      if (mounted) setState(() => _rows = List<Map<String, dynamic>>.from(r));
    } catch (_) {
      if (mounted) setState(() => _rows = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          controller: _q,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(),
          decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search), hintText: 'Referencia de pago, guía o número de pedido',
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _load)),
        ),
      ),
      SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), children: [
          Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: const Text('Todos'), selected: _estado == null, onSelected: (_) { setState(() => _estado = null); _load(); })),
          for (final e in _estados.entries)
            Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(e.value), selected: _estado == e.key, onSelected: (_) { setState(() => _estado = e.key); _load(); })),
        ]),
      ),
      Expanded(
        child: rows == null
            ? const Center(child: CircularProgressIndicator())
            : rows.isEmpty
                ? Center(child: Text('No hay pedidos con ese filtro.', style: TextStyle(color: context.muted)))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = rows[i];
                        final f = DateTime.tryParse('${r['created_at']}')?.toLocal();
                        return ListTile(
                          title: Text(field(r['listings'], 'title', 'Artículo'), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('@${field(r['buyer'], 'username', '?')} compra a @${field(r['seller'], 'username', '?')}'
                              '${f != null ? ' · ${f.day}/${f.month}' : ''}${r['pay_ref'] != null ? ' · Ref ${r['pay_ref']}' : ''}'),
                          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(_usd(_n(r['price']) + _n(r['fee'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(_estados[r['status']] ?? '${r['status']}', style: TextStyle(color: context.muted, fontSize: 12)),
                          ]),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OrderPage(orderId: r['id'] as String))),
                        );
                      },
                    ),
                  ),
      ),
    ]);
  }
}

/// Moderación de anuncios: buscar, ver y ocultar los que incumplen las reglas.
class _ListingsAdminTab extends StatefulWidget {
  const _ListingsAdminTab();
  @override
  State<_ListingsAdminTab> createState() => _ListingsAdminTabState();
}

class _ListingsAdminTabState extends State<_ListingsAdminTab> {
  final _q = TextEditingController();
  List<Map<String, dynamic>>? _rows;
  static const _est = {'active': 'Visible', 'hidden': 'Oculto', 'reserved': 'Reservado', 'sold': 'Vendido'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      var f = _db.from('listings').select('*, profiles!listings_seller_id_fkey(username)');
      final q = _q.text.trim().replaceAll(RegExp(r'[,()*%]'), '');
      if (q.isNotEmpty) f = f.ilike('title', '%$q%');
      final r = await f.order('created_at', ascending: false).limit(100);
      if (mounted) setState(() => _rows = List<Map<String, dynamic>>.from(r));
    } catch (_) {
      if (mounted) setState(() => _rows = []);
    }
  }

  Future<void> _estado(String id, String st) async {
    try {
      await _db.from('listings').update({'status': st}).eq('id', id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is PostgrestException ? e.message : 'No se pudo cambiar.')));
      }
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          controller: _q,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(),
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Buscar por título',
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _load)),
        ),
      ),
      Expanded(
        child: rows == null
            ? const Center(child: CircularProgressIndicator())
            : rows.isEmpty
                ? Center(child: Text('No hay anuncios.', style: TextStyle(color: context.muted)))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = rows[i];
                        final l = Listing.fromMap(r);
                        final st = '${r['status']}';
                        return ListTile(
                          leading: SizedBox(width: 52, height: 52,
                              child: ClipRRect(borderRadius: BorderRadius.circular(8), child: ListingPhoto(item: l, iconSize: 22))),
                          title: Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${_usd(l.price)} · @${l.seller} · ${l.category} · ${_est[st] ?? st}'),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ListingDetail(item: l))),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) => _estado(l.id, v),
                            itemBuilder: (_) => [
                              if (st == 'active') const PopupMenuItem(value: 'hidden', child: Text('Ocultar anuncio')),
                              if (st == 'hidden') const PopupMenuItem(value: 'active', child: Text('Volver a mostrar')),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
      ),
    ]);
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
          .order('created_at', ascending: true);
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
    const q = {
      'retenido': '¿Confirmas que el pago llegó a la cuenta? El vendedor recibirá el aviso para enviar.',
      'cancelado': '¿Cancelar este pedido? Si ya estaba pagado, el dinero vuelve al instante al Saldo Pavito del comprador.',
      'liberado': '¿Cerrar el reclamo a favor del vendedor? El dinero pasa a su Saldo Pavito.',
      'devolucion': '¿Pedir la devolución? El comprador tendrá 3 días hábiles para enviar la prenda; cuando el vendedor la reciba, el dinero vuelve al comprador.',
    };
    if (!await _seguro(context, q[status] ?? '¿Confirmas el cambio?')) return;
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
                  if (!pagos) ...[
                    const SizedBox(height: 8),
                    PruebasBloque(orderId: r['id'] as String, ocultarSiVacio: true),
                    if (r['status'] == 'disputa' || r['status'] == 'devolucion')
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.forum_outlined, size: 18),
                          label: const Text('Ver chat entre ellos'),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => AdminChatPage(
                                  orderId: r['id'] as String,
                                  titulo: '@${field(r['buyer'], 'username', '?')} y @${field(r['seller'], 'username', '?')}'))),
                        ),
                      ),
                  ],
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
                        child: Text(pagos ? 'No llegó' : 'Reembolsar sin devolución'),
                      ),
                    ),
                  ]),
                  if (!pagos) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.assignment_return_outlined, size: 18),
                      onPressed: () => _set(r['id'] as String, 'devolucion'),
                      label: const Text('Pedir devolución de la prenda'),
                    ),
                  ],
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
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.history, size: 18),
            label: const Text('Chats consultados'),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const AdminAccesosChatPage())),
          ),
        ),
        for (final r in _rows)
          ListTile(
            title: Text('${r['reason']}'),
            subtitle: Text(_detalle(r)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => AdminChatPage(reportId: r['id'] as String, titulo: 'Chat de la denuncia'))),
            leading: const Icon(Icons.forum_outlined),
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

  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      var f = _db.from('profiles').select('id, username, city, blocked, is_admin, verificado, fundador_n, created_at');
      final q = _q.text.trim().replaceAll(RegExp(r'[^A-Za-z0-9_.]'), '');
      if (q.isNotEmpty) f = f.ilike('username', '%$q%');
      final r = await f.order('created_at', ascending: false).limit(100);
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
    if (!await _seguro(context, flag
        ? '¿Bloquear a esta persona? No podrá publicar, comprar ni escribir.'
        : '¿Desbloquear a esta persona?')) return;
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

  Future<void> _verificar(String id, bool si) async {
    if (!await _seguro(context, si
        ? '¿Marcar como vendedor verificado? Hazlo solo si comprobaste su identidad (cédula y teléfono).'
        : '¿Quitar la insignia de verificado?')) return;
    try {
      await _db.rpc('admin_set_verificado', params: {'p_user': id, 'p_si': si});
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          controller: _q,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(),
          decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search), hintText: 'Buscar por nombre de usuario',
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _load)),
        ),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(children: [
                  for (final r in _rows)
                    ListTile(
                      title: Text('@${r['username']}${r['is_admin'] == true ? '  (admin)' : ''}'
                          '${r['verificado'] == true ? '  ✔ verificado' : ''}'),
                      subtitle: Text('${r['city']}'
                          '${r['fundador_n'] != null ? ' · Fundador #${r['fundador_n']}' : ''}'
                          '${r['blocked'] == true ? ' · BLOQUEADO' : ''}'),
                      trailing: r['is_admin'] == true
                          ? null
                          : PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'ver') _verificar(r['id'] as String, true);
                                if (v == 'nover') _verificar(r['id'] as String, false);
                                if (v == 'bloq') _block(r['id'] as String, true);
                                if (v == 'desbloq') _block(r['id'] as String, false);
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                    value: r['verificado'] == true ? 'nover' : 'ver',
                                    child: Text(r['verificado'] == true ? 'Quitar verificado' : 'Marcar como verificado')),
                                PopupMenuItem(
                                    value: r['blocked'] == true ? 'desbloq' : 'bloq',
                                    child: Text(r['blocked'] == true ? 'Desbloquear' : 'Bloquear')),
                              ],
                            ),
                    ),
                ]),
              ),
      ),
    ]);
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
              'id, days, amount, pay_ref, created_at, listings(title), profiles!promotions_seller_id_fkey(username)')
          .eq('status', 'revision')
          .order('created_at', ascending: true);
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
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), 
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
                      OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)), 
                          onPressed: () => _do(() => _db.rpc(
                              'admin_review_promotion',
                              params: {'p_id': r['id'], 'p_ok': false})),
                          child: const Text('Rechazar')),
                      const SizedBox(width: 8),
                      FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), 
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

/// Retiros pedidos por los usuarios desde su Saldo Pavito: se pagan por Pago Móvil.
class _RetirosTab extends StatefulWidget {
  const _RetirosTab();
  @override
  State<_RetirosTab> createState() => _RetirosTabState();
}

class _RetirosTabState extends State<_RetirosTab> {
  List<Map<String, dynamic>>? _rows;
  bool _verPagados = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db
          .from('retiros')
          .select('id, monto, estado, destino, ref_pago, motivo, creado, resuelto_at, user:profiles!retiros_user_id_fkey(username)')
          .eq('estado', _verPagados ? 'pagado' : 'pendiente')
          .order('creado', ascending: !_verPagados)
          .limit(100);
      if (mounted) setState(() => _rows = List<Map<String, dynamic>>.from(r));
    } catch (_) {
      if (mounted) setState(() => _rows = []);
    }
  }

  void _aviso(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is PostgrestException ? e.message : 'No se pudo completar.')));
  }

  /// Datos completos para hacer el Pago Móvil (cada consulta queda registrada).
  Future<void> _verDatos(Map<String, dynamic> r) async {
    try {
      final d = Map<String, dynamic>.from(
          (await _db.rpc('admin_datos_retiro', params: {'p_retiro': r['id']})) as Map);
      if (!mounted) return;
      final bs = tasaBs > 0 ? (_n(r['monto']) * tasaBs) : 0;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Datos para el Pago Móvil'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText('Banco: ${d['banco']}\nCédula / RIF: ${d['cedula']}\nTeléfono: ${d['telefono']}'),
            const SizedBox(height: 8),
            SelectableText('Monto: ${_usd(r['monto'])}${bs > 0 ? '  ·  Bs ${bs.toStringAsFixed(2)} (tasa ${tasaBs.toStringAsFixed(2)})' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (d['cambiado_despues'] == true) ...[
              const SizedBox(height: 8),
              const Text('Cambió sus datos después de pedir el retiro: no se puede pagar. Recházalo.',
                  style: TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 8),
            Text('Esta consulta quedó registrada.', style: TextStyle(color: c.muted, fontSize: 12)),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar'))],
        ),
      );
    } catch (e) {
      _aviso(e);
    }
  }

  Future<void> _pagar(Map<String, dynamic> r) async {
    final ref = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('¿Ya le enviaste ${_usd(r['monto'])}?'),
        content: TextField(
            controller: ref,
            decoration: const InputDecoration(labelText: 'Referencia del Pago Móvil que hiciste')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Volver')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sí, ya le pagué')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.rpc('admin_pagar_retiro', params: {'p_retiro': r['id'], 'p_ref': ref.text.trim()});
    } catch (e) {
      _aviso(e);
    }
    _load();
  }

  Future<void> _rechazar(Map<String, dynamic> r) async {
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Rechazar retiro'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('El dinero vuelve a su Saldo Pavito y le avisamos el motivo.'),
          const SizedBox(height: 8),
          TextField(controller: motivo, decoration: const InputDecoration(labelText: 'Motivo (ej. datos incorrectos)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Volver')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Rechazar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.rpc('admin_rechazar_retiro', params: {'p_retiro': r['id'], 'p_motivo': motivo.text.trim()});
    } catch (e) {
      _aviso(e);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          ChoiceChip(label: const Text('Por pagar'), selected: !_verPagados, onSelected: (_) {
            setState(() => _verPagados = false);
            _load();
          }),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Pagados'), selected: _verPagados, onSelected: (_) {
            setState(() => _verPagados = true);
            _load();
          }),
        ]),
      ),
      Expanded(
        child: rows == null
            ? const Center(child: CircularProgressIndicator())
            : rows.isEmpty
                ? Center(child: Text(_verPagados ? 'Todavía no hay retiros pagados.' : 'No hay retiros por pagar.',
                    style: TextStyle(color: context.muted)))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(padding: const EdgeInsets.all(16), children: [
                      for (final r in rows)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(
                                  child: Text('@${field(r['user'], 'username', '?')} retira ${_usd(r['monto'])}',
                                      style: const TextStyle(fontWeight: FontWeight.w800)),
                                ),
                                if (!_verPagados && _atrasado(r['creado'], 2)) const _Atrasado(),
                              ]),
                              if (tasaBs > 0)
                                Text('≈ Bs ${(_n(r['monto']) * tasaBs).toStringAsFixed(2)} a la tasa de hoy',
                                    style: TextStyle(color: context.muted)),
                              Text('Destino: ${_destino(r['destino'])}', style: TextStyle(color: context.muted)),
                              if (_verPagados && r['ref_pago'] != null)
                                Text('Referencia: ${r['ref_pago']}', style: TextStyle(color: context.muted)),
                              if (!_verPagados) ...[
                                const SizedBox(height: 10),
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                                    icon: const Icon(Icons.lock_open_outlined, size: 18),
                                    label: const Text('Ver datos para pagar'),
                                    onPressed: () => _verDatos(r),
                                  ),
                                  FilledButton(
                                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                                      onPressed: () => _pagar(r),
                                      child: const Text('Ya le pagué')),
                                  TextButton(onPressed: () => _rechazar(r), child: const Text('Rechazar')),
                                ]),
                              ],
                            ]),
                          ),
                        ),
                    ]),
                  ),
      ),
    ]);
  }
}

/// El destino guardado es el resumen enmascarado de los datos de cobro.
String _destino(Object? d) {
  try {
    final m = d is Map ? d : (jsonDecode('${d ?? ''}') as Map);
    return '${m['banco']} · ${m['cedula']} · ${m['telefono']}';
  } catch (_) {
    return '${d ?? '—'}';
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
  List<Map<String, dynamic>> _log = [];
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
      final lg = await _db.rpc('admin_auditoria', params: {'p_limite': 30});
      if (!mounted) return;
      setState(() {
        _c = Map<String, dynamic>.from(c as Map);
        _hist = List<Map<String, dynamic>>.from(h);
        _log = List<Map<String, dynamic>>.from(lg as List);
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
        '${c['pagos_atrasados']} retiro(s) pasados de 2 días hábiles',
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
        fila('Saldos de los usuarios', c['saldos'], ayuda: 'Ventas cobradas y devoluciones que aún no retiran'),
        fila('Retiros por pagar', c['retiros_pendientes'], ayuda: 'Pedidos de retiro a Pago Móvil'),
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
        if (_log.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('Registro de acciones', style: display(16, color: context.ink)),
          Text('Queda guardado para siempre: nadie lo puede borrar.',
              style: TextStyle(color: context.muted, fontSize: 12.5)),
          for (final a in _log)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${_accion[a['accion']] ?? a['accion']} · @${a['quien']}'),
              subtitle: Text('${DateTime.tryParse('${a['creado']}')?.toLocal().toString().substring(0, 16) ?? ''}'
                  '${a['detalle'] is Map && (a['detalle'] as Map)['usd'] != null ? ' · ${_usd(_n((a['detalle'] as Map)['usd']))}' : ''}'),
            ),
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

const _accion = {
  'estado_pedido': 'Cambio de estado de pedido',
  'pago_a_vendedor': 'Pago a vendedor',
  'reembolso': 'Reembolso',
  'ver_datos_cobro': 'Vio datos bancarios',
  'ver_datos_retiro': 'Vio datos para un retiro',
  'cambio_datos_cobro': 'Cambio de datos de cobro',
  'pedir_retiro': 'Pidió un retiro',
  'pagar_retiro': 'Pagó un retiro',
  'rechazar_retiro': 'Rechazó un retiro',
  'pago_con_saldo': 'Pagó con su saldo',
  'bloqueo': 'Bloqueó a un usuario',
  'verificar': 'Verificó a un vendedor',
  'quitar_verificado': 'Quitó la verificación',
  'desbloqueo': 'Desbloqueó a un usuario',
  'tasa': 'Cambio de tasa',
  'cuadre': 'Cuadre guardado',
};

/// Confirmación del administrador antes de mover dinero o estados.
Future<bool> _seguro(BuildContext context, String texto) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Confirmar'),
      content: Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Volver')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sí, confirmar')),
      ],
    ),
  );
  return r == true;
}
