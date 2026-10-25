import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_state.dart';
import 'listing.dart';
import 'theme.dart';

const _sizes = ['XS', 'S', 'M', 'L', 'XL', 'Único', '36', '38', '40', '42'];
const _conditions = ['Como nuevo', 'Muy buen estado', 'Buen estado', 'Con detalles'];
const _cities = [
  'Caracas', 'Valencia', 'Maracaibo', 'Barquisimeto', 'Maracay',
  'Puerto La Cruz', 'Mérida', 'San Cristóbal', 'Ciudad Guayana',
  'Isla de Margarita',
];

/// Pantalla para publicar una prenda.
class SellPage extends StatefulWidget {
  const SellPage({super.key, required this.state, required this.onPublished});
  final AppState state;
  final VoidCallback onPublished;

  @override
  State<SellPage> createState() => _SellPageState();
}

class _SellPageState extends State<SellPage> {
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _desc = TextEditingController();
  Uint8List? _photo;
  String _category = 'Mujer';
  String _size = 'M';
  String _condition = 'Muy buen estado';
  String? _city;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    final x = await ImagePicker()
        .pickImage(source: src, maxWidth: 1000, imageQuality: 80);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() => _photo = bytes);
  }

  void _choosePhoto() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Tomar una foto'),
            onTap: () {
              Navigator.pop(ctx);
              _pick(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Elegir de la galería'),
            onTap: () {
              Navigator.pop(ctx);
              _pick(ImageSource.gallery);
            },
          ),
        ]),
      ),
    );
  }

  bool _busy = false;

  Future<void> _publish() async {
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    final acct = widget.state.account;
    if (acct == null) {
      return setState(() => _error = 'Inicia sesión para vender.');
    }
    if (_title.text.trim().length < 3) {
      return setState(() => _error = 'Escribe un título (mínimo 3 letras).');
    }
    if (price == null || price <= 0 || price > 5000) {
      return setState(
          () => _error = 'Escribe un precio en dólares entre 1 y 5000.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await listingsStore.publish(
      title: _title.text.trim(),
      description: _desc.text.trim(),
      price: price,
      category: _category,
      size: _size,
      condition: _condition,
      city: _city ?? acct.city,
      photo: _photo,
    );
    if (!mounted) return;
    if (err != null) {
      return setState(() {
        _busy = false;
        _error = err;
      });
    }
    _title.clear();
    _price.clear();
    _desc.clear();
    setState(() {
      _busy = false;
      _photo = null;
      _error = null;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('¡Prenda publicada!')));
    widget.onPublished();
  }

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Vender una prenda', style: display(24, color: ink)),
        const SizedBox(height: 4),
        Text('Sin comisión: cobras el precio completo.',
            style: TextStyle(color: context.muted)),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _choosePhoto,
          child: AspectRatio(
            aspectRatio: 1.4,
            child: Container(
              decoration: BoxDecoration(
                color: context.chip,
                borderRadius: BorderRadius.circular(14),
                image: _photo == null
                    ? null
                    : DecorationImage(
                        image: MemoryImage(_photo!), fit: BoxFit.cover),
              ),
              child: _photo == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_outlined,
                            size: 36, color: context.muted),
                        const SizedBox(height: 6),
                        Text('Añadir foto',
                            style: TextStyle(color: context.muted)),
                      ],
                    )
                  : null,
            ),
          ),
        ),
        if (_photo != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
                onPressed: _choosePhoto, child: const Text('Cambiar foto')),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          maxLength: 60,
          decoration: const InputDecoration(
              labelText: 'Título', hintText: 'Chaqueta de jean azul'),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _desc,
          maxLines: 3,
          maxLength: 300,
          decoration: const InputDecoration(
              labelText: 'Descripción', hintText: 'Estado, medidas, marca…'),
        ),
        const SizedBox(height: 8),
        _Drop(
            label: 'Categoría',
            value: _category,
            items: categories.where((c) => c != 'Todo').toList(),
            onChanged: (v) => setState(() => _category = v)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _Drop(
                  label: 'Talla',
                  value: _size,
                  items: _sizes,
                  onChanged: (v) => setState(() => _size = v))),
          const SizedBox(width: 12),
          Expanded(
              child: _Drop(
                  label: 'Estado',
                  value: _condition,
                  items: _conditions,
                  onChanged: (v) => setState(() => _condition = v))),
        ]),
        const SizedBox(height: 12),
        _Drop(
            label: 'Ciudad',
            value: _city ?? widget.state.account?.city ?? _cities.first,
            items: {
              if (widget.state.account != null) widget.state.account!.city,
              ..._cities
            }.toList(),
            onChanged: (v) => setState(() => _city = v)),
        const SizedBox(height: 12),
        TextField(
          controller: _price,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              labelText: 'Precio en dólares', prefixText: '\$ '),
        ),
        if (price != null && price > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                'Tú cobras \$${price.toStringAsFixed(2)}. El comprador paga además la protección.',
                style: TextStyle(color: context.leaf, fontSize: 13)),
          ),
        if (_error != null)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: context.chip, borderRadius: BorderRadius.circular(10)),
            child: Text(_error!),
          ),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: _busy ? null : _publish,
            child: Text(_busy ? 'Publicando…' : 'Publicar')),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Drop extends StatelessWidget {
  const _Drop(
      {required this.label,
      required this.value,
      required this.items,
      required this.onChanged});
  final String label;
  final String value;
  final List<String> items;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: items.contains(value) ? value : items.first,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final i in items) DropdownMenuItem(value: i, child: Text(i))
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
