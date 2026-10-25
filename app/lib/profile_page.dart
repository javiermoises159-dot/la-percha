import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'auth_sheet.dart';
import 'explore_page.dart';
import 'info_pages.dart';
import 'listing.dart';
import 'orders_page.dart';
import 'theme.dart';

/// Perfil: cabecera y menú completo.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final a = appState.account;
        final ink = Theme.of(context).colorScheme.onSurface;
        if (a == null) {
          return ListView(padding: const EdgeInsets.all(20), children: [
            Text('Crea tu cuenta', style: display(24, color: ink)),
            const SizedBox(height: 6),
            Text('La necesitas para vender, comprar y escribir a otros usuarios.',
                style: TextStyle(color: context.muted)),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: () => showAuthSheet(context, appState),
                child: const Text('Crear cuenta')),
            const SizedBox(height: 10),
            OutlinedButton(
                onPressed: () => showAuthSheet(context, appState, login: true),
                child: const Text('Ya tengo cuenta')),
            const SizedBox(height: 16),
            ..._legalItems(context),
          ]);
        }
        return ListView(children: [
          InkWell(
            onTap: () => _go(context, const MyListingsPage()),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: context.chip,
                  child: Text(a.username.substring(0, 1).toUpperCase(),
                      style: display(28, color: ink)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.username, style: display(22, color: ink)),
                      Text('Ver mis anuncios · ${a.city}',
                          style: TextStyle(color: context.muted)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ]),
            ),
          ),
          _item(context, Icons.favorite_border, 'Favoritos',
              page: const FavoritesPage()),
          _item(context, Icons.account_balance_wallet_outlined, 'Saldo',
              trailing: '\$0.00',
              page: const InfoPage(
                  title: 'Saldo',
                  body:
                      'Aquí verás el dinero de tus ventas, disponible para retirar a tu Pago Móvil o a Binance Pay.\n\nEl dinero llega a tu saldo cuando el comprador confirma que recibió la prenda.\n\nEsta función se activa con los pedidos protegidos.')),
          _item(context, Icons.receipt_long_outlined, 'Mis pedidos',
              page: const OrdersPage()),
          _item(context, Icons.rocket_launch_outlined, 'Herramientas de promoción',
              page: const InfoPage(
                  title: 'Herramientas de promoción',
                  body:
                      'Pronto podrás destacar tus anuncios para que más personas los vean.')),
          const Divider(height: 1),
          _item(context, Icons.tune, 'Personalización',
              page: const InfoPage(
                  title: 'Personalización',
                  body:
                      'Pronto podrás elegir tus categorías, tallas y ciudad favoritas para ver primero lo que te interesa.')),
          _item(context, Icons.local_offer_outlined, 'Descuentos por lote',
              trailing: 'No activos',
              page: const InfoPage(
                  title: 'Descuentos por lote',
                  body:
                      'Pronto podrás ofrecer un descuento a quien compre varias de tus prendas a la vez.')),
          _item(context, Icons.beach_access_outlined, 'Modo vacaciones',
              page: const InfoPage(
                  title: 'Modo vacaciones',
                  body:
                      'Pronto podrás pausar todos tus anuncios mientras estás fuera, y reactivarlos con un toque.')),
          const Divider(height: 1),
          _item(context, Icons.help_outline, 'Guía de La Percha',
              page: const InfoPage(title: 'Guía de La Percha', body: guideText)),
          _item(context, Icons.support_agent_outlined, 'Centro de ayuda',
              page: const InfoPage(title: 'Centro de ayuda', body: helpText)),
          const Divider(height: 1),
          _item(context, Icons.settings_outlined, 'Ajustes',
              page: const SettingsPage()),
          ..._legalItems(context),
          const SizedBox(height: 24),
        ]);
      },
    );
  }

  static void _go(BuildContext context, Widget page) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => page));

  static Widget _item(BuildContext context, IconData icon, String label,
      {String? trailing, required Widget page}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (trailing != null)
          Text(trailing, style: TextStyle(color: context.muted)),
        const Icon(Icons.chevron_right),
      ]),
      onTap: () => _go(context, page),
    );
  }

  static List<Widget> _legalItems(BuildContext context) => [
        _item(context, Icons.info_outline, 'Información sobre La Percha',
            page: const InfoPage(title: 'Sobre La Percha', body: aboutText)),
        _item(context, Icons.gavel_outlined, 'Notas legales',
            page: const InfoPage(title: 'Notas legales', body: legalText)),
        _item(context, Icons.privacy_tip_outlined, 'Privacidad',
            page: const InfoPage(title: 'Política de privacidad', body: privacyText)),
        _item(context, Icons.description_outlined, 'Términos y condiciones',
            page: const InfoPage(title: 'Términos y condiciones', body: termsText)),
        _item(context, Icons.cookie_outlined, 'Cookies',
            page: const InfoPage(title: 'Cookies', body: cookiesText)),
      ];
}

/// Favoritos del usuario.
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favoritos')),
      body: ListenableBuilder(
        listenable: Listenable.merge([appState, listingsStore]),
        builder: (context, _) => ListingGrid(
          items: listingsStore.all
              .where((l) => appState.favs.contains(l.id))
              .toList(),
          emptyText: 'Toca el corazón de una prenda para guardarla aquí.',
        ),
      ),
    );
  }
}

/// Mis anuncios: ocultar, mostrar y eliminar.
class MyListingsPage extends StatefulWidget {
  const MyListingsPage({super.key});

  @override
  State<MyListingsPage> createState() => _MyListingsPageState();
}

class _MyListingsPageState extends State<MyListingsPage> {
  List<Listing> _items = [];
  Map<String, String> _status = {};
  bool _loading = true;
  String? _error;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = appState.account?.id;
    if (uid == null) return;
    try {
      final rows = await _db
          .from('listings')
          .select('*, profiles(username)')
          .eq('seller_id', uid)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _items = [for (final r in rows) Listing.fromMap(r)];
        _status = {for (final r in rows) r['id'] as String: r['status'] as String};
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar tus anuncios.';
      });
    }
  }

  Future<void> _setStatus(Listing l, String status) async {
    try {
      await _db.from('listings').update({'status': status}).eq('id', l.id);
      await _load();
      listingsStore.load();
    } catch (_) {
      _snack('No se pudo cambiar el anuncio.');
    }
  }

  Future<void> _delete(Listing l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar este anuncio?'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.from('listings').delete().eq('id', l.id);
      await _load();
      listingsStore.load();
    } catch (_) {
      _snack('No se pudo eliminar. Puede que tenga un pedido en curso.');
    }
  }

  void _snack(String t) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = {
      'active': 'Visible',
      'hidden': 'Oculto',
      'reserved': 'Reservado',
      'sold': 'Vendido',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Mis anuncios')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? Center(
                      child: Text('Todavía no has publicado nada.',
                          style: TextStyle(color: context.muted)))
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final l = _items[i];
                        final st = _status[l.id] ?? 'active';
                        return ListTile(
                          leading: SizedBox(
                              width: 52,
                              height: 52,
                              child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: ListingPhoto(item: l, iconSize: 24))),
                          title: Text(l.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '\$${l.price.toStringAsFixed(0)} · ${labels[st] ?? st}'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'hide') _setStatus(l, 'hidden');
                              if (v == 'show') _setStatus(l, 'active');
                              if (v == 'delete') _delete(l);
                            },
                            itemBuilder: (_) => [
                              if (st == 'active')
                                const PopupMenuItem(
                                    value: 'hide', child: Text('Ocultar')),
                              if (st == 'hidden')
                                const PopupMenuItem(
                                    value: 'show', child: Text('Mostrar')),
                              const PopupMenuItem(
                                  value: 'delete', child: Text('Eliminar')),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}

/// Ajustes de la cuenta.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _user = TextEditingController(text: appState.account?.username);
  late final _city = TextEditingController(text: appState.account?.city);
  String? _msg;
  bool _busy = false;

  @override
  void dispose() {
    _user.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final u = _user.text.trim();
    final c = _city.text.trim();
    if (!isValidUsername(u)) {
      return setState(() => _msg =
          'El usuario debe tener 3 a 20 caracteres: letras, números, punto o guion bajo.');
    }
    if (c.length < 2) return setState(() => _msg = 'Indica tu ciudad.');
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'username': u, 'city': c}).eq('id', appState.account!.id);
      await appState.refresh();
      if (mounted) setState(() => _msg = 'Guardado.');
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => _msg =
            e.code == '23505' ? 'Ese nombre de usuario ya está en uso.' : e.message);
      }
    } catch (_) {
      if (mounted) setState(() => _msg = 'No se pudo guardar.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar tu cuenta?'),
        content: const Text(
            'Se borrarán tu perfil, tus anuncios, tus favoritos y tus mensajes. No se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.rpc('delete_my_account');
      await appState.signOut();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (_) {
      if (mounted) {
        setState(() => _msg =
            'No se pudo eliminar. Si tienes pedidos en curso, termínalos primero.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(
            controller: _user,
            maxLength: 20,
            decoration: const InputDecoration(labelText: 'Nombre de usuario')),
        const SizedBox(height: 8),
        TextField(
            controller: _city,
            decoration: const InputDecoration(labelText: 'Ciudad')),
        const SizedBox(height: 8),
        Text('Correo: ${appState.account?.email ?? ''}',
            style: TextStyle(color: context.muted)),
        if (_msg != null)
          Padding(
              padding: const EdgeInsets.only(top: 12), child: Text(_msg!)),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: _busy ? null : _save, child: const Text('Guardar')),
        const SizedBox(height: 10),
        OutlinedButton(
            onPressed: () async {
              await appState.signOut();
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            },
            child: const Text('Cerrar sesión')),
        const SizedBox(height: 32),
        TextButton(
            onPressed: _deleteAccount,
            child: Text('Eliminar mi cuenta',
                style: TextStyle(color: Theme.of(context).colorScheme.primary))),
      ]),
    );
  }
}
