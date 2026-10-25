import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
    required this.description,
    required this.color,
    this.photo,
  });

  final String id;
  final String title;
  final double price; // USD
  final String category;
  final String size;
  final String condition;
  final String city;
  final String seller;
  final String description;
  final Color color;
  final Uint8List? photo;
}

const categories = ['Todo', 'Mujer', 'Hombre', 'Niños', 'Zapatos', 'Accesorios'];

/// Anuncios en memoria (ejemplos + los que publica el usuario).
/// En la etapa 2 se reemplaza por el servidor.
class ListingsStore extends ChangeNotifier {
  final List<Listing> _items = [...sampleListings];
  List<Listing> get all => List.unmodifiable(_items);
  void add(Listing l) {
    _items.insert(0, l);
    notifyListeners();
  }

  void remove(String id) {
    _items.removeWhere((l) => l.id == id);
    notifyListeners();
  }
}

final listingsStore = ListingsStore();

/// Datos de ejemplo. En la etapa 2 vendrán del servidor.
const sampleListings = <Listing>[
  Listing(
      id: '1',
      title: 'Chaqueta de jean azul',
      price: 14,
      category: 'Mujer',
      size: 'M',
      condition: 'Muy buen estado',
      city: 'Valencia',
      seller: 'maria_v',
      description: 'Chaqueta de jean clásica, poco uso. Sin manchas ni roturas.',
      color: Color(0xFF9DB7D5)),
  Listing(
      id: '2',
      title: 'Camisa a cuadros',
      price: 8,
      category: 'Hombre',
      size: 'L',
      condition: 'Buen estado',
      city: 'Caracas',
      seller: 'jose_c',
      description: 'Camisa de manga larga, algodón suave.',
      color: Color(0xFFD9A38F)),
  Listing(
      id: '3',
      title: 'Vestido floral verano',
      price: 12,
      category: 'Mujer',
      size: 'S',
      condition: 'Como nuevo',
      city: 'Maracaibo',
      seller: 'ana_m',
      description: 'Vestido ligero, usado una sola vez.',
      color: Color(0xFFE8B4C0)),
  Listing(
      id: '4',
      title: 'Zapatillas deportivas',
      price: 20,
      category: 'Zapatos',
      size: '42',
      condition: 'Buen estado',
      city: 'Barquisimeto',
      seller: 'luis_b',
      description: 'Zapatillas cómodas para caminar y correr.',
      color: Color(0xFFB5C9A8)),
  Listing(
      id: '5',
      title: 'Conjunto infantil',
      price: 9,
      category: 'Niños',
      size: '4 años',
      condition: 'Muy buen estado',
      city: 'Maracay',
      seller: 'carla_p',
      description: 'Camiseta y pantalón para niño de 4 años.',
      color: Color(0xFFF2D49B)),
  Listing(
      id: '6',
      title: 'Bolso de cuero marrón',
      price: 18,
      category: 'Accesorios',
      size: 'Único',
      condition: 'Buen estado',
      city: 'Mérida',
      seller: 'pedro_r',
      description: 'Bolso mediano con cierre, forro interior en buen estado.',
      color: Color(0xFFC9A98A)),
];

/// "Foto" de la prenda: la real si existe, o un color con icono.
class ListingPhoto extends StatelessWidget {
  const ListingPhoto({super.key, required this.item, this.iconSize = 48});
  final Listing item;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    if (item.photo != null) {
      return Image.memory(item.photo!, fit: BoxFit.cover);
    }
    return Container(
        color: item.color,
        child: Icon(Icons.checkroom, size: iconSize, color: Colors.white70));
  }
}
