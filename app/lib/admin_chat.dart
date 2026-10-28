import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'theme.dart';

/// Chat entre dos personas, solo para pedidos con problema o denuncias abiertas.
/// Cada vez que se abre queda registrado.
class AdminChatPage extends StatefulWidget {
  const AdminChatPage({super.key, this.orderId, this.reportId, required this.titulo});
  final String? orderId;
  final String? reportId;
  final String titulo;

  @override
  State<AdminChatPage> createState() => _AdminChatPageState();
}

class _AdminChatPageState extends State<AdminChatPage> {
  List<Map<String, dynamic>>? _m;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Supabase.instance.client
          .rpc('admin_chat', params: {'p_order': widget.orderId, 'p_report': widget.reportId});
      if (mounted) setState(() => _m = List<Map<String, dynamic>>.from(r as List));
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar el chat.');
    }
  }

  String _hora(Object? v) {
    final d = DateTime.tryParse('$v')?.toLocal();
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: const Color(0xFFFFF4D6),
          padding: const EdgeInsets.all(12),
          child: const Text('Solo para resolver este caso. Esta consulta queda registrada.',
              style: TextStyle(color: Color(0xFF6B4E00), fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : m == null
                  ? const Center(child: CircularProgressIndicator())
                  : m.isEmpty
                      ? Center(child: Text('Estas dos personas no se escribieron por el chat.', style: TextStyle(color: context.muted)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(14),
                          itemCount: m.length,
                          itemBuilder: (context, i) {
                            final x = m[i];
                            final a = x['es_a'] == true;
                            final prenda = '${x['prenda'] ?? ''}';
                            final cambia = prenda.isNotEmpty && (i == 0 || '${m[i - 1]['prenda']}' != prenda);
                            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              if (cambia)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text('Sobre: $prenda',
                                      textAlign: TextAlign.center, style: TextStyle(color: context.muted, fontSize: 12)),
                                ),
                              Align(
                                alignment: a ? Alignment.centerLeft : Alignment.centerRight,
                                child: Container(
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                                  decoration: BoxDecoration(
                                    color: a ? context.chip : const Color(0xFFE3F1E9),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('@${x['autor']} · ${_hora(x['enviado'])}',
                                        style: TextStyle(fontSize: 11, color: context.muted, fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 2),
                                    SelectableText('${x['texto']}', style: const TextStyle(color: Color(0xFF161412))),
                                  ]),
                                ),
                              ),
                            ]);
                          },
                        ),
        ),
      ]),
    );
  }
}

/// Registro de qué chats se consultaron, cuándo y por quién.
class AdminAccesosChatPage extends StatelessWidget {
  const AdminAccesosChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chats consultados')),
      body: FutureBuilder<dynamic>(
        future: Supabase.instance.client.rpc('admin_accesos_chat'),
        builder: (context, s) {
          if (!s.hasData) {
            return s.hasError
                ? const Center(child: Text('No se pudo cargar.'))
                : const Center(child: CircularProgressIndicator());
          }
          final r = List<Map<String, dynamic>>.from(s.data as List);
          if (r.isEmpty) return Center(child: Text('Nadie ha consultado chats.', style: TextStyle(color: context.muted)));
          return ListView(children: [
            for (final x in r)
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: Text('${x['motivo']}: ${x['entre']}'),
                subtitle: Text('Por @${x['admin']} · ${DateTime.tryParse('${x['creado']}')?.toLocal().toString().substring(0, 16) ?? ''}'),
              ),
          ]);
        },
      ),
    );
  }
}
