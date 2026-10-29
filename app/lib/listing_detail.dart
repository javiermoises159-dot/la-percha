import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'features.dart';
import 'fundador.dart';
import 'mas.dart';
import 'chat_page.dart';
import 'explore_page.dart';
import 'extras.dart';
import 'listing.dart';
import 'orders_page.dart';
import 'perfil_foto.dart';
import 'seller_profile.dart';
import 'theme.dart';

/// Comisión de protección al comprador (la paga quien compra).
double buyerFee(double price) => 0.25 + price * 0.05;

final _vistosEnSesion = <String>{};

class ListingDetail extends StatelessWidget {
  const ListingDetail({super.key, required this.item});
  final Listing item;

  String _hace(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return 'hace ${d.inMinutes.clamp(1, 59)} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    if (d.inDays < 30) return 'hace ${d.inDays} d';
    return 'hace ${d.inDays ~/ 30} meses';
  }

  @override
  Widget build(BuildContext context) {
    final fee = buyerFee(item.price);
    if (_vistosEnSesion.add(item.id)) registrarVista(item);
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final fav = appState.favs.contains(item.id);
        final mine = appState.account?.id == item.sellerId;
        final meta = [
          if (item.brand != null) item.brand!,
          if (item.size != 'No aplica') 'Talla ${item.size}',
          item.condition,
          item.city,
          _hace(item.createdAt),
        ].where((x) => x.isNotEmpty).join(' · ');
        Widget circle(IconData icon, VoidCallback onTap, {Color? color}) =>
            Padding(
              padding: const EdgeInsets.all(6),
              child: Material(
                color: Colors.white.withValues(alpha: 0.94),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                  child: Padding(
                      padding: const EdgeInsets.all(9),
                      child: Icon(icon, size: 20, color: color ?? LP.ink)),
                ),
              ),
            );
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            automaticallyImplyLeading: false,
            leading: circle(Icons.arrow_back_rounded,
                () => Navigator.of(context).maybePop()),
            actions: [
              circle(Icons.ios_share_rounded, () => compartirAnuncio(context, item)),
              circle(fav ? Icons.favorite : Icons.favorite_border,
                  () => toggleFavorite(context, item.id),
                  color: fav ? Theme.of(context).colorScheme.primary : null),
              if (!mine)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.94),
                    shape: const CircleBorder(),
                    child: PopupMenuButton<String>(
                      tooltip: 'Más opciones',
                      icon: const Icon(Icons.more_horiz_rounded, color: LP.ink),
                      onSelected: (v) {
                        if (v == 'denunciar')
                          showReportSheet(context, listingId: item.id);
                        if (v == 'lote')
                          openBundle(context, item.sellerId, item.seller);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'lote',
                            child: Text('Comprar varios de este vendedor')),
                        PopupMenuItem(
                            value: 'denunciar',
                            child: Text('Denunciar anuncio')),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: mine
              ? null
              : Container(
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(top: BorderSide(color: context.line))),
                  padding: EdgeInsets.fromLTRB(
                      16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 688),
                      child: Row(children: [
                        SizedBox(
                          width: 50,
                          child: Tooltip(
                           message: 'Escribir al vendedor',
                           child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.zero),
                            onPressed: () => openChatFor(context, item),
                            child: const Icon(Icons.chat_bubble_outline_rounded,
                                size: 20, semanticLabel: 'Escribir al vendedor'),
                          ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                              onPressed: () => makeOfferFor(context, item),
                              child: const Text('Ofertar')),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: FilledButton(
                              onPressed: () => startCheckout(context, item),
                              child: const Text('Comprar')),
                        ),
                      ]),
                    ),
                  ),
                ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(padding: EdgeInsets.zero, children: [
                PhotoCarousel(item: item),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                                '\$${item.price.toStringAsFixed(item.price % 1 == 0 ? 0 : 2)}',
                                style: display(32, color: context.ink)),
                            const SizedBox(width: 8),
                            if (bsText(item.price).isNotEmpty)
                              Text(bsText(item.price),
                                  style: TextStyle(
                                      color: context.muted, fontSize: 14)),
                          ]),
                      const SizedBox(height: 8),
                      Text(item.title,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              height: 1.3)),
                      const SizedBox(height: 4),
                      Text(meta,
                          style: TextStyle(color: context.muted, fontSize: 14)),
                      if (item.fotoIa) ...[
                        const SizedBox(height: 6),
                        Text(
                            'Portada de catálogo: desliza para ver las fotos reales.',
                            style:
                                TextStyle(color: context.muted, fontSize: 13)),
                      ],
                      const SizedBox(height: 12),
                      Row(children: [
                        Icon(Icons.verified_user_outlined,
                            size: 18, color: context.leaf),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                              'Compra protegida: pagas \$${(item.price + fee).toStringAsFixed(2)} y el dinero queda guardado hasta que lo recibes',
                              style: TextStyle(
                                  color: context.leaf,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ),
                      ]),
                      const SizedBox(height: 14),
                      Divider(color: context.line),
                      const SizedBox(height: 8),
                      EnvioInfo(item: item),
                      const SizedBox(height: 8),
                      Divider(color: context.line),
                      InkWell(
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => SellerProfilePage(
                                    sellerId: item.sellerId,
                                    username: item.seller))),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(children: [
                            AvatarDe(userId: item.sellerId, nombre: item.seller, radius: 21),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.seller,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15)),
                                    Wrap(children: [
                                      if (item.envioGratis)
                                        const Padding(
                                          padding: EdgeInsets.only(right: 6),
                                          child: Chip(
                                              visualDensity: VisualDensity.compact,
                                              label: Text('Envío gratis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                                        ),
                                      FundadorChip(sellerId: item.sellerId),
                                      VerificadoChip(userId: item.sellerId),
                                    ]),
                                    Text('Ver perfil y valoraciones',
                                        style: TextStyle(
                                            color: context.muted,
                                            fontSize: 12)),
                                  ]),
                            ),
                            if (!mine)
                              FollowButtonCompact(sellerId: item.sellerId),
                          ]),
                        ),
                      ),
                      Divider(color: context.line),
                      const SizedBox(height: 12),
                      const Text('Descripción',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(
                          item.description.isEmpty
                              ? 'Sin descripción.'
                              : item.description,
                          style: const TextStyle(height: 1.45)),
                      const SizedBox(height: 16),
                      Text(
                          'Protección al comprador: \$${fee.toStringAsFixed(2)}. Quien vende no paga comisión.',
                          style: TextStyle(color: context.muted, fontSize: 12)),
                      if (mine) ...[
                        const SizedBox(height: 16),
                        Text('Este es tu anuncio.',
                            style: TextStyle(color: context.muted)),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Editar anuncio'),
                          onPressed: () => Navigator.of(context).pushReplacement(
                              MaterialPageRoute<void>(builder: (_) => EditarAnuncioPage(item: item))),
                        ),
                      ],
                    ],
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}


/// Enlace para compartir: muestra foto, título y precio en WhatsApp y abre el anuncio.
String get _sitio => kIsWeb ? Uri.base.origin : 'https://pavito.app';
String enlaceAnuncio(Listing l) => '$_sitio/a/${l.id}';
String enlaceTienda(String usuario) => '$_sitio/t/$usuario';

/// Comparte la tienda de un vendedor: en WhatsApp sale con foto y cuántas prendas tiene.
void compartirTienda(BuildContext context, String usuario, {bool mia = false}) {
  final url = enlaceTienda(usuario);
  final texto = mia
      ? 'Mira mi tienda en Pavito 👗 Todo lo que vendo, con compra protegida: $url'
      : 'Mira la tienda de @$usuario en Pavito. Compra protegida: $url';
  _hojaCompartir(context, mia ? 'Compartir mi tienda' : 'Compartir tienda', texto, url,
      nota: mia ? 'Ponlo en la bio de tu Instagram y en tus estados de WhatsApp.' : null);
}

void compartirAnuncio(BuildContext context, Listing l) {
  final url = enlaceAnuncio(l);
  final precio = l.price % 1 == 0 ? l.price.toStringAsFixed(0) : l.price.toStringAsFixed(2);
  final texto = 'Mira esto en Pavito: ${l.title} a \$$precio. Compra protegida: tu pago queda guardado hasta que lo recibes. $url';
  _hojaCompartir(context, 'Compartir', texto, url);
}

void _hojaCompartir(BuildContext context, String titulo, String texto, String url, {String? nota}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(titulo, style: display(22, color: ctx.ink)),
          if (nota != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(nota, style: TextStyle(color: ctx.muted))),
          if (nota != null) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(url, style: const TextStyle(fontWeight: FontWeight.w700))),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1FA855)),
            icon: const Icon(Icons.chat_rounded),
            label: const Text('Enviar por WhatsApp'),
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(texto)}'),
                  mode: LaunchMode.externalApplication);
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.link_rounded),
            label: const Text('Copiar enlace'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enlace copiado. Pégalo en tus estados o grupos.')));
            },
          ),
        ]),
      ),
    ),
  );
}
