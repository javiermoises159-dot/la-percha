import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'theme.dart';

/// Panel: visitas por día, de dónde llegan y quién se registró.
class VisitasAdminPage extends StatefulWidget {
  const VisitasAdminPage({super.key});
  @override
  State<VisitasAdminPage> createState() => _VisitasAdminPageState();
}

class _VisitasAdminPageState extends State<VisitasAdminPage> {
  int _dias = 14;
  Map<String, dynamic>? _d;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Supabase.instance.client.rpc('admin_visitas', params: {'p_dias': _dias});
      if (mounted) setState(() => (_d = Map<String, dynamic>.from(r as Map), _error = null));
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudieron cargar las visitas.');
    }
  }

  int _n(Object? v) => (v as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (_error != null) return Center(child: Text(_error!));
    if (d == null) return const Center(child: CircularProgressIndicator());
    final hoy = Map<String, dynamic>.from(d['hoy'] as Map);
    final tot = Map<String, dynamic>.from(d['total'] as Map);
    final dias = List<Map<String, dynamic>>.from(d['dias'] as List);
    final orig = List<Map<String, dynamic>>.from(d['origenes'] as List);
    final rutas = List<Map<String, dynamic>>.from(d['rutas'] as List);
    final plat = List<Map<String, dynamic>>.from(d['plataformas'] as List);
    final nuevos = List<Map<String, dynamic>>.from(d['nuevos'] as List);
    final maxV = dias.fold<int>(1, (m, x) => _n(x['visitas']) > m ? _n(x['visitas']) : m);
    final conv = _n(tot['visitas']) == 0 ? 0 : (_n(tot['registros']) * 100 / _n(tot['visitas']));
    final ink = Theme.of(context).colorScheme.onSurface;

    Widget dato(String v, String t, [Color? c]) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: context.chip, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c ?? ink)),
              Text(t, style: TextStyle(fontSize: 12, color: context.muted)),
            ]),
          ),
        );
    Widget titulo(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 22, 0, 8),
        child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: ink)));
    Widget barras(List<Map<String, dynamic>> xs, String k) {
      final m = xs.fold<int>(1, (a, x) => _n(x['visitas']) > a ? _n(x['visitas']) : a);
      return Column(children: [
        for (final x in xs)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 130, child: Text('${x[k]}', overflow: TextOverflow.ellipsis)),
              Expanded(
                child: LayoutBuilder(
                  builder: (_, c) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                        height: 14,
                        width: c.maxWidth * _n(x['visitas']) / m,
                        decoration: BoxDecoration(color: const Color(0xFFE0452C), borderRadius: BorderRadius.circular(7))),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                  width: 70,
                  child: Text(
                      x.containsKey('con_cuenta') ? '${x['visitas']} · ${x['con_cuenta']}👤' : '${x['visitas']}',
                      textAlign: TextAlign.right)),
            ]),
          ),
      ]);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          dato('${hoy['visitas']}', 'Visitas hoy'),
          const SizedBox(width: 8),
          dato('${hoy['registros']}', 'Registros hoy', const Color(0xFF1F7A4D)),
          const SizedBox(width: 8),
          dato('${hoy['ahora']}', 'Últimos 30 min'),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          dato('${tot['visitas']}', 'Visitas $_dias días'),
          const SizedBox(width: 8),
          dato('${tot['registros']}', 'Registros $_dias días', const Color(0xFF1F7A4D)),
          const SizedBox(width: 8),
          dato(conv > 100 ? '—' : '${conv.toStringAsFixed(1)} %', 'Se registran'),
        ]),
        const SizedBox(height: 8),
        Text('Usuarios en total: ${tot['usuarios']}', style: TextStyle(color: context.muted)),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 7, label: Text('7 días')),
            ButtonSegment(value: 14, label: Text('14 días')),
            ButtonSegment(value: 30, label: Text('30 días')),
          ],
          selected: {_dias},
          onSelectionChanged: (s) {
            setState(() => (_dias = s.first, _d = null));
            _load();
          },
        ),
        titulo('Visitas por día'),
        SizedBox(
          height: 150,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final x in dias)
              Expanded(
                child: Tooltip(
                  message: '${x['dia']}: ${x['visitas']} visitas · ${x['registros']} registros',
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text('${x['visitas']}', style: TextStyle(fontSize: 9, color: context.muted)),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 110 * _n(x['visitas']) / maxV + 2,
                      decoration: BoxDecoration(color: const Color(0xFFF5B731), borderRadius: BorderRadius.circular(4)),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: _n(x['registros']) > 0 ? 6 : 0,
                      color: const Color(0xFF1F7A4D),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
        Text('Amarillo: visitas · Verde: hubo registros ese día', style: TextStyle(fontSize: 12, color: context.muted)),
        titulo('De dónde vienen'),
        if (orig.isEmpty) Text('Aún no hay visitas.', style: TextStyle(color: context.muted)) else barras(orig, 'origen'),
        Text('👤 = cuántos de esas visitas entraron con su cuenta', style: TextStyle(fontSize: 12, color: context.muted)),
        titulo('Por dónde entran'),
        barras(rutas, 'ruta'),
        titulo('Dispositivo'),
        barras(plat, 'plataforma'),
        titulo('Últimos registros'),
        for (final x in nuevos)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_add_alt_1_outlined),
            title: Text('@${x['username']} · ${x['city']}'),
            subtitle: Text(
                '${DateTime.tryParse('${x['created_at']}')?.toLocal().toString().substring(0, 16) ?? ''}${x['origen'] != null ? ' · vino de ${x['origen']}' : ''}'),
          ),
        const SizedBox(height: 20),
      ]),
    );
  }
}
