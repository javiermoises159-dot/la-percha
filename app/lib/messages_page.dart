import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'auth_sheet.dart';
import 'chat_page.dart';
import 'theme.dart';

/// Mensajes y notificaciones.
class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        if (appState.account == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.mail_outline, size: 48, color: context.muted),
                const SizedBox(height: 12),
                Text('Tus mensajes', style: display(22,
                    color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 6),
                Text('Crea tu cuenta para hablar con compradores y vendedores.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.muted)),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: () => showAuthSheet(context, appState),
                    child: const Text('Crear cuenta')),
              ]),
            ),
          );
        }
        return DefaultTabController(
          length: 2,
          child: Column(children: [
            const TabBar(tabs: [Tab(text: 'Mensajes'), Tab(text: 'Notificaciones')]),
            Expanded(
              child: TabBarView(children: [
                const _ThreadList(),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                        'Aquí verás avisos de tus ventas, compras y ofertas. Llega con los pedidos.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.muted)),
                  ),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

class _ThreadList extends StatefulWidget {
  const _ThreadList();

  @override
  State<_ThreadList> createState() => _ThreadListState();
}

class _ThreadListState extends State<_ThreadList> {
  List<Map<String, dynamic>> _rows = [];
  Map<String, String> _names = {};
  Map<String, String> _titles = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = Supabase.instance.client;
    try {
      final rows = await db
          .from('threads')
          .select()
          .order('last_at', ascending: false, nullsFirst: false)
          .limit(50);
      final me = appState.account?.id;
      final userIds = <String>{
        for (final r in rows)
          (r['buyer_id'] == me ? r['seller_id'] : r['buyer_id']) as String
      }.toList();
      final listingIds = <String>{for (final r in rows) r['listing_id'] as String}.toList();
      final names = <String, String>{};
      final titles = <String, String>{};
      if (userIds.isNotEmpty) {
        final p = await db.from('profiles').select('id,username').inFilter('id', userIds);
        for (final r in p) {
          names[r['id'] as String] = r['username'] as String;
        }
      }
      if (listingIds.isNotEmpty) {
        final l = await db.from('listings').select('id,title').inFilter('id', listingIds);
        for (final r in l) {
          titles[r['id'] as String] = r['title'] as String;
        }
      }
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(rows);
        _names = names;
        _titles = titles;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar los mensajes.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, style: TextStyle(color: context.muted)));
    }
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
              'Todavía no tienes conversaciones. Abre una prenda y toca "Escribir al vendedor".',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.muted)),
        ),
      );
    }
    final me = appState.account?.id;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final r = _rows[i];
          final other = (r['buyer_id'] == me ? r['seller_id'] : r['buyer_id']) as String;
          final name = _names[other] ?? 'Usuario';
          final title = _titles[r['listing_id']] ?? 'Prenda';
          return ListTile(
            leading: CircleAvatar(
                backgroundColor: context.chip,
                child: Text(name.isEmpty ? '?' : name[0].toUpperCase())),
            title: Text('@$name · $title', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text((r['last_message'] as String?) ?? 'Sin mensajes',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ChatPage(
                      threadId: r['id'] as String, title: '@$name · $title')));
              _load();
            },
          );
        },
      ),
    );
  }
}
