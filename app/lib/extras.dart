import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'auth_sheet.dart';
import 'config.dart';
import 'listing.dart';
import 'orders_page.dart';
import 'theme.dart';

SupabaseClient get _db => Supabase.instance.client;

String _usd(num v) => '\$${v.toStringAsFixed(2)}';

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

String _err(Object e, String fallback) =>
    e is PostgrestException ? e.message : fallback;

/// Ciudades donde se puede vender.
const ciudades = [
  'Caracas',
  'Valencia',
  'Maracaibo',
  'Barquisimeto',
  'Maracay',
  'Puerto La Cruz',
  'Mérida',
  'San Cristóbal',
  'Ciudad Guayana',
  'Isla de Margarita',
];

const estados = [
  'Nuevo con etiqueta',
  'Nuevo sin etiqueta',
  'Como nuevo',
  'Muy buen estado',
  'Buen estado',
  'Con detalles'
];

// ===================== Denunciar =====================

const _motivos = [
  'Parece una estafa',
  'Pide pagar o hablar fuera de Pavito',
  'Artículo falso o imitación',
  'Artículo prohibido o peligroso',
  'Fotos o textos ofensivos',
  'Otro',
];

/// Denunciar un anuncio (listingId) o a una persona (userId).
Future<void> showReportSheet(BuildContext context,
    {String? listingId, String? userId}) async {
  if (appState.account == null) {
    showAuthSheet(context, appState, message: 'Crea tu cuenta para denunciar.');
    return;
  }
  String? motivo;
  final extra = TextEditingController();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    listingId != null
                        ? 'Denunciar anuncio'
                        : 'Denunciar usuario',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                    'Lo revisamos en privado. La otra persona no sabrá quién fue.',
                    style: TextStyle(color: ctx.muted, fontSize: 13)),
                for (final m in _motivos)
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(m),
                    value: m,
                    groupValue: motivo,
                    onChanged: (v) => setState(() => motivo = v),
                  ),
                TextField(
                  controller: extra,
                  maxLength: 300,
                  decoration: const InputDecoration(
                      labelText: 'Cuéntanos más (opcional)'),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        motivo == null ? null : () => Navigator.pop(ctx, true),
                    child: const Text('Enviar denuncia'),
                  ),
                ),
              ]),
        ),
      ),
    ),
  );
  if (ok != true || motivo == null) return;
  final more = extra.text.trim();
  try {
    await _db.from('reports').insert({
      if (listingId != null) 'listing_id': listingId,
      if (listingId == null && userId != null) 'user_id': userId,
      'reason': more.isEmpty ? motivo! : '${motivo!}: $more',
    });
    if (context.mounted) _snack(context, 'Gracias. Revisaremos la denuncia.');
  } on PostgrestException catch (e) {
    if (!context.mounted) return;
    _snack(
        context,
        e.code == '23505'
            ? 'Ya habías denunciado esto. Lo estamos revisando.'
            : e.message);
  } catch (_) {
    if (context.mounted)
      _snack(context, 'No se pudo enviar. Revisa tu conexión.');
  }
}

// ===================== Preferencias =====================

class Prefs {
  const Prefs({this.city, this.cats = const []});
  final String? city;
  final List<String> cats;
}

class PrefsStore extends ChangeNotifier {
  Prefs prefs = const Prefs();

  Future<void> load() async {
    final me = appState.account?.id;
    if (me == null) return;
    try {
      final r = await _db
          .from('private_profiles')
          .select('prefs')
          .eq('id', me)
          .maybeSingle();
      final p = r?['prefs'];
      if (p is Map) {
        prefs = Prefs(
            city: p['city'] as String?,
            cats: List<String>.from((p['cats'] as List?) ?? const []));
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<String?> save(Prefs p) async {
    final me = appState.account?.id;
    if (me == null) return 'Inicia sesión.';
    try {
      await _db.from('private_profiles').upsert({
        'id': me,
        'prefs': {'city': p.city, 'cats': p.cats},
      });
      prefs = p;
      notifyListeners();
      return null;
    } catch (e) {
      return _err(e, 'No se pudo guardar.');
    }
  }

  /// Puntos para ordenar: primero lo de tu ciudad y tus categorías.
  int score(Listing l) =>
      (prefs.city != null && l.city == prefs.city ? 2 : 0) +
      (prefs.cats.contains(l.category) ? 1 : 0);
}

final prefsStore = PrefsStore();

class PrefsPage extends StatefulWidget {
  const PrefsPage({super.key});
  @override
  State<PrefsPage> createState() => _PrefsPageState();
}

class _PrefsPageState extends State<PrefsPage> {
  String? _city;
  late Set<String> _cats;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _city = prefsStore.prefs.city;
    _cats = {...prefsStore.prefs.cats};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personalización')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Te mostramos primero lo de tu ciudad y lo que te interesa.',
            style: TextStyle(color: context.muted)),
        const SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          initialValue: _city,
          decoration: const InputDecoration(labelText: 'Mi ciudad'),
          items: [
            const DropdownMenuItem<String?>(
                value: null, child: Text('Toda Venezuela')),
            for (final c in ciudades)
              DropdownMenuItem<String?>(value: c, child: Text(c)),
          ],
          onChanged: (v) => setState(() => _city = v),
        ),
        const SizedBox(height: 20),
        const Text('Me interesa',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in categories.skip(1))
            FilterChip(
              label: Text(c),
              selected: _cats.contains(c),
              onSelected: (on) =>
                  setState(() => on ? _cats.add(c) : _cats.remove(c)),
            ),
        ]),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final e = await prefsStore
                      .save(Prefs(city: _city, cats: _cats.toList()));
                  if (!context.mounted) return;
                  setState(() => _busy = false);
                  if (e != null) return _snack(context, e);
                  listingsStore.resort();
                  _snack(context, 'Guardado.');
                  Navigator.pop(context);
                },
          child: const Text('Guardar'),
        ),
      ]),
    );
  }
}

// ===================== Filtros de búsqueda =====================

class Filtros {
  const Filtros({this.min, this.max, this.city, this.condition, this.size, this.marca});
  final String? marca;
  final double? min;
  final double? max;
  final String? city;
  final String? condition;
  final String? size;

  bool get activos =>
      min != null ||
      max != null ||
      city != null ||
      condition != null ||
      size != null ||
      marca != null;
  int get cuantos =>
      [min, max, city, condition, size, marca].where((x) => x != null).length;

  bool ok(Listing l) =>
      (min == null || l.price >= min!) &&
      (max == null || l.price <= max!) &&
      (city == null || l.city == city) &&
      (condition == null || l.condition == condition) &&
      (size == null || l.size == size) &&
      (marca == null || (l.brand ?? '').toLowerCase().contains(marca!.toLowerCase()));
}

/// Abre la hoja de filtros y devuelve los nuevos (o null si se cancela).
Future<Filtros?> showFiltros(BuildContext context, Filtros actual) {
  final min = TextEditingController(text: actual.min?.toStringAsFixed(0) ?? '');
  final max = TextEditingController(text: actual.max?.toStringAsFixed(0) ?? '');
  String? city = actual.city, cond = actual.condition, size = actual.size;
  final marca = TextEditingController(text: actual.marca ?? '');
  final sizes = {
    for (final c in categories.skip(1)) ...sizesFor(c),
  }.where((s) => s != 'No aplica').toList();
  double? num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
  return showModalBottomSheet<Filtros>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Filtros',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: min,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Precio mín. \$'))),
                const SizedBox(width: 12),
                Expanded(
                    child: TextField(
                        controller: max,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Precio máx. \$'))),
              ]),
              const SizedBox(height: 12),
              TextField(
                  controller: marca,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Marca', hintText: 'Cualquiera')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: city,
                decoration: const InputDecoration(labelText: 'Ciudad'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Todas')),
                  for (final c in ciudades)
                    DropdownMenuItem<String?>(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => city = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: cond,
                decoration: const InputDecoration(labelText: 'Estado'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Cualquiera')),
                  for (final c in estados)
                    DropdownMenuItem<String?>(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => cond = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: size,
                decoration: const InputDecoration(labelText: 'Talla'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Cualquiera')),
                  for (final s in sizes)
                    DropdownMenuItem<String?>(value: s, child: Text(s)),
                ],
                onChanged: (v) => setState(() => size = v),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, const Filtros()),
                      child: const Text('Quitar filtros')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                      onPressed: () => Navigator.pop(
                          ctx,
                          Filtros(
                              min: num(min.text),
                              max: num(max.text),
                              city: city,
                              condition: cond,
                              size: size,
                              marca: marca.text.trim().isEmpty ? null : marca.text.trim())),
                      child: const Text('Ver resultados')),
                ),
              ]),
            ]),
          ),
        ),
      ),
    ),
  );
}

// ===================== Saldo =====================

class SaldoPage extends StatefulWidget {
  const SaldoPage({super.key});
  @override
  State<SaldoPage> createState() => _SaldoPageState();
}

class _SaldoPageState extends State<SaldoPage> {
  List<Map<String, dynamic>>? _rows;
  Map<String, dynamic> _saldo = const {};
  List<Map<String, dynamic>> _movs = [];
  List<Map<String, dynamic>> _retiros = [];
  String? _bancoSel;
  Map? _resumen;
  DateTime? _cambiado;
  bool _editando = false;
  final _cedula = TextEditingController();
  final _tel = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cedula.dispose();
    _tel.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final me = appState.account?.id;
    if (me == null) return;
    try {
      final r = await _db
          .from('orders')
          .select('id, price, status, paid_out_at, updated_at, listings(title)')
          .eq('seller_id', me)
          .neq('status', 'cancelado')
          .order('updated_at', ascending: false)
          .limit(200);
      // Los datos de cobro se guardan cifrados: aquí solo llega un resumen enmascarado.
      final p = await _db
          .from('private_profiles')
          .select('payout_resumen, payout_cambiado')
          .eq('id', me)
          .maybeSingle();
      _resumen = p?['payout_resumen'] as Map?;
      _cambiado = DateTime.tryParse('${p?['payout_cambiado'] ?? ''}');
      try {
        _saldo = Map<String, dynamic>.from((await _db.rpc('mi_saldo')) as Map);
        _movs = List<Map<String, dynamic>>.from(await _db
            .from('movimientos')
            .select('monto, tipo, creado, nota')
            .order('creado', ascending: false)
            .limit(40));
        _retiros = List<Map<String, dynamic>>.from(await _db
            .from('retiros')
            .select('monto, estado, creado, motivo')
            .order('creado', ascending: false)
            .limit(10));
      } catch (_) {}
      if (mounted) setState(() => _rows = List<Map<String, dynamic>>.from(r));
    } catch (_) {
      if (mounted) setState(() => _rows = []);
    }
  }

  Future<void> _savePayout() async {
    if (pagosCerrados(context)) return;
    if (appState.account == null) return;
    if (_bancoSel == null ||
        !RegExp(r'^[VEJPGvejpg]-?\s?[\d.]{5,12}$').hasMatch(_cedula.text.trim()) ||
        _tel.text.replaceAll(RegExp(r'\D'), '').length < 10) {
      return _snack(context,
          'Elige tu banco y escribe tu cédula (V-12345678) y el teléfono del Pago Móvil.');
    }
    setState(() => _busy = true);
    try {
      await _db.from('private_profiles').upsert({
        'id': appState.account?.id ?? '',
        'payout': {
          'banco': _bancoSel,
          'cedula': _cedula.text.trim(),
          'telefono': _tel.text.trim(),
        },
      });
      _cedula.clear();
      _tel.clear();
      _editando = false;
      await _load();
      if (mounted) {
        _snack(context,
            'Datos guardados y cifrados. Por seguridad, si los cambias, los retiros esperan 24 h.');
      }
    } catch (e) {
      if (mounted) _snack(context, _err(e, 'No se pudo guardar.'));
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _mini(String label, double v, String hint) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: context.chip, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: context.muted, fontSize: 12)),
          Text(_usd(v), style: display(18, color: context.ink)),
          Text(hint, style: TextStyle(color: context.muted, fontSize: 11)),
        ]),
      );

  static String _fecha(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    return '${t.day}/${t.month}/${t.year}';
  }

  Future<void> _retirar() async {
    if (pagosCerrados(context)) return;
    final disponible = ((_saldo['disponible'] as num?) ?? 0).toDouble();
    if (_resumen == null) {
      return _snack(context, 'Primero pon abajo tus datos de Pago Móvil para cobrar.');
    }
    final ctrl = TextEditingController(text: disponible.toStringAsFixed(2));
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Retirar saldo', style: display(22, color: c.ink)),
          const SizedBox(height: 6),
          Text('Disponible: ${_usd(disponible)}. Mínimo \$5.', style: TextStyle(color: c.muted)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Monto en dólares', prefixText: '\$ '),
          ),
          const SizedBox(height: 10),
          Text('Lo enviamos a ${_resumen!['banco']} · ${_resumen!['cedula']} · ${_resumen!['telefono']}, '
              'en bolívares a la tasa BCV del día, en 1 a 2 días hábiles.',
              style: TextStyle(color: c.muted, fontSize: 13, height: 1.35)),
          const SizedBox(height: 14),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Pedir retiro')),
        ]),
      ),
    );
    if (ok != true) return;
    final m = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
    if (m == null || m < 5) return _snack(context, 'El retiro mínimo es de \$5.');
    if (m > disponible) return _snack(context, 'No tienes ese saldo disponible.');
    setState(() => _busy = true);
    try {
      await _db.rpc('pedir_retiro', params: {'p_monto': m});
      if (mounted) _snack(context, 'Listo. Te enviamos ${_usd(m)} a tu Pago Móvil en 1 a 2 días hábiles.');
      await _load();
    } catch (e) {
      if (mounted) _snack(context, _err(e, 'No se pudo pedir el retiro.'));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final ink = Theme.of(context).colorScheme.onSurface;
    double n(String k) => ((_saldo[k] as num?) ?? 0).toDouble();
    final disponible = n('disponible');
    return Scaffold(
      appBar: AppBar(title: const Text('Saldo Pavito')),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: context.leafSoft, borderRadius: BorderRadius.circular(18)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Disponible', style: TextStyle(color: context.muted)),
                    Text(_usd(disponible),
                        style: display(36, color: context.leaf)
                            .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    if (bsText(disponible).isNotEmpty)
                      Text(bsText(disponible), style: TextStyle(color: context.muted, fontSize: 13)),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: (disponible >= 5 || !pagosAbiertos) ? _retirar : null,
                      icon: const Icon(Icons.account_balance_outlined),
                      label: Text(disponible >= 5 ? 'Retirar a mi Pago Móvil' : 'Retiras desde \$5'),
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _mini('Pendiente', n('pendiente'), 'Ventas en camino')),
                  const SizedBox(width: 8),
                  Expanded(child: _mini('En retiro', n('en_retiro'), 'Te lo enviamos en 1–2 días')),
                ]),
                const SizedBox(height: 10),
                Text(
                    'Cuando el comprador confirma que recibió (o pasan 7 días sin quejas), el dinero de tu venta entra aquí. '
                    'Úsalo para comprar en Pavito o retíralo a tu Pago Móvil desde \$5. '
                    'Si te devolvemos una compra cancelada, también llega a este saldo al instante.',
                    style: TextStyle(color: context.muted, fontSize: 13, height: 1.35)),
                const SizedBox(height: 20),
                Text('Dónde cobras', style: display(18, color: ink)),
                const SizedBox(height: 8),
                if (_resumen != null && !_editando) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: context.chip, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.lock_outline, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${_resumen!['banco']}',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text('${_resumen!['cedula']} · ${_resumen!['telefono']}',
                                  style: TextStyle(color: context.muted)),
                            ]),
                      ),
                    ]),
                  ),
                  if (_cambiado != null &&
                      DateTime.now().difference(_cambiado!).inHours < 24)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                          'Cambiaste estos datos hace poco: por seguridad, podrás retirar 24 h después del cambio.',
                          style: TextStyle(color: context.muted, fontSize: 13)),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                      onPressed: () => setState(() => _editando = true),
                      child: const Text('Cambiar datos de cobro')),
                ] else ...[
                  DropdownButtonFormField<String>(
                    initialValue: _bancoSel,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Banco'),
                    items: [
                      for (final b in bancosVe)
                        DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _bancoSel = v),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _cedula,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                          labelText: 'Cédula o RIF', hintText: 'V-12345678')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _tel,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                          labelText: 'Teléfono del Pago Móvil', hintText: '0414 1234567')),
                  const SizedBox(height: 6),
                  Text('Se guardan cifrados. Nadie de Pavito te los pedirá por mensaje.',
                      style: TextStyle(color: context.muted, fontSize: 12.5)),
                  const SizedBox(height: 10),
                  FilledButton(
                      onPressed: _busy ? null : _savePayout,
                      child: const Text('Guardar datos de cobro')),
                  if (_editando)
                    TextButton(
                        onPressed: () => setState(() => _editando = false),
                        child: const Text('Cancelar')),
                ],
                const SizedBox(height: 24),
                if (_retiros.isNotEmpty) ...[
                  Text('Retiros', style: display(18, color: ink)),
                  for (final r in _retiros)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                          r['estado'] == 'pagado'
                              ? Icons.check_circle_outline
                              : r['estado'] == 'rechazado'
                                  ? Icons.undo_rounded
                                  : Icons.schedule_rounded,
                          color: r['estado'] == 'pagado' ? context.leaf : context.muted),
                      title: Text(_usd(r['monto'] as num)),
                      subtitle: Text('${{'pendiente': 'En camino a tu Pago Móvil', 'pagado': 'Enviado', 'rechazado': 'Devuelto a tu saldo'}[r['estado']] ?? r['estado']}'
                          '${r['motivo'] != null && '${r['motivo']}'.isNotEmpty ? ' · ${r['motivo']}' : ''} · ${_fecha('${r['creado']}')}'),
                    ),
                  const SizedBox(height: 12),
                ],
                Text('Movimientos', style: display(18, color: ink)),
                if (_movs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('Aquí verás tus ventas cobradas, devoluciones, compras y retiros.',
                        style: TextStyle(color: context.muted)),
                  ),
                for (final m in _movs)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(const {
                          'venta': 'Venta completada',
                          'reembolso': 'Devolución de una compra',
                          'compra': 'Compra pagada con saldo',
                          'retiro': 'Retiro a tu Pago Móvil',
                          'retiro_devuelto': 'Retiro devuelto',
                          'ajuste': 'Ajuste de Pavito',
                        }[m['tipo']] ??
                        '${m['tipo']}'),
                    subtitle: Text(_fecha('${m['creado']}')),
                    trailing: Text(
                        '${(m['monto'] as num) > 0 ? '+' : '−'}${_usd((m['monto'] as num).abs())}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: (m['monto'] as num) > 0 ? context.leaf : ink)),
                  ),
              ]),
            ),
    );
  }
}

// ===================== Descuentos por lote (vendedor) =====================

class LoteDiscountsPage extends StatefulWidget {
  const LoteDiscountsPage({super.key});
  @override
  State<LoteDiscountsPage> createState() => _LoteDiscountsPageState();
}

class _LoteDiscountsPageState extends State<LoteDiscountsPage> {
  int? _d2, _d3, _d5;
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
          .select('lote_2, lote_3, lote_5')
          .eq('id', appState.account?.id ?? '')
          .single();
      if (!mounted) return;
      setState(() {
        _d2 = (r['lote_2'] as num).toInt();
        _d3 = (r['lote_3'] as num).toInt();
        _d5 = (r['lote_5'] as num).toInt();
      });
    } catch (_) {
      if (mounted) setState(() => _d2 = _d3 = _d5 = 0);
    }
  }

  Widget _row(String label, int value, ValueChanged<int> onChanged) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label)),
          DropdownButton<int>(
            value: value,
            items: [
              for (final p in const [0, 5, 10, 15, 20, 25, 30])
                DropdownMenuItem(
                    value: p, child: Text(p == 0 ? 'Sin descuento' : '$p %')),
            ],
            onChanged: (v) => onChanged(v ?? 0),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final ready = _d2 != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Descuentos por lote')),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(20), children: [
              Text(
                  'Anima a comprarte varias cosas a la vez: quien arma un lote paga un solo envío '
                  'y recibe tu descuento. Tú vendes más de una vez.',
                  style: TextStyle(color: context.muted)),
              const SizedBox(height: 16),
              _row('2 artículos', _d2!, (v) => setState(() => _d2 = v)),
              _row('3 o 4 artículos', _d3!, (v) => setState(() => _d3 = v)),
              _row('5 o más artículos', _d5!, (v) => setState(() => _d5 = v)),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await _db.from('profiles').update({
                            'lote_2': _d2,
                            'lote_3': _d3,
                            'lote_5': _d5
                          }).eq('id', appState.account?.id ?? '');
                          if (context.mounted)
                            _snack(context, 'Descuentos guardados.');
                        } catch (e) {
                          if (context.mounted)
                            _snack(context, _err(e, 'No se pudo guardar.'));
                        }
                        if (mounted) setState(() => _busy = false);
                      },
                child: const Text('Guardar'),
              ),
            ]),
    );
  }
}

// ===================== Comprar un lote (comprador) =====================

class BundlePage extends StatefulWidget {
  const BundlePage({super.key, required this.sellerId, required this.username});
  final String sellerId;
  final String username;
  @override
  State<BundlePage> createState() => _BundlePageState();
}

class _BundlePageState extends State<BundlePage> {
  List<Listing>? _items;
  Map<String, dynamic>? _disc;
  final Set<String> _sel = {};
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  String _metodo = metodosEntrega.first;
  String _ciudad = ciudadInicial();
  double? _envio;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _load() async {
    try {
      final l = await _db
          .from('listings')
          .select('*, profiles!listings_seller_id_fkey(username)')
          .eq('seller_id', widget.sellerId)
          .eq('status', 'active')
          .order('created_at', ascending: false);
      final d = await _db
          .from('profiles')
          .select('lote_2, lote_3, lote_5')
          .eq('id', widget.sellerId)
          .single();
      if (!mounted) return;
      setState(() {
        _items = [for (final r in l) Listing.fromMap(r)];
        _disc = d;
      });
    } catch (_) {
      if (mounted) setState(() => _items = []);
    }
  }

  int _pct(int n) {
    final d = _disc ?? const {};
    int v(String k) => (d[k] as num?)?.toInt() ?? 0;
    if (n >= 5 && v('lote_5') > 0) return v('lote_5');
    if (n >= 3 && v('lote_3') > 0) return v('lote_3');
    return n >= 2 ? v('lote_2') : 0;
  }

  bool get _todoGratis {
    final l = _items;
    return l != null && _sel.isNotEmpty && l.where((x) => _sel.contains(x.id)).every((x) => x.envioGratis);
  }

  Future<void> _recalc() async {
    if (_sel.length < 2) {
      if (mounted) setState(() => _envio = null);
      return;
    }
    final e = await envioEstimadoLote(_sel.toList(), _ciudad, _metodo);
    if (mounted) setState(() => _envio = e);
  }

  Future<void> _buy() async {
    if (pagosCerrados(context)) return;
    final name = _name.text.trim(),
        phone = _phone.text.trim(),
        address = _address.text.trim();
    if (_sel.length < 2)
      return setState(() => _error = 'Elige al menos 2 artículos.');
    if (name.length < 3 || phone.length < 7 || address.length < 6) {
      return setState(
          () => _error = 'Completa tu nombre, teléfono y dirección.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await _db.rpc('create_bundle', params: {
        'p_listings': _sel.toList(),
        'p_delivery': {
          'name': name,
          'phone': phone,
          'address': address,
          'ciudad': _ciudad,
          'metodo': _metodo
        },
      });
      listingsStore.load();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => OrderPage(orderId: id as String)));
    } catch (e) {
      setState(() => _error = _err(e, 'No se pudo crear el lote.'));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final chosen = [
      for (final l in items ?? const <Listing>[])
        if (_sel.contains(l.id)) l
    ];
    final subtotal = chosen.fold(0.0, (a, l) => a + l.price);
    final pct = _pct(chosen.length);
    final conDesc = chosen.fold(
        0.0, (a, l) => a + (l.price * (100 - pct) / 100 * 100).round() / 100);
    final fee = chosen.isEmpty
        ? 0.0
        : 0.25 +
            chosen.fold(
                0.0, (a, l) => a + ((l.price * (100 - pct) / 100) * 0.05));
    return Scaffold(
      appBar: AppBar(title: Text('Lote de @${widget.username}')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(
                  _disc == null ||
                          (_pct(2) == 0 && _pct(3) == 0 && _pct(5) == 0)
                      ? 'Elige varios artículos: pagas un solo envío.'
                      : 'Descuentos: 2 artículos ${_pct(2)} % · 3+ ${_pct(3)} % · 5+ ${_pct(5)} %. Un solo envío.',
                  style: TextStyle(color: context.muted)),
              const SizedBox(height: 8),
              for (final l in items)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _sel.contains(l.id),
                  onChanged: (v) {
                    setState(() => v == true ? _sel.add(l.id) : _sel.remove(l.id));
                    _recalc();
                  },
                  secondary: SizedBox(
                      width: 52,
                      height: 52,
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: ListingPhoto(item: l, iconSize: 22))),
                  title: Text(l.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${_usd(l.price)} · ${l.size}'),
                ),
              if (items.length < 2)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                      'Este vendedor tiene menos de 2 artículos a la venta.',
                      style: TextStyle(color: context.muted)),
                ),
              if (chosen.isNotEmpty) ...[
                const Divider(height: 24),
                _line('${chosen.length} artículos', _usd(subtotal)),
                if (pct > 0)
                  _line('Descuento del lote ($pct %)',
                      '- ${_usd(subtotal - conDesc)}'),
                _line('Envío (uno solo)', chosen.length < 2 ? '' : textoEnvio(_envio)),
                _line('Protección al comprador', _usd(fee)),
                _line('Total', _usd(conDesc + fee + (_envio ?? 0)), bold: true),
                if (bsText(conDesc + fee + (_envio ?? 0)).isNotEmpty)
                  _line('', bsText(conDesc + fee + (_envio ?? 0))),
              ],
              if (chosen.length >= 2) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _metodo,
                  decoration:
                      const InputDecoration(labelText: 'Cómo lo recibes'),
                  items: [
                    for (final m in metodosDisponibles())
                      DropdownMenuItem(value: m, child: Text(metodoSegunEnvio(m, _todoGratis)))
                  ],
                  onChanged: (v) {
                    setState(() => _metodo = v ?? _metodo);
                    _recalc();
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _ciudad,
                  decoration: const InputDecoration(labelText: 'Ciudad de entrega'),
                  items: [for (final c in ciudades) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) {
                    setState(() => _ciudad = v ?? _ciudad);
                    _recalc();
                  },
                ),
                if (notaEntrega(_metodo) != null) ...[
                  const SizedBox(height: 6),
                  Text(notaEntrega(_metodo)!,
                      style: TextStyle(color: context.muted, fontSize: 13)),
                ],
                const SizedBox(height: 10),
                TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        const InputDecoration(labelText: 'Nombre completo')),
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
                        labelText: 'Dirección u oficina de envío')),
                const SizedBox(height: 14),
                FilledButton(
                    onPressed: _busy ? null : _buy,
                    child: Text('Pedir lote de ${chosen.length}')),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
              ],
            ]),
    );
  }

  Widget _line(String a, String b, {bool bold = false}) {
    final s = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(a, style: s), Text(b, style: s)]),
    );
  }
}

/// Ir a comprar un lote, pidiendo cuenta si hace falta.
void openBundle(BuildContext context, String sellerId, String username) {
  if (appState.account == null) {
    showAuthSheet(context, appState, message: 'Crea tu cuenta para comprar.');
    return;
  }
  Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BundlePage(sellerId: sellerId, username: username)));
}

// ===================== Galería de fotos del anuncio =====================

class PhotoCarousel extends StatefulWidget {
  const PhotoCarousel({super.key, required this.item});
  final Listing item;
  @override
  State<PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<PhotoCarousel> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final photos = widget.item.photos;
    if (photos.length <= 1) {
      return AspectRatio(
          aspectRatio: 1, child: ListingPhoto(item: widget.item, iconSize: 96, grande: true));
    }
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(children: [
        PageView.builder(
          itemCount: photos.length,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (_, i) => Image.network(photos[i],
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) =>
                  ListingPhoto(item: widget.item, iconSize: 96, grande: true)),
        ),
        Positioned(
          bottom: 10,
          left: 0,
          right: 0,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < photos.length; i++)
              Container(
                width: i == _i ? 18 : 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                    color: i == _i ? Colors.white : Colors.white60,
                    borderRadius: BorderRadius.circular(4)),
              ),
          ]),
        ),
        Positioned(
          bottom: 10,
          right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(10)),
            child: Text('${_i + 1}/${photos.length}',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ),
      ]),
    );
  }
}


/// Bancos de Venezuela con Pago Móvil (código SUDEBAN y nombre).
const bancosVe = [
  '0102 - Banco de Venezuela',
  '0104 - Venezolano de Crédito',
  '0105 - Mercantil',
  '0108 - Provincial',
  '0114 - Bancaribe',
  '0115 - Exterior',
  '0128 - Caroní',
  '0134 - Banesco',
  '0137 - Sofitasa',
  '0138 - Plaza',
  '0146 - Bangente',
  '0151 - BFC Banco Fondo Común',
  '0156 - 100% Banco',
  '0157 - DelSur',
  '0163 - Banco del Tesoro',
  '0166 - Banco Agrícola',
  '0168 - Bancrecer',
  '0169 - R4 Banco Microfinanciero',
  '0171 - Banco Activo',
  '0172 - Bancamiga',
  '0173 - Banco Internacional de Desarrollo',
  '0174 - Banplus',
  '0175 - Banco Digital de los Trabajadores',
  '0177 - Banfanb',
  '0178 - N58 Banco Digital',
  '0191 - BNC Nacional de Crédito',
];
