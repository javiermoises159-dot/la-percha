import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'theme.dart';

SupabaseClient get _db => Supabase.instance.client;

// ===================== Foto de perfil / logo de tienda =====================

/// Círculo con la foto de la persona o, si no tiene, su inicial.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.url, required this.nombre, this.radius = 24});
  final String? url;
  final String nombre;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final inicial = nombre.isEmpty ? '?' : nombre.substring(0, 1).toUpperCase();
    final u = url;
    return CircleAvatar(
      radius: radius,
      backgroundColor: context.chip,
      backgroundImage: (u != null && u.isNotEmpty) ? NetworkImage(u) : null,
      child: (u != null && u.isNotEmpty)
          ? null
          : Text(inicial, style: display(radius * 0.9, color: Theme.of(context).colorScheme.onSurface)),
    );
  }
}

final _cacheAvatar = <String, Future<String?>>{};

/// Foto de cualquier usuario (se pide una sola vez por sesión).
class AvatarDe extends StatelessWidget {
  const AvatarDe({super.key, required this.userId, required this.nombre, this.radius = 24});
  final String userId;
  final String nombre;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final f = _cacheAvatar.putIfAbsent(userId, () async {
      try {
        final r = await _db.from('profiles').select('avatar_url').eq('id', userId).maybeSingle();
        return r?['avatar_url'] as String?;
      } catch (_) {
        return null;
      }
    });
    return FutureBuilder<String?>(
      future: f,
      builder: (_, s) => Avatar(url: s.data, nombre: nombre, radius: radius),
    );
  }
}

/// Elige una foto de la galería y la deja como foto de perfil.
Future<void> cambiarFotoPerfil(BuildContext context) async {
  final cuenta = appState.account;
  if (cuenta == null) return;
  final msg = ScaffoldMessenger.of(context);
  try {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, imageQuality: 85);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    final path = '${cuenta.id}/avatar.jpg';
    await _db.storage.from('avatares').uploadBinary(path, bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true, cacheControl: '3600'));
    final url = '${_db.storage.from('avatares').getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
    await _db.from('profiles').update({'avatar_url': url}).eq('id', cuenta.id);
    _cacheAvatar.remove(cuenta.id);
    await appState.refresh();
    msg.showSnackBar(const SnackBar(content: Text('¡Listo! Tu foto quedó actualizada.')));
  } catch (_) {
    msg.showSnackBar(const SnackBar(content: Text('No se pudo subir la foto. Inténtalo de nuevo.')));
  }
}

// ===================== Distintivos =====================

class _Dist {
  const _Dist(this.clave, this.icono, this.titulo, this.como);
  final String clave;
  final IconData icono;
  final String titulo;
  final String como;
}

const _distintivos = <_Dist>[
  _Dist('foto', Icons.account_circle_outlined, 'Con cara y nombre', 'Pon tu foto de perfil o el logo de tu tienda.'),
  _Dist('primera_prenda', Icons.checkroom_outlined, 'Primera prenda', 'Publica tu primera prenda.'),
  _Dist('closet_10', Icons.inventory_2_outlined, 'Clóset lleno', 'Publica 10 prendas.'),
  _Dist('primera_venta', Icons.sell_outlined, 'Primera venta', 'Completa tu primera venta.'),
  _Dist('vendedor_5', Icons.emoji_events_outlined, 'Vendedor de confianza', 'Completa 5 ventas.'),
  _Dist('primera_compra', Icons.shopping_bag_outlined, 'Primera compra', 'Completa tu primera compra.'),
  _Dist('buena_fama', Icons.star_outline_rounded, 'Buena fama', 'Consigue 3 reseñas con promedio de 4,5 estrellas o más.'),
  _Dist('fundador', Icons.workspace_premium_outlined, 'Vendedor fundador', 'Entre los primeros 200 vendedores de Pavito.'),
  _Dist('verificado', Icons.verified_outlined, 'Verificado', 'Lo otorga el equipo de Pavito tras revisar tu cuenta.'),
];

final _cacheDist = <String, Future<Map<String, bool>>>{};

Future<Map<String, bool>> distintivosDe(String userId, {bool fresco = false}) {
  if (fresco) _cacheDist.remove(userId);
  return _cacheDist.putIfAbsent(userId, () async {
    try {
      final r = await _db.rpc('distintivos_de', params: {'p_user': userId});
      final m = Map<String, dynamic>.from(r as Map);
      return {for (final e in m.entries) e.key: e.value == true};
    } catch (_) {
      return <String, bool>{};
    }
  });
}

/// Tarjeta "Distintivos obtenidos X de N" del perfil propio.
class DistintivosCard extends StatelessWidget {
  const DistintivosCard({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, bool>>(
      future: distintivosDe(userId, fresco: true),
      builder: (context, s) {
        final m = s.data ?? const <String, bool>{};
        final n = _distintivos.where((d) => m[d.clave] == true).length;
        return InkWell(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => DistintivosPage(userId: userId))),
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                border: Border.all(color: context.line), borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.verified_outlined),
                const SizedBox(width: 10),
                const Expanded(
                    child: Text('Distintivos obtenidos',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                Text('$n de ${_distintivos.length}', style: TextStyle(color: context.muted)),
              ]),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    value: n / _distintivos.length, minHeight: 8, backgroundColor: context.soft),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Distintivos conseguidos, en pequeño, para el perfil público de un vendedor.
class DistintivosChips extends StatelessWidget {
  const DistintivosChips({super.key, required this.userId, this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 8)});
  final String userId;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, bool>>(
      future: distintivosDe(userId),
      builder: (context, s) {
        final m = s.data ?? const <String, bool>{};
        final ganados = _distintivos.where((d) => m[d.clave] == true).toList();
        if (ganados.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: padding,
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in ganados)
              Tooltip(
                message: d.como,
                child: Chip(
                  avatar: Icon(d.icono, size: 16, color: LP.clayText),
                  label: Text(d.titulo, style: const TextStyle(fontSize: 12.5)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ]),
        );
      },
    );
  }
}

class DistintivosPage extends StatelessWidget {
  const DistintivosPage({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Distintivos')),
      body: FutureBuilder<Map<String, bool>>(
        future: distintivosDe(userId, fresco: true),
        builder: (context, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final m = s.data ?? const <String, bool>{};
          final yo = appState.account?.id == userId;
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (yo && m['foto'] != true)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton.icon(
                    onPressed: () => cambiarFotoPerfil(context),
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Poner mi foto o logo')),
              ),
            for (final d in _distintivos)
              Builder(builder: (context) {
                final ok = m[d.clave] == true;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: ok ? LP.yellow : context.chip,
                    child: Icon(d.icono, color: ok ? Colors.white : context.muted),
                  ),
                  title: Text(d.titulo, style: TextStyle(fontWeight: FontWeight.w700, color: ok ? null : context.muted)),
                  subtitle: Text(d.como),
                  trailing: ok ? const Icon(Icons.check_circle, color: LP.ok) : null,
                );
              }),
          ]);
        },
      ),
    );
  }
}
