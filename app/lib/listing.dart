import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  });

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
    );
  }
}

/// Tasa BCV (Bs por dólar). 0 = desconocida; se carga del servidor.
double tasaBs = 0;

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
      final rows = await _db
          .from('listings')
          .select('*, profiles!listings_seller_id_fkey(username)')
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(300);
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
            .select('valor')
            .eq('clave', 'tasa_bs')
            .maybeSingle();
        tasaBs = (t?['valor'] as num?)?.toDouble() ?? tasaBs;
      } catch (_) {}
      error = null;
    } catch (_) {
      error = 'No se pudieron cargar las prendas. Revisa tu conexión.';
    }
    loading = false;
    notifyListeners();
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
  }) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return 'Inicia sesión para vender.';
    try {
      final urls = <String>[];
      for (final photo in photos.take(5)) {
        final png = photo.length > 4 && photo[0] == 0x89 && photo[1] == 0x50;
        final path =
            '$uid/${DateTime.now().microsecondsSinceEpoch}.${png ? 'png' : 'jpg'}';
        await _db.storage.from('listing-photos').uploadBinary(path, photo,
            fileOptions:
                FileOptions(contentType: png ? 'image/png' : 'image/jpeg'));
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
  const ListingPhoto({super.key, required this.item, this.iconSize = 48});
  final Listing item;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(categoryIcons[item.category] ?? Icons.checkroom,
            size: iconSize, color: const Color(0xFFB9B2AA)));
    if (item.photos.isEmpty) return placeholder;
    return Image.network(
      item.photos.first,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => placeholder,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : placeholder,
    );
  }
}
