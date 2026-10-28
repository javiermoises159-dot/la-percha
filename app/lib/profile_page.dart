import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'extras.dart';
import 'features.dart';
import 'auth_sheet.dart';
import 'explore_page.dart';
import 'info_pages.dart';
import 'listing.dart';
import 'listing_detail.dart';
import 'mas.dart';
import 'admin_2fa.dart';
import 'orders_page.dart';
import 'seller_profile.dart';
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
            Text(
                'La necesitas para vender, comprar y escribir a otros usuarios.',
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
          if (a.isAdmin)
            _item(context, Icons.admin_panel_settings_outlined,
                'Panel de administración',
                page: const AdminGate()),
          _item(context, Icons.checkroom_outlined, 'Mi armario',
              page: const MyListingsPage()),
          _item(context, Icons.person_outline, 'Ver mi perfil público',
              page: SellerProfilePage(sellerId: a.id, username: a.username)),
          _item(context, Icons.favorite_border, 'Favoritos',
              page: const FavoritesPage()),
          _item(context, Icons.notifications_active_outlined, 'Mis alertas de búsqueda',
              page: const AlertasPage()),
          _item(context, Icons.account_balance_wallet_outlined, 'Saldo Pavito',
              page: const SaldoPage()),
          _item(context, Icons.receipt_long_outlined, 'Mis pedidos',
              page: const OrdersPage()),
          _item(context, Icons.rocket_launch_outlined,
              'Herramientas de promoción',
              page: const PromotePage()),
          _item(context, Icons.card_giftcard_outlined, 'Invita y gana',
              page: const InvitarPage()),
          const Divider(height: 1),
          _item(context, Icons.tune, 'Personalización',
              page: const PrefsPage()),
          _item(context, Icons.local_offer_outlined, 'Descuentos por lote',
              page: const LoteDiscountsPage()),
          _item(context, Icons.beach_access_outlined, 'Modo vacaciones',
              page: const VacationPage()),
          const Divider(height: 1),
          _item(context, Icons.help_outline, 'Guía de Pavito',
              page:
                  const InfoPage(title: 'Guía de Pavito', body: guideText)),
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

  static void _go(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

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
        _item(context, Icons.info_outline, 'Información sobre Pavito',
            page: const InfoPage(title: 'Sobre Pavito', body: aboutText)),
        _item(context, Icons.gavel_outlined, 'Notas legales',
            page: const InfoPage(title: 'Notas legales', body: legalText)),
        _item(context, Icons.privacy_tip_outlined, 'Privacidad',
            page: const InfoPage(
                title: 'Política de privacidad', body: privacyText)),
        _item(context, Icons.description_outlined, 'Términos y condiciones',
            page: const TermsPage()),
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

/// Mi armario: todo lo que vendes, con filtros por estado, destacar, ocultar y eliminar.
class MyListingsPage extends StatefulWidget {
  const MyListingsPage({super.key});

  @override
  State<MyListingsPage> createState() => _MyListingsPageState();
}

class _MyListingsPageState extends State<MyListingsPage> {
  List<Listing> _items = [];
  Map<String, String> _status = {};
  Map<String, (int, int)> _stats = {};
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
          .select('*, profiles!listings_seller_id_fkey(username)')
          .eq('seller_id', uid)
          .order('created_at', ascending: false);
      final stats = await misEstadisticas();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _items = [for (final r in rows) Listing.fromMap(r)];
        _status = {
          for (final r in rows) r['id'] as String: r['status'] as String
        };
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

  Future<void> _subir(Listing l) async {
    try {
      await _db.rpc('subir_anuncio', params: {'p_listing': l.id});
      listingsStore.load();
      _snack('Listo: tu anuncio vuelve a salir entre los primeros.');
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('No se pudo subir el anuncio.');
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

  String _filtro = 'todos';

  @override
  Widget build(BuildContext context) {
    const labels = {
      'active': 'En venta',
      'hidden': 'Oculto',
      'reserved': 'Reservado',
      'sold': 'Vendido',
    };
    const filtros = {
      'todos': 'Todo',
      'active': 'En venta',
      'reserved': 'Reservados',
      'sold': 'Vendidos',
      'hidden': 'Ocultos',
    };
    int cuenta(String st) => _status.values.where((v) => v == st).length;
    final enVenta = _items.where((l) => _status[l.id] == 'active');
    final valor = enVenta.fold<double>(0, (a, l) => a + l.price);
    final visibles = _filtro == 'todos'
        ? _items
        : _items.where((l) => (_status[l.id] ?? 'active') == _filtro).toList();
    Widget dato(String n, String t) => Expanded(
          child: Column(children: [
            Text(n, style: display(22, color: context.ink)),
            Text(t, style: TextStyle(color: context.muted, fontSize: 12.5)),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Mi armario')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? Center(
                      child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('Tu armario está vacío', style: display(20, color: context.ink)),
                        const SizedBox(height: 6),
                        Text('Publica lo que ya no usas y aparecerá aquí.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.muted)),
                      ]),
                    ))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: CustomScrollView(slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                            child: Row(children: [
                              dato('${cuenta('active')}', 'en venta'),
                              dato('${cuenta('sold')}', 'vendidos'),
                              dato('\$${valor.toStringAsFixed(0)}', 'valor en venta'),
                            ]),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 52,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              children: [
                                for (final f in filtros.entries)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(f.key == 'todos'
                                          ? '${f.value} (${_items.length})'
                                          : '${f.value} (${cuenta(f.key)})'),
                                      selected: _filtro == f.key,
                                      onSelected: (_) => setState(() => _filtro = f.key),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (visibles.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text('Nada por aquí.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: context.muted)),
                            ),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 220,
                                mainAxisSpacing: 18,
                                crossAxisSpacing: 10,
                                childAspectRatio: .62),
                            delegate: SliverChildBuilderDelegate(
                              childCount: visibles.length,
                              (_, i) {
                                final l = visibles[i];
                                final st = _status[l.id] ?? 'active';
                                return InkWell(
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                                      builder: (_) => ListingDetail(item: l))),
                                  child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Stack(fit: StackFit.expand, children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(10),
                                              child: Opacity(
                                                opacity: st == 'active' ? 1 : .55,
                                                child: ListingPhoto(item: l, iconSize: 32),
                                              ),
                                            ),
                                            if (st != 'active')
                                              Positioned(
                                                left: 8,
                                                top: 8,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                      color: st == 'sold' ? LP.ok : LP.ink,
                                                      borderRadius: BorderRadius.circular(20)),
                                                  child: Text(labels[st] ?? st,
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w700)),
                                                ),
                                              ),
                                            Positioned(
                                              right: 2,
                                              top: 2,
                                              child: PopupMenuButton<String>(
                                                icon: Container(
                                                  decoration: const BoxDecoration(
                                                      color: Colors.white, shape: BoxShape.circle),
                                                  padding: const EdgeInsets.all(4),
                                                  child: const Icon(Icons.more_horiz,
                                                      size: 18, color: LP.ink),
                                                ),
                                                onSelected: (v) {
                                                  if (v == 'hide') _setStatus(l, 'hidden');
                                                  if (v == 'show') _setStatus(l, 'active');
                                                  if (v == 'promo') {
                                                    Navigator.of(context).push(MaterialPageRoute<void>(
                                                        builder: (_) => const PromotePage()));
                                                  }
                                                  if (v == 'delete') _delete(l);
                                                  if (v == 'edit') {
                                                    Navigator.of(context)
                                                        .push(MaterialPageRoute<bool>(
                                                            builder: (_) => EditarAnuncioPage(item: l)))
                                                        .then((ok) {
                                                      if (ok == true) _load();
                                                    });
                                                  }
                                                  if (v == 'bump') _subir(l);
                                                },
                                                itemBuilder: (_) => [
                                                  if (st == 'active' || st == 'hidden')
                                                    const PopupMenuItem(
                                                        value: 'edit', child: Text('Editar')),
                                                  if (st == 'active')
                                                    const PopupMenuItem(
                                                        value: 'bump', child: Text('Subir arriba (gratis)')),
                                                  if (st == 'active')
                                                    const PopupMenuItem(
                                                        value: 'promo', child: Text('Destacar')),
                                                  if (st == 'active')
                                                    const PopupMenuItem(
                                                        value: 'hide', child: Text('Ocultar')),
                                                  if (st == 'hidden')
                                                    const PopupMenuItem(
                                                        value: 'show', child: Text('Volver a poner en venta')),
                                                  if (st == 'active' || st == 'hidden')
                                                    const PopupMenuItem(
                                                        value: 'delete', child: Text('Eliminar')),
                                                ],
                                              ),
                                            ),
                                          ]),
                                        ),
                                        const SizedBox(height: 6),
                                        Text('\$${l.price.toStringAsFixed(0)}',
                                            style: display(16, color: context.ink)),
                                        Text(l.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: context.muted)),
                                        if (_stats[l.id] != null)
                                          Text('${_stats[l.id]!.$1} vistas · ${_stats[l.id]!.$2} ♥',
                                              style: TextStyle(color: context.muted, fontSize: 12)),
                                      ]),
                                );
                              },
                            ),
                          ),
                        ),
                      ]),
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
        setState(() => _msg = e.code == '23505'
            ? 'Ese nombre de usuario ya está en uso.'
            : e.message);
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
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _msg = e.message);
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
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(_msg!)),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: _busy ? null : _save, child: const Text('Guardar')),
        const SizedBox(height: 10),
        OutlinedButton(
            onPressed: () async {
              await appState.signOut();
              if (context.mounted)
                Navigator.of(context).popUntil((r) => r.isFirst);
            },
            child: const Text('Cerrar sesión')),
        const SizedBox(height: 32),
        TextButton(
            onPressed: _deleteAccount,
            child: Text('Eliminar mi cuenta',
                style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? LP.clayD
                        : LP.clayText))),
      ]),
    );
  }
}
