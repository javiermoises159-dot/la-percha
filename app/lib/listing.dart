import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

class Listing {
  const Listing({
    required this.id,
    required this.title,
    required this.price,
    required this.category,
    required this.size,
    required this.condition,
    required this.city,
    required this.seller,
    required this.sellerId,
    required this.description,
    required this.photos,
    required this.color,
    this.featuredUntil,
    this.fotoIa = false,
    this.createdAt,
    this.brand,
    this.envioGratis = false,
    this.envioTamano,
  });

  /// Tamaño del paquete elegido por el vendedor: chico, mediano o grande (null = según la categoría).
  final String? envioTamano;

  /// El vendedor paga el envío.
  final bool envioGratis;

  /// Marca (opcional).
  final String? brand;

  final String id;
  final String title;
  final double price; // USD
  final String category;
  final String size;
  final String condition;
  final String city;
  final String seller;
  final String sellerId;
  final String description;
  final List<String> photos;
  final Color color;
  final DateTime? featuredUntil;
  final bool fotoIa;
  final DateTime? createdAt;

  bool get featured =>
      featuredUntil != null && featuredUntil!.isAfter(DateTime.now());

  factory Listing.fromMap(Map<String, dynamic> m) {
    final id = m['id'] as String;
    final prof = m['profiles'];
    return Listing(
      id: id,
      title: m['title'] as String,
      price: (m['price'] as num).toDouble(),
      category: m['category'] as String,
      size: m['size'] as String,
      condition: m['condition'] as String,
      city: m['city'] as String,
      seller: prof is Map ? (prof['username'] as String? ?? '') : '',
      sellerId: m['seller_id'] as String,
      description: m['description'] as String? ?? '',
      photos: List<String>.from(m['photos'] as List? ?? const []),
      color: _tints[id.hashCode.abs() % _tints.length],
      featuredUntil: DateTime.tryParse('${m['featured_until'] ?? ''}'),
      fotoIa: m['foto_ia'] == true,
      createdAt: DateTime.tryParse('${m['created_at'] ?? ''}')?.toLocal(),
      envioGratis: m['envio_gratis'] == true,
      envioTamano: m['envio_tamano'] as String?,
      brand: (m['brand'] as String?)?.trim().isEmpty == true ? null : m['brand'] as String?,
    );
  }
}

/// Tasa BCV (Bs por dólar). 0 = desconocida; se carga del servidor.
double tasaBs = 0;

/// Cuándo se actualizó la tasa por última vez (la pone el servidor cada hora).
DateTime? tasaActualizada;

/// La tasa tiene más de 24 h sin actualizarse: no se debe cobrar en Bs con ella.
bool get tasaVieja =>
    tasaBs <= 0 || tasaActualizada == null || DateTime.now().difference(tasaActualizada!).inHours >= 24;

/// "≈ Bs 6.027,40", o vacío si aún no hay tasa.
String bsText(double usd) {
  if (tasaBs <= 0) return '';
  final v = usd * tasaBs;
  final parts = v.toStringAsFixed(v >= 100 ? 0 : 2).split('.');
  final ent =
      parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return parts.length > 1 ? '≈ Bs $ent,${parts[1]}' : '≈ Bs $ent';
}

const _tints = [
  Color(0xFF9DB7D5),
  Color(0xFFD9A38F),
  Color(0xFFE8B4C0),
  Color(0xFFB5C9A8),
  Color(0xFFF2D49B),
  Color(0xFFC9A98A),
];

const categories = [
  'Todo',
  'Mujer',
  'Hombre',
  'Niños',
  'Bebés',
  'Zapatos',
  'Accesorios',
  'Hogar',
  'Libros y juegos',
  'Deportes',
  'Mascotas',
];

/// Tamaño de paquete sugerido según la categoría.
String tamanoSugerido(String categoria) {
  if (const {'Accesorios', 'Bebés', 'Libros y juegos', 'Mascotas'}.contains(categoria)) return 'chico';
  if (const {'Zapatos', 'Hogar', 'Deportes'}.contains(categoria)) return 'grande';
  return 'mediano';
}

const tamanosPaquete = {
  'chico': 'Pequeño: cabe en un sobre o bolsa grande',
  'mediano': 'Mediano: cabe en una caja de zapatos',
  'grande': 'Grande: cabe en una caja de mudanza',
};

const _clothing = {'Mujer', 'Hombre', 'Niños', 'Bebés'};
const _clothingSizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'Única'];
const _babySizes = [
  '0-3 m',
  '3-6 m',
  '6-12 m',
  '12-18 m',
  '18-24 m',
  '2 años',
  '3 años',
  '4 años'
];
const _shoeSizes = [
  '22-27',
  '28-33',
  '34',
  '35',
  '36',
  '37',
  '38',
  '39',
  '40',
  '41',
  '42',
  '43',
  '44',
  '45'
];

/// Tallas según la categoría; lo que no es ropa no lleva talla.
List<String> sizesFor(String category) {
  if (category == 'Zapatos') return _shoeSizes;
  if (category == 'Bebés') return _babySizes;
  if (_clothing.contains(category)) return _clothingSizes;
  return const ['No aplica'];
}

/// ¿La categoría usa la palabra "prenda" o "artículo"?
bool isClothing(String category) =>
    _clothing.contains(category) ||
    category == 'Zapatos' ||
    category == 'Accesorios';

const categoryIcons = {
  'Mujer': Icons.woman,
  'Hombre': Icons.man,
  'Niños': Icons.child_care,
  'Bebés': Icons.baby_changing_station,
  'Zapatos': Icons.hiking,
  'Accesorios': Icons.watch_outlined,
  'Hogar': Icons.chair_outlined,
  'Libros y juegos': Icons.menu_book_outlined,
  'Deportes': Icons.sports_soccer,
  'Mascotas': Icons.pets,
};

/// Anuncios que vienen del servidor.
class ListingsStore extends ChangeNotifier {
  List<Listing> _items = [];
  List<Listing> _raw = [];

  /// Puntuación extra por preferencias (ciudad, categorías); la pone extras.dart.
  static int Function(Listing)? prefScore;

  // Destacados primero; luego lo que encaja con tus preferencias; luego lo más nuevo.
  void _sort() {
    final s = prefScore;
    final list = [..._raw];
    list.sort((a, b) {
      final f = (b.featured ? 1 : 0) - (a.featured ? 1 : 0);
      if (f != 0) return f;
      return s == null ? 0 : s(b) - s(a);
    });
    _items = list;
  }

  void resort() {
    _sort();
    notifyListeners();
  }

  bool loading = false;
  String? error;
  List<Listing> get all => List.unmodifiable(_items);

  SupabaseClient get _db => Supabase.instance.client;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      PostgrestList rows;
      try {
        rows = await _db
            .from('listings')
            .select('*, profiles!listings_seller_id_fkey(username)')
            .eq('status', 'active')
            .order('orden', ascending: false, nullsFirst: false)
            .limit(300);
      } on PostgrestException {
        // Servidor sin la columna "orden" todavía: orden por fecha de publicación.
        rows = await _db
            .from('listings')
            .select('*, profiles!listings_seller_id_fkey(username)')
            .eq('status', 'active')
            .order('created_at', ascending: false)
            .limit(300);
      }
      _raw = [for (final r in rows) Listing.fromMap(r)];
      // Los destacados siempre salen, aunque sean más viejos que los últimos 300.
      try {
        final dest = await _db
            .from('listings')
            .select('*, profiles!listings_seller_id_fkey(username)')
            .eq('status', 'active')
            .gt('featured_until', DateTime.now().toUtc().toIso8601String())
            .limit(100);
        final ids = {for (final l in _raw) l.id};
        _raw.addAll([for (final r in dest) if (!ids.contains(r['id'])) Listing.fromMap(r)]);
      } catch (_) {}
      _sort();
      try {
        final t = await _db
            .from('ajustes')
            .select('valor, actualizado')
            .eq('clave', 'tasa_bs')
            .maybeSingle();
        tasaBs = (t?['valor'] as num?)?.toDouble() ?? tasaBs;
        tasaActualizada = DateTime.tryParse('${t?['actualizado'] ?? ''}')?.toLocal() ?? tasaActualizada;
      } catch (_) {}
      error = null;
    } catch (_) {
      error = 'No se pudieron cargar las prendas. Revisa tu conexión.';
    }
    loading = false;
    notifyListeners();
  }

  /// Cambia los datos de un anuncio propio (no las fotos). Devuelve null si salió bien.
  Future<String?> editar(String id, Map<String, dynamic> cambios) async {
    try {
      await _db.from('listings').update(cambios).eq('id', id);
      await load();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (_) {
      return 'No se pudo guardar. Revisa tu conexión.';
    }
  }

  /// Busca en toda la base de datos (título, descripción, categoría o vendedor),
  /// no solo en lo que ya está cargado. Devuelve null si no hay conexión.
  Future<List<Listing>?> buscar(String q, {String? categoria, int limite = 100}) async {
    try {
      final rows = await _db
          .rpc('buscar_anuncios', params: {'p_q': q, 'p_cat': categoria, 'p_lim': limite})
          .select('*, profiles!listings_seller_id_fkey(username)');
      return [for (final r in rows) Listing.fromMap(r)];
    } catch (_) {
      return null;
    }
  }

  /// Devuelve null si salió bien, o el mensaje de error.
  Future<String?> publish({
    required String title,
    required String description,
    required double price,
    required String category,
    required String size,
    required String condition,
    required String city,
    List<Uint8List> photos = const [],
    bool fotoIa = false,
    String? brand,
    bool envioGratis = false,
    String? envioTamano,
  }) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return 'Inicia sesión para vender.';
    try {
      final urls = <String>[];
      for (final (i, photo) in photos.take(5).indexed) {
        final png = photo.length > 4 && photo[0] == 0x89 && photo[1] == 0x50;
        final ts = DateTime.now().microsecondsSinceEpoch;
        // La portada lleva además una miniatura ("m_…" → "m_…-mini.jpg") para la cuadrícula.
        final mini = i == 0 ? miniaturaJpg(photo) : null;
        final path = '$uid/${mini != null ? 'm_' : ''}$ts.${png ? 'png' : 'jpg'}';
        await _db.storage.from('listing-photos').uploadBinary(path, photo,
            fileOptions:
                FileOptions(contentType: png ? 'image/png' : 'image/jpeg', cacheControl: '31536000'));
        if (mini != null) {
          try {
            await _db.storage.from('listing-photos').uploadBinary('$uid/m_$ts-mini.jpg', mini,
                fileOptions: const FileOptions(contentType: 'image/jpeg', cacheControl: '31536000'));
          } catch (_) {}
        }
        urls.add(_db.storage.from('listing-photos').getPublicUrl(path));
      }
      await _db.from('listings').insert({
        'title': title,
        'description': description,
        'price': price,
        'category': category,
        'size': size,
        'condition': condition,
        'city': city,
        'photos': urls,
        if (fotoIa) 'foto_ia': true,
        if (envioGratis) 'envio_gratis': true,
        if (envioTamano != null) 'envio_tamano': envioTamano,
        if (brand != null && brand.trim().isNotEmpty) 'brand': brand.trim(),
      });
      await load();
      return null;
    } on StorageException catch (e) {
      return 'No se pudo subir la foto: ${e.message}';
    } on PostgrestException catch (e) {
      return e.message;
    } catch (_) {
      return 'No se pudo publicar. Revisa tu conexión.';
    }
  }
}

final listingsStore = ListingsStore();

/// Foto de la prenda: la real si existe, o un color con icono.
class ListingPhoto extends StatelessWidget {
  const ListingPhoto({super.key, required this.item, this.iconSize = 48, this.grande = false});
  /// true = foto completa (vistas grandes); false = miniatura si existe (cuadrículas).
  final bool grande;
  final Listing item;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(categoryIcons[item.category] ?? Icons.checkroom,
            size: iconSize, color: const Color(0xFFB9B2AA)));
    if (item.photos.isEmpty) return placeholder;
    final full = item.photos.first;
    final mini = grande ? null : urlMiniatura(full);
    if (mini != null) {
      return Image.network(
        mini,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => Image.network(full,
            fit: BoxFit.cover, width: double.infinity, height: double.infinity,
            errorBuilder: (_, __, ___) => placeholder),
        loadingBuilder: (_, child, progress) => progress == null ? child : placeholder,
      );
    }
    return Image.network(
      full,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => placeholder,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : placeholder,
    );
  }
}


/// Miniatura JPG de unos 400 px de ancho para las cuadrículas (gasta 5–6 veces menos datos).
Uint8List? miniaturaJpg(Uint8List foto) {
  try {
    final d = img.decodeImage(foto);
    if (d == null) return null;
    final r = d.width > 400 ? img.copyResize(d, width: 400, interpolation: img.Interpolation.average) : d;
    return Uint8List.fromList(img.encodeJpg(r, quality: 72));
  } catch (_) {
    return null;
  }
}

/// URL de la miniatura de una portada subida con miniatura ("…/m_123.jpg" → "…/m_123-mini.jpg").
String? urlMiniatura(String url) {
  final m = RegExp(r'^(.*/m_\d+)\.(jpg|png)$').firstMatch(url);
  return m == null ? null : '${m.group(1)}-mini.jpg';
}
