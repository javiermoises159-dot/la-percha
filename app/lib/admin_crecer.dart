import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';
import 'theme.dart';

final _db = Supabase.instance.client;

String _fecha(Object? v) {
  final d = DateTime.tryParse('$v')?.toLocal();
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
}

String _error(Object e) => e is PostgrestException ? e.message : 'No se pudo completar.';

/// ===== Activar usuarios: quién no ha publicado y cómo contactarlo =====
class ActivarUsuariosPage extends StatefulWidget {
  const ActivarUsuariosPage({super.key});
  @override
  State<ActivarUsuariosPage> createState() => _ActivarUsuariosPageState();
}

class _ActivarUsuariosPageState extends State<ActivarUsuariosPage> {
  bool _soloSin = true;
  List<Map<String, dynamic>>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _rows = null);
    try {
      final r = await _db.rpc('admin_usuarios_activacion', params: {'p_solo_sin_prendas': _soloSin});
      if (mounted) setState(() => _rows = List<Map<String, dynamic>>.from(r as List));
    } catch (e) {
      if (mounted) {
        setState(() => _rows = []);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo cargar la lista: ${_error(e)}')));
      }
    }
  }

  String? _wa(String? tel) {
    var d = (tel ?? '').replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return null;
    if (d.startsWith('0')) d = '58${d.substring(1)}';
    if (d.length == 10 && d.startsWith('4')) d = '58$d';
    return d;
  }

  Future<void> _avisoA(Map<String, dynamic> u) async {
    final c = TextEditingController(
        text: '¡Hola @${u['username']}! Sube tus primeras 3 prendas a Pavito y llévate un destacado gratis 🦜');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Aviso a @${u['username']}'),
        content: TextField(controller: c, maxLength: 160, maxLines: 4),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _db.rpc('admin_enviar_aviso', params: {'p_texto': c.text, 'p_grupo': 'usuario', 'p_usuario': u['id']});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aviso enviado')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_error(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          Expanded(
            child: Text(rows == null ? '' : '${rows.length} ${_soloSin ? 'sin prendas publicadas' : 'usuarios'}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          FilterChip(
            label: Text('Solo sin prendas', style: TextStyle(color: _soloSin ? Colors.white : null)),
            checkmarkColor: Colors.white,
            selected: _soloSin,
            onSelected: (v) {
              _soloSin = v;
              _load();
            },
          ),
        ]),
      ),
      Expanded(
        child: rows == null
            ? const Center(child: CircularProgressIndicator())
            : rows.isEmpty
                ? Center(child: Text('Nadie por aquí.', style: TextStyle(color: context.muted)))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final u = rows[i];
                        final wa = _wa(u['telefono'] as String?);
                        final correo = (u['correo'] as String?) ?? '';
                        final texto = Uri.encodeComponent(
                            '¡Hola! Soy Javier de Pavito 🦜 Vi que te registraste. ¿Te ayudo a subir tus primeras prendas? Si subes 3 te regalo un destacado.');
                        return ListTile(
                          title: Text('@${u['username']}${u['fundador'] != null ? ' · Fundador #${u['fundador']}' : ''}'),
                          subtitle: Text(
                              '${u['city']} · se registró ${_fecha(u['creado'])} · ${u['prendas']} prendas'
                              '${u['ultima_visita'] != null ? '\nÚltima visita ${_fecha(u['ultima_visita'])}' : ''}'),
                          isThreeLine: u['ultima_visita'] != null,
                          trailing: Wrap(spacing: 0, children: [
                            if (wa != null)
                              IconButton(
                                tooltip: 'WhatsApp',
                                icon: const Icon(Icons.chat_rounded, color: Color(0xFF1FA855)),
                                onPressed: () => launchUrl(Uri.parse('https://wa.me/$wa?text=$texto'),
                                    mode: LaunchMode.externalApplication),
                              ),
                            if (correo.isNotEmpty)
                              IconButton(
                                tooltip: 'Correo',
                                icon: const Icon(Icons.mail_outline),
                                onPressed: () => launchUrl(Uri.parse(
                                    'mailto:$correo?subject=${Uri.encodeComponent('Tu clóset en Pavito')}&body=$texto')),
                              ),
                            IconButton(
                              tooltip: 'Aviso en la app',
                              icon: const Icon(Icons.campaign_outlined),
                              onPressed: () => _avisoA(u),
                            ),
                          ]),
                        );
                      },
                    ),
                  ),
      ),
    ]);
  }
}

/// ===== Mensajes a un grupo de usuarios =====
class MensajesAdminPage extends StatefulWidget {
  const MensajesAdminPage({super.key});
  @override
  State<MensajesAdminPage> createState() => _MensajesAdminPageState();
}

class _MensajesAdminPageState extends State<MensajesAdminPage> {
  static const _grupos = {
    'todos': 'Todos los usuarios',
    'sin_prendas': 'Quienes no han publicado',
    'con_prendas': 'Quienes ya venden',
    'fundadores': 'Fundadores',
    'ciudad': 'Una ciudad',
  };
  final _texto = TextEditingController();
  final _ciudad = TextEditingController();
  String _grupo = 'sin_prendas';
  int? _cuantos;
  bool _busy = false;
  List<Map<String, dynamic>> _hist = [];

  @override
  void initState() {
    super.initState();
    _contar();
    _historial();
  }

  Future<void> _contar() async {
    if (_grupo == 'ciudad' && _ciudad.text.trim().isEmpty) {
      setState(() => _cuantos = null);
      return;
    }
    try {
      final n = await _db.rpc('admin_enviar_aviso',
          params: {'p_texto': '', 'p_grupo': _grupo, 'p_ciudad': _ciudad.text, 'p_simular': true});
      if (mounted) setState(() => _cuantos = (n as num).toInt());
    } catch (_) {
      if (mounted) setState(() => _cuantos = null);
    }
  }

  Future<void> _historial() async {
    try {
      final r = await _db.rpc('admin_comunicados');
      if (mounted) setState(() => _hist = List<Map<String, dynamic>>.from(r as List));
    } catch (_) {}
  }

  Future<void> _enviar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Enviar mensaje?'),
        content: Text('Le llegará a ${_cuantos ?? '?'} personas como aviso en la app y notificación:\n\n“${_texto.text.trim()}”'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final n = await _db.rpc('admin_enviar_aviso',
          params: {'p_texto': _texto.text, 'p_grupo': _grupo, 'p_ciudad': _ciudad.text});
      _texto.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enviado a $n personas')));
      _historial();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_error(e))));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final largo = _texto.text.trim().length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Llega como aviso (campanita) y, a quien tenga las notificaciones activadas, también al móvil.',
          style: TextStyle(height: 1.4)),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        value: _grupo,
        decoration: const InputDecoration(labelText: 'Para quién'),
        items: [for (final e in _grupos.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) {
          setState(() => _grupo = v ?? 'todos');
          _contar();
        },
      ),
      if (_grupo == 'ciudad') ...[
        const SizedBox(height: 10),
        TextField(
            controller: _ciudad,
            decoration: const InputDecoration(labelText: 'Ciudad (ej. Caracas)'),
            onChanged: (_) => _contar()),
      ],
      const SizedBox(height: 6),
      Text(_cuantos == null ? '' : 'Le llegará a $_cuantos ${_cuantos == 1 ? 'persona' : 'personas'}',
          style: TextStyle(color: context.muted)),
      const SizedBox(height: 10),
      TextField(
        controller: _texto,
        maxLength: 160,
        maxLines: 4,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
            labelText: 'Mensaje', hintText: 'Ej.: ¡Sube 3 prendas esta semana y llévate un destacado gratis! 🦜'),
      ),
      FilledButton.icon(
        onPressed: _busy || largo < 5 || (_cuantos ?? 0) == 0 ? null : _enviar,
        icon: const Icon(Icons.send_rounded),
        label: const Text('Enviar'),
      ),
      const SizedBox(height: 6),
      Text('Máximo 5 mensajes a grupos por día.', style: TextStyle(fontSize: 12, color: context.muted)),
      const SizedBox(height: 22),
      const Text('Enviados', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      if (_hist.isEmpty) Text('Todavía ninguno.', style: TextStyle(color: context.muted)),
      for (final h in _hist)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.campaign_outlined),
          title: Text('${h['texto']}'),
          subtitle: Text(
              '${_grupos[h['grupo']] ?? (h['grupo'] == 'usuario' ? 'Una persona' : h['grupo'])}${h['ciudad'] != null ? ' (${h['ciudad']})' : ''} · ${h['enviados']} personas · ${_fecha(h['creado'])}'),
        ),
    ]);
  }
}

/// ===== Pagos y cobro: abrir los pagos y los datos donde pagan los compradores =====
class PagosConfigPage extends StatefulWidget {
  const PagosConfigPage({super.key});
  @override
  State<PagosConfigPage> createState() => _PagosConfigPageState();
}

class _PagosConfigPageState extends State<PagosConfigPage> {
  static const _campos = [
    ('pm_banco', 'Pago Móvil · Banco', 'Ej.: 0102 - Banco de Venezuela'),
    ('pm_cedula', 'Pago Móvil · Cédula o RIF', 'Ej.: V-12345678'),
    ('pm_telefono', 'Pago Móvil · Teléfono', 'Ej.: 0414-1234567'),
    ('binance_id', 'Binance Pay · Pay ID', 'Binance → Pay → Recibir'),
    ('binance_nombre', 'Binance Pay · Nombre', ''),
    ('zinli_correo', 'Zinli · Correo', ''),
    ('zinli_nombre', 'Zinli · Nombre', ''),
  ];
  final _c = {for (final x in _campos) x.$1: TextEditingController()};
  bool _abiertos = false;
  bool _cargando = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ConfigApp.cargar();
    for (final x in _campos) {
      _c[x.$1]!.text = ConfigApp.valor(x.$1);
    }
    if (mounted) setState(() => (_abiertos = pagosAbiertos, _cargando = false));
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _guardar() async {
    setState(() => _busy = true);
    try {
      for (final x in _campos) {
        final v = _c[x.$1]!.text.trim();
        if (v != ConfigApp.valor(x.$1)) await _db.rpc('admin_set_config', params: {'p_clave': x.$1, 'p_valor': v});
      }
      await _load();
      _snack('Datos de cobro guardados');
    } catch (e) {
      _snack(_error(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _cambiarPagos(bool abrir) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(abrir ? '¿Abrir los pagos?' : '¿Cerrar los pagos?'),
        content: Text(abrir
            ? 'Desde ese momento cualquiera puede comprar y pagar a los datos de cobro de abajo. Revisa que sean los REALES.'
            : 'Nadie podrá hacer pedidos nuevos. Los pedidos en curso siguen igual.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(abrir ? 'Abrir pagos' : 'Cerrar pagos')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _db.rpc('admin_set_config', params: {'p_clave': 'pagos_abiertos', 'p_valor': abrir ? 'true' : 'false'});
      await _load();
      _snack(abrir ? 'Pagos abiertos 🎉' : 'Pagos cerrados');
    } catch (e) {
      _snack(_error(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _abiertos ? const Color(0xFFE3F1E9) : const Color(0xFFFFF4D6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_abiertos ? 'Pagos ABIERTOS' : 'Pagos cerrados (fase de prueba)',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF161412))),
              const SizedBox(height: 4),
              Text(
                  _abiertos
                      ? 'La gente puede comprar y pagar.'
                      : 'La app muestra "Los pagos abren muy pronto" y el servidor rechaza los pedidos.',
                  style: const TextStyle(color: Color(0xFF3B3632))),
            ]),
          ),
          Switch(value: _abiertos, onChanged: _busy ? null : _cambiarPagos),
        ]),
      ),
      const SizedBox(height: 20),
      const Text('Datos de cobro de Pavito', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 4),
      Text('Aquí pagan los compradores. Deja vacío el método que no uses y no se mostrará.',
          style: TextStyle(color: context.muted)),
      const SizedBox(height: 10),
      for (final x in _campos)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _c[x.$1],
            maxLength: 80,
            decoration: InputDecoration(labelText: x.$2, hintText: x.$3.isEmpty ? null : x.$3, counterText: ''),
          ),
        ),
      FilledButton(onPressed: _busy ? null : _guardar, child: const Text('Guardar datos de cobro')),
      const SizedBox(height: 10),
      Text('Para abrir los pagos hace falta al menos un método completo. Cada cambio queda registrado.',
          style: TextStyle(fontSize: 12, color: context.muted)),
    ]);
  }
}
