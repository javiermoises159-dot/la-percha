import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'theme.dart';

const _claveOpinion = 'pv_opinion_v1';

/// Pide la opinión una sola vez, cuando la persona ya completó una compra o una venta.
Future<void> pedirOpinionSiToca(BuildContext context, AppState state) async {
  final cuenta = state.account;
  if (cuenta == null) return;
  try {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('$_claveOpinion-${cuenta.id}') == true) return;
    final r = await Supabase.instance.client.rpc('quiere_opinar');
    if (r != true) return;
    if (!context.mounted) return;
    // Pase lo que pase (enviar o cerrar), no se vuelve a mostrar.
    await p.setBool('$_claveOpinion-${cuenta.id}', true);
    if (!context.mounted) return;
    await showDialog<void>(
        context: context, builder: (_) => _AvisoOpinion(usuario: cuenta.username));
  } catch (_) {}
}

class _AvisoOpinion extends StatelessWidget {
  const _AvisoOpinion({required this.usuario});
  final String usuario;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close)),
          ),
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(color: LP.yellow, shape: BoxShape.circle),
            child: const Icon(Icons.star_rounded, size: 48, color: Colors.white),
          ),
          const SizedBox(height: 18),
          Text('Tu opinión nos ayuda a mejorar',
              textAlign: TextAlign.center, style: display(22, color: cs.onSurface)),
          const SizedBox(height: 10),
          Text(
              'Hola $usuario, ¿nos regalas 1 minuto para contarnos cómo te fue en Pavito?\n\nUn abrazo,\nel equipo de Pavito',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.4, color: cs.onSurface.withOpacity(0.7))),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const _FormOpinion(),
                );
              },
              child: const Text('Dar mi opinión'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _FormOpinion extends StatefulWidget {
  const _FormOpinion();
  @override
  State<_FormOpinion> createState() => _FormOpinionState();
}

class _FormOpinionState extends State<_FormOpinion> {
  int _est = 0;
  final _txt = TextEditingController();
  bool _busy = false;
  bool _listo = false;

  @override
  void dispose() {
    _txt.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_est == 0 || _busy) return;
    setState(() => _busy = true);
    try {
      final c = _txt.text.trim();
      await Supabase.instance.client.from('opiniones').insert({
        'estrellas': _est,
        if (c.isNotEmpty) 'comentario': c.length > 600 ? c.substring(0, 600) : c,
      });
      if (mounted) setState(() => _listo = true);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo enviar. Inténtalo de nuevo.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: _listo
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.favorite, size: 44, color: LP.clay),
              const SizedBox(height: 12),
              Text('¡Gracias!', style: display(24, color: cs.onSurface)),
              const SizedBox(height: 8),
              const Text('Leemos cada opinión para mejorar Pavito.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 18),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cerrar'))),
            ])
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Text('¿Cómo te fue en Pavito?',
                  style: display(22, color: cs.onSurface)),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: () => setState(() => _est = i),
                    iconSize: 40,
                    icon: Icon(i <= _est ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: LP.yellow),
                  ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: _txt,
                maxLines: 4,
                maxLength: 600,
                decoration: const InputDecoration(
                    hintText: 'Cuéntanos qué te gustó y qué mejorarías (opcional)'),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_est == 0 || _busy) ? null : _enviar,
                  child: Text(_busy ? 'Enviando…' : 'Enviar opinión'),
                ),
              ),
            ]),
    );
  }
}

/// Panel de admin: opiniones recibidas.
class OpinionesAdminPage extends StatefulWidget {
  const OpinionesAdminPage({super.key});
  @override
  State<OpinionesAdminPage> createState() => _OpinionesAdminPageState();
}

class _OpinionesAdminPageState extends State<OpinionesAdminPage> {
  List<Map<String, dynamic>>? _ops;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Supabase.instance.client
          .from('opiniones')
          .select('estrellas, comentario, created_at, user_id')
          .order('created_at', ascending: false)
          .limit(200);
      if (mounted) setState(() => _ops = List<Map<String, dynamic>>.from(r as List));
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudieron cargar las opiniones.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    final ops = _ops;
    if (ops == null) return const Center(child: CircularProgressIndicator());
    if (ops.isEmpty) return const Center(child: Text('Todavía no hay opiniones.'));
    final prom = ops.fold<num>(0, (a, o) => a + (o['estrellas'] as num)) / ops.length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('${prom.toStringAsFixed(1)} ★ de promedio · ${ops.length} opiniones',
          style: display(20, color: Theme.of(context).colorScheme.onSurface)),
      const SizedBox(height: 12),
      for (final o in ops)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: context.soft, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${'★' * (o['estrellas'] as int)}${'☆' * (5 - (o['estrellas'] as int))}',
                style: const TextStyle(fontSize: 20, color: LP.yellow)),
            if ((o['comentario'] as String?)?.isNotEmpty ?? false) ...[
              const SizedBox(height: 6),
              Text(o['comentario'] as String),
            ],
            const SizedBox(height: 6),
            Text(((o['created_at'] as String?) ?? '').split('T').first,
                style: TextStyle(fontSize: 12, color: context.muted)),
          ]),
        ),
    ]);
  }
}
