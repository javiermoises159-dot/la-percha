import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'auth_sheet.dart';
import 'listing.dart';
import 'theme.dart';

/// Abre (o crea) la conversación con el vendedor de una prenda.
Future<void> openChatFor(BuildContext context, Listing item) async {
  final a = appState.account;
  if (a == null) {
    showAuthSheet(context, appState,
        message: 'Crea tu cuenta para escribirle al vendedor.');
    return;
  }
  if (item.sellerId == a.id) return;
  final db = Supabase.instance.client;
  try {
    Map<String, dynamic>? row = await db
        .from('threads')
        .select('id')
        .eq('listing_id', item.id)
        .eq('buyer_id', a.id)
        .maybeSingle();
    row ??= await db
        .from('threads')
        .insert({'listing_id': item.id, 'seller_id': item.sellerId})
        .select('id')
        .single();
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ChatPage(
            threadId: row!['id'] as String,
            title: '@${item.seller} · ${item.title}')));
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el chat. Intenta de nuevo.')));
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.threadId, required this.title});
  final String threadId;
  final String title;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  SupabaseClient get _db => Supabase.instance.client;
  List<Map<String, dynamic>> _msgs = [];
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _db
          .from('messages')
          .select()
          .eq('thread_id', widget.threadId)
          .order('created_at');
      if (!mounted) return;
      final grew = rows.length != _msgs.length;
      setState(() => _msgs = List<Map<String, dynamic>>.from(rows));
      if (grew) _toEnd();
    } catch (_) {}
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _db
          .from('messages')
          .insert({'thread_id': widget.threadId, 'text': text});
      // El resumen del chat lo actualiza el servidor.
      _ctrl.clear();
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo enviar el mensaje.')));
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final me = appState.account?.id;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, style: const TextStyle(fontSize: 16))),
      body: Column(children: [
        Expanded(
          child: _msgs.isEmpty
              ? Center(
                  child: Text('Escribe el primer mensaje.',
                      style: TextStyle(color: context.muted)))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _msgs.length,
                  itemBuilder: (_, i) {
                    final m = _msgs[i];
                    final mine = m['sender_id'] == me;
                    final aviso = m['aviso'] == true && !mine;
                    final bubble = Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: mine ? scheme.primary : scheme.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(m['text'] as String,
                            style: TextStyle(
                                color: mine ? scheme.onPrimary : scheme.onSurface)),
                      ),
                    );
                    if (!aviso) return bubble;
                    return Column(children: [bubble, const _AvisoEstafa()]);
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  maxLength: 1000,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'Escribe un mensaje'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Aviso bajo mensajes que piden pagar o hablar fuera de La Percha.
class _AvisoEstafa extends StatelessWidget {
  const _AvisoEstafa();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade700),
      ),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.shield_outlined, size: 18),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Cuidado: este mensaje menciona contactos o pagos fuera de La Percha. '
            'Paga siempre con "Comprar" dentro de la app: si pagas por fuera, '
            'tu dinero no está protegido.',
            style: TextStyle(fontSize: 12.5),
          ),
        ),
      ]),
    );
  }
}
