import 'config.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'features.dart';
import 'auth_sheet.dart';
import 'listing.dart';
import 'theme.dart';

/// Abre (o crea) la conversación con el vendedor de una prenda.
Future<void> openChatFor(BuildContext context, Listing item, {String? borrador}) async {
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
            title: '@${item.seller} · ${item.title}',
            borrador: borrador)));
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo abrir el chat. Intenta de nuevo.')));
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.threadId, required this.title, this.borrador});
  final String threadId;
  final String title;
  final String? borrador; // texto que aparece ya escrito (sin enviar)

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
    if (widget.borrador != null) _ctrl.text = widget.borrador!;
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
          .order('created_at', ascending: true);
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
      appBar: AppBar(
          title: Text(widget.title, style: const TextStyle(fontSize: 16))),
      body: Column(children: [
        OfferBar(threadId: widget.threadId, onChanged: _load),
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
                                color: mine
                                    ? scheme.onPrimary
                                    : scheme.onSurface)),
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
                  buildCounter: (_,
                          {required currentLength,
                          required isFocused,
                          maxLength}) =>
                      null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration:
                      const InputDecoration(hintText: 'Escribe un mensaje'),
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

/// Aviso bajo mensajes que piden pagar o hablar fuera de Pavito.
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
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.shield_outlined, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            modoDirecto
                ? 'Cuidado: nunca pagues por adelantado a alguien sin reseñas. Si puedes, '
                  'entrega en persona en un lugar público, o paga al recibir.'
                : 'Cuidado: este mensaje menciona contactos o pagos fuera de Pavito. '
                  'Paga siempre con "Comprar" dentro de la app: si pagas por fuera, '
                  'tu dinero no está protegido.',
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
      ]),
    );
  }
}


/// "Comprar" en modo directo: consejos de seguridad y luego el chat con el
/// vendedor, con el mensaje ya escrito. Pavito no toca el dinero.
void comprarDirecto(BuildContext context, Listing item) {
  if (appState.account == null) {
    showAuthSheet(context, appState, message: 'Crea tu cuenta para escribirle al vendedor.');
    return;
  }
  final precio = item.price % 1 == 0 ? item.price.toStringAsFixed(0) : item.price.toStringAsFixed(2);
  Widget punto(BuildContext c, IconData i, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, size: 22, color: c.leaf),
          const SizedBox(width: 12),
          Expanded(child: Text(t, style: TextStyle(color: c.ink, height: 1.35))),
        ]),
      );
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Compra directa al vendedor', style: display(22, color: ctx.ink)),
          const SizedBox(height: 6),
          Text('Acuerdan el pago y la entrega por el chat. Pavito no cobra comisión y no recibe tu dinero.',
              style: TextStyle(color: ctx.muted, height: 1.4)),
          const SizedBox(height: 18),
          punto(ctx, Icons.handshake_outlined, 'Lo más seguro: entrega en persona, en un lugar público, y pagas al ver la prenda.'),
          punto(ctx, Icons.local_shipping_outlined, 'Si es por envío, pide fotos reales y la guía, y paga solo a quien tenga buenas reseñas.'),
          punto(ctx, Icons.block_outlined, 'Nunca mandes códigos, claves ni pagues "para apartar" a alguien que no conoces.'),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openChatFor(context, item,
                  borrador: '¡Hola! Me interesa "${item.title}" por \$$precio. ¿Sigue disponible? ¿Cómo hacemos el pago y la entrega?');
            },
            child: const Text('Escribirle al vendedor'),
          ),
        ]),
      ),
    ),
  );
}
