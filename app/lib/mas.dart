import 'config.dart';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'extras.dart';
import 'listing.dart';
import 'push.dart';
import 'theme.dart';

/// Funciones para estar a la altura de Vinted: editar anuncio, alertas de búsqueda,
/// vistas, vendedor verificado e invitaciones.
SupabaseClient get _db => Supabase.instance.client;

void _snack(BuildContext context, String t) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

String _error(Object e, String porDefecto) => e is PostgrestException ? e.message : porDefecto;

// ===================== Vistas =====================

String? _dispositivo;

/// Identificador al azar de este dispositivo (solo para contar vistas sin cuenta).
Future<String> dispositivoId() async {
  if (_dispositivo != null) return _dispositivo!;
  try {
    final p = await SharedPreferences.getInstance();
    var id = p.getString('pv_dispositivo');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
      await p.setString('pv_dispositivo', id);
    }
    return _dispositivo = id;
  } catch (_) {
    return _dispositivo = 'tmp${DateTime.now().millisecondsSinceEpoch}';
  }
}

Future<void> registrarVista(Listing l) async {
  if (l.sellerId == appState.account?.id) return;
  try {
    await _db.rpc('registrar_vista', params: {'p_listing': l.id, 'p_dispositivo': await dispositivoId()});
  } catch (_) {}
}

/// Vistas y favoritos de los anuncios propios: {id: (vistas, favoritos)}.
Future<Map<String, (int, int)>> misEstadisticas() async {
  try {
    final r = await _db.rpc('mis_estadisticas') as List;
    return {
      for (final x in r)
        '${x['listing_id']}': (((x['vistas'] as num?) ?? 0).toInt(), ((x['favoritos'] as num?) ?? 0).toInt())
    };
  } catch (_) {
    return {};
  }
}

// ===================== Vendedor verificado =====================

final _verificados = <String, Future<bool>>{};

Future<bool> esVerificado(String userId) => _verificados.putIfAbsent(userId, () async {
      try {
        final r = await _db.from('profiles').select('verificado').eq('id', userId).maybeSingle();
        return r?['verificado'] == true;
      } catch (_) {
        return false;
      }
    });

class VerificadoChip extends StatelessWidget {
  const VerificadoChip({super.key, required this.userId, this.grande = false});
  final String userId;
  final bool grande;
  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: esVerificado(userId),
        builder: (context, s) {
          if (s.data != true) return const SizedBox.shrink();
          return Tooltip(
            message: 'Pavito verificó la identidad de este vendedor',
            child: Container(
              margin: const EdgeInsets.only(top: 3, left: 4),
              padding: EdgeInsets.symmetric(horizontal: grande ? 10 : 7, vertical: grande ? 4 : 2),
              decoration: BoxDecoration(color: const Color(0xFFE3F0FF), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.verified_rounded, size: grande ? 16 : 13, color: const Color(0xFF1565C0)),
                const SizedBox(width: 4),
                Text('Verificado',
                    style: TextStyle(color: const Color(0xFF0D47A1), fontWeight: FontWeight.w800, fontSize: grande ? 13 : 11.5)),
              ]),
            ),
          );
        },
      );
}

// ===================== Editar anuncio =====================

class EditarAnuncioPage extends StatefulWidget {
  const EditarAnuncioPage({super.key, required this.item});
  final Listing item;
  @override
  State<EditarAnuncioPage> createState() => _EditarAnuncioPageState();
}

class _EditarAnuncioPageState extends State<EditarAnuncioPage> {
  late final _titulo = TextEditingController(text: widget.item.title);
  late final _desc = TextEditingController(text: widget.item.description);
  late final _precio = TextEditingController(
      text: widget.item.price % 1 == 0 ? widget.item.price.toStringAsFixed(0) : widget.item.price.toStringAsFixed(2));
  late final _marca = TextEditingController(text: widget.item.brand ?? '');
  late String _categoria = widget.item.category;
  late String _talla = widget.item.size;
  late String _estado = widget.item.condition;
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _titulo.dispose();
    _desc.dispose();
    _precio.dispose();
    _marca.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final precio = double.tryParse(_precio.text.trim().replaceAll(',', '.'));
    if (_titulo.text.trim().length < 3) return setState(() => _err = 'Escribe un título.');
    if (precio == null || precio < 1 || precio > 5000) {
      return setState(() => _err = 'Escribe un precio en dólares entre 1 y 5000.');
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    final e = await listingsStore.editar(widget.item.id, {
      'title': _titulo.text.trim(),
      'description': _desc.text.trim(),
      'price': precio,
      'category': _categoria,
      'size': _talla,
      'condition': _estado,
      'brand': _marca.text.trim().isEmpty ? null : _marca.text.trim(),
    });
    if (!mounted) return;
    if (e != null) {
      return setState(() {
        _busy = false;
        _err = e;
      });
    }
    _snack(context, precio < widget.item.price
        ? 'Guardado. Avisamos de la rebaja a quienes lo tienen en favoritos.'
        : 'Cambios guardados.');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cats = categories.where((c) => c != 'Todo').toList();
    final tallas = sizesFor(_categoria);
    if (!tallas.contains(_talla)) _talla = tallas.first;
    Widget drop(String label, String value, List<String> items, ValueChanged<String> onChanged) =>
        DropdownButtonFormField<String>(
          initialValue: items.contains(value) ? value : items.first,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [for (final i in items) DropdownMenuItem(value: i, child: Text(i))],
          onChanged: (v) {
            if (v != null) setState(() => onChanged(v));
          },
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Editar anuncio')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Las fotos no se cambian aquí. Si quieres otras fotos, publícalo de nuevo.',
            style: TextStyle(color: context.muted, fontSize: 13)),
        const SizedBox(height: 12),
        TextField(controller: _titulo, maxLength: 60, decoration: const InputDecoration(labelText: 'Título')),
        TextField(
            controller: _marca,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Marca (opcional)')),
        TextField(
            controller: _desc, maxLines: 3, maxLength: 300, decoration: const InputDecoration(labelText: 'Descripción')),
        const SizedBox(height: 8),
        drop('Categoría', _categoria, cats, (v) => _categoria = v),
        const SizedBox(height: 12),
        drop('Talla', _talla, tallas, (v) => _talla = v),
        const SizedBox(height: 12),
        drop('Estado', _estado, estados, (v) => _estado = v),
        const SizedBox(height: 12),
        TextField(
            controller: _precio,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Precio en dólares', prefixText: '\$ ')),
        if (_err != null) ...[
          const SizedBox(height: 10),
          Text(_err!, style: const TextStyle(color: Color(0xFFB3261E))),
        ],
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _guardar, child: Text(_busy ? 'Guardando…' : 'Guardar cambios')),
      ]),
    );
  }
}

// ===================== Alertas de búsqueda =====================

/// Crea una alerta con lo que se está buscando ahora.
Future<void> crearAlerta(BuildContext context, {String q = '', String? categoria, String? talla, String? ciudad, double? precioMax}) async {
  if (appState.account == null) return _snack(context, 'Inicia sesión para crear alertas.');
  try {
    await _db.from('alertas_busqueda').insert({
      'q': q.trim(),
      'categoria': categoria,
      'talla': talla,
      'ciudad': ciudad,
      'precio_max': precioMax,
    });
    if (context.mounted) {
      _snack(context, 'Listo. Te avisamos cuando publiquen algo que coincida.');
    }
  } catch (e) {
    if (context.mounted) _snack(context, _error(e, 'No se pudo crear la alerta.'));
  }
}

class AlertasPage extends StatefulWidget {
  const AlertasPage({super.key});
  @override
  State<AlertasPage> createState() => _AlertasPageState();
}

class _AlertasPageState extends State<AlertasPage> {
  List<Map<String, dynamic>>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _db.from('alertas_busqueda').select().order('creado', ascending: false);
      if (mounted) setState(() => _rows = List<Map<String, dynamic>>.from(r));
    } catch (_) {
      if (mounted) setState(() => _rows = []);
    }
  }

  Future<void> _nueva() async {
    final q = TextEditingController();
    String? cat;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Nueva alerta', style: display(22, color: c.ink)),
            const SizedBox(height: 10),
            TextField(controller: q, decoration: const InputDecoration(labelText: 'Qué buscas', hintText: 'Zara, botas de cuero, PS4…')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: cat,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
                for (final x in categories.where((c) => c != 'Todo')) DropdownMenuItem<String?>(value: x, child: Text(x)),
              ],
              onChanged: (v) => set(() => cat = v),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Crear alerta')),
          ]),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await crearAlerta(context, q: q.text, categoria: cat);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: const Text('Mis alertas')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _nueva, icon: const Icon(Icons.add_alert_outlined), label: const Text('Nueva alerta')),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                        'Crea una alerta y te avisamos apenas alguien publique lo que buscas.\n\n'
                        'También puedes crearla desde el buscador.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.muted, height: 1.4)),
                  ),
                )
              : ListView(children: [
                  for (final a in rows)
                    ListTile(
                      leading: const Icon(Icons.notifications_active_outlined),
                      title: Text('${a['q']}'.isEmpty ? (a['categoria'] ?? 'Todo') as String : '"${a['q']}"'),
                      subtitle: Text([
                        if (a['categoria'] != null && '${a['q']}'.isNotEmpty) a['categoria'],
                        if (a['talla'] != null) 'Talla ${a['talla']}',
                        if (a['ciudad'] != null) a['ciudad'],
                        if (a['precio_max'] != null) 'Hasta \$${a['precio_max']}',
                      ].join(' · ')),
                      trailing: IconButton(
                        tooltip: 'Borrar alerta',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          try {
                            await _db.from('alertas_busqueda').delete().eq('id', a['id'] as String);
                          } catch (_) {}
                          _load();
                        },
                      ),
                    ),
                ]),
    );
  }
}

// ===================== Invita a un amigo =====================

/// Si se abrió con ?ref=usuario, se guarda para asignarlo al crear la cuenta.
Future<void> guardarInvitacion() async {
  final ref = Uri.base.queryParameters['ref'];
  if (ref == null || !RegExp(r'^[A-Za-z0-9_.]{3,20}$').hasMatch(ref)) return;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString('pv_ref', ref);
  } catch (_) {}
}

/// Tras crear el perfil: registra quién invitó (una sola vez).
Future<void> aplicarInvitacion() async {
  try {
    final p = await SharedPreferences.getInstance();
    final ref = p.getString('pv_ref');
    if (ref == null) return;
    await _db.rpc('usar_invitacion', params: {'p_username': ref});
    await p.remove('pv_ref');
  } catch (_) {}
}

class InvitarPage extends StatefulWidget {
  const InvitarPage({super.key});
  @override
  State<InvitarPage> createState() => _InvitarPageState();
}

class _InvitarPageState extends State<InvitarPage> {
  int? _n;

  @override
  void initState() {
    super.initState();
    _db.rpc('mis_invitados').then((v) {
      if (mounted) setState(() => _n = (v as num?)?.toInt() ?? 0);
    }).catchError((_) {
      if (mounted) setState(() => _n = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final u = appState.account?.username ?? '';
    final link = 'https://pavito.pages.dev/?ref=$u';
    final texto = 'Te invito a Pavito: compra y vende ropa y cosas que ya no usas en toda Venezuela, '
        '${modoDirecto ? 'sin comisiones' : 'con pago protegido'}. Vender es gratis. $link';
    return Scaffold(
      appBar: AppBar(title: const Text('Invita y gana')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Icon(Icons.card_giftcard_rounded, size: 56, color: LP.clay),
        const SizedBox(height: 10),
        Text('Invita a tus amigos a vender', textAlign: TextAlign.center, style: display(22, color: context.ink)),
        const SizedBox(height: 8),
        Text('Por cada amigo que se registre con tu enlace y publique su primera prenda, ganas 1 destacado gratis de 7 días.',
            textAlign: TextAlign.center, style: TextStyle(color: context.muted, height: 1.4)),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: context.chip, borderRadius: BorderRadius.circular(12)),
          child: SelectableText(link, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1FA855)),
          icon: const Icon(Icons.chat_rounded),
          label: const Text('Enviar por WhatsApp'),
          onPressed: () => launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(texto)}'),
              mode: LaunchMode.externalApplication),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.link_rounded),
          label: const Text('Copiar enlace'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: link));
            _snack(context, 'Enlace copiado.');
          },
        ),
        const SizedBox(height: 20),
        if (_n != null)
          Text(_n == 1 ? '1 persona se registró con tu enlace.' : '$_n personas se registraron con tu enlace.',
              textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
      ]),
    );
  }
}

// ===================== Notificaciones al teléfono =====================

/// Cartel para activar las notificaciones (solo aparece si hace falta).
class PushBanner extends StatefulWidget {
  const PushBanner({super.key});
  @override
  State<PushBanner> createState() => _PushBannerState();
}

class _PushBannerState extends State<PushBanner> {
  String? _estado;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    pushEstado().then((e) {
      if (mounted) setState(() => _estado = e);
    });
  }

  Future<void> _activar() async {
    setState(() => _busy = true);
    final e = await activarPush();
    if (!mounted) return;
    if (e != null) _snack(context, e);
    final st = await pushEstado();
    if (mounted) {
      setState(() {
        _busy = false;
        _estado = st;
      });
      if (e == null) _snack(context, 'Listo. Te avisaremos al teléfono de ventas, mensajes y pagos.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _estado;
    if (e == null || e == 'activo' || e == 'no_soportado' || appState.account == null) return const SizedBox.shrink();
    final ios = e == 'instalar_ios';
    final bloqueado = e == 'bloqueado';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.chip, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        const Icon(Icons.notifications_active_outlined, color: LP.clay),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Notificaciones al teléfono', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(
                ios
                    ? 'En iPhone: toca Compartir → "Agregar a inicio", abre Pavito desde ese ícono y actívalas aquí.'
                    : bloqueado
                        ? 'Las bloqueaste en este navegador. Actívalas en los ajustes del sitio para Pavito.'
                        : 'Entérate al instante cuando te compren, te escriban o te paguen.',
                style: TextStyle(color: context.muted, fontSize: 13, height: 1.3)),
          ]),
        ),
        if (!ios && !bloqueado) ...[
          const SizedBox(width: 8),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: _busy ? null : _activar,
              child: const Text('Activar')),
        ],
      ]),
    );
  }
}
