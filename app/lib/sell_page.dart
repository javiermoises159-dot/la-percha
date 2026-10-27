import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'fundador.dart';
import 'listing.dart';
import 'theme.dart';

const _conditions = [
  'Como nuevo',
  'Muy buen estado',
  'Buen estado',
  'Con detalles'
];
const _cities = [
  'Caracas',
  'Valencia',
  'Maracaibo',
  'Barquisimeto',
  'Maracay',
  'Puerto La Cruz',
  'Mérida',
  'San Cristóbal',
  'Ciudad Guayana',
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
  final List<Uint8List> _photos = [];
  bool _fotoIa = false; // la primera foto es una portada creada por la IA
  bool _scanning = false;
  bool _autoScan = false;

  /// "Vende con una foto": la IA del servidor rellena el anuncio.
  Future<void> _scan() async {
    if (_photos.isEmpty) {
      _autoScan = true; // al elegir la foto, se arma el anuncio solo
      return _choosePhoto();
    }
    final foto = _photos[_fotoIa && _photos.length > 1 ? 1 : 0];
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final res =
          await Supabase.instance.client.functions.invoke('escanear', body: {
        'imagen': base64Encode(foto),
        'mime': 'image/jpeg',
        'limpia': !_fotoIa,
      });
      final d = Map<String, dynamic>.from(res.data as Map);
      setState(() {
        _title.text = '${d['titulo'] ?? ''}';
        _desc.text = [
          '${d['descripcion'] ?? ''}',
          if (d['marca'] != null) 'Marca: ${d['marca']}.',
          if (d['color'] != null) 'Color: ${d['color']}.',
        ].where((x) => x.trim().isNotEmpty).join(' ');
        if (d['precio_sugerido'] != null)
          _price.text = '${d['precio_sugerido']}';
        final cat = '${d['categoria']}';
        if (categories.contains(cat) && cat != 'Todo') _category = cat;
        final sizes = sizesFor(_category);
        final talla = d['talla'] as String?;
        _size = talla != null && sizes.contains(talla)
            ? talla
            : (sizes.contains(_size) ? _size : sizes.first);
        final estado = '${d['estado']}';
        if (_conditions.contains(estado)) _condition = estado;
        final limpia = d['foto_limpia'] as String?;
        if (limpia != null && !_fotoIa && _photos.length < 5) {
          _photos.insert(0, base64Decode(limpia));
          _fotoIa = true;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Listo. Revisa los datos y el precio antes de publicar.')));
      }
    } on FunctionException catch (e) {
      final det = e.details;
      setState(() => _error = det is Map && det['error'] != null
          ? '${det['error']}'
          : 'No se pudo analizar la foto. Intenta de nuevo.');
    } catch (_) {
      setState(
          () => _error = 'No se pudo analizar la foto. Revisa tu conexión.');
    }
    if (mounted) setState(() => _scanning = false);
  }

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
    if (_photos.length < 5) setState(() => _photos.add(bytes));
    if (_autoScan) {
      _autoScan = false;
      _scan();
    }
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
    if (_fotoIa && _photos.length < 2) {
      return setState(() =>
          _error = 'Añade al menos una foto real además de la portada IA.');
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
      photos: _photos,
      fotoIa: _fotoIa,
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
      _photos.clear();
      _fotoIa = false;
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Publicado! Ya está a la venta.')));
    widget.onPublished();
    celebrarSiFundador(context);
  }

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Vender', style: display(26, color: ink)),
        const SizedBox(height: 4),
        Text(
            'Sin comisión: cobras el precio completo. O escríbelo tú mismo más abajo.',
            style: TextStyle(color: context.muted)),
        const SizedBox(height: 16),
        if (_photos.isEmpty) ...[
          _MagicButton(busy: _scanning, hasPhoto: false, onTap: _scan),
          const SizedBox(height: 20),
        ],
        SizedBox(
          height: 110,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var i = 0; i < _photos.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_photos[i],
                        width: 110, height: 110, fit: BoxFit.cover),
                  ),
                  if (i == 0)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: _fotoIa
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(6)),
                              child: const Text('Catálogo',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 11)),
                            )
                          : const SizedBox.shrink(),
                    ),
                  if (i == 0)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6)),
                        child: const Text('Portada',
                            style:
                                TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                    ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: IconButton.filledTonal(
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      tooltip: 'Quitar foto',
                      onPressed: () => setState(() {
                        if (i == 0 && _fotoIa) _fotoIa = false;
                        _photos.removeAt(i);
                      }),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ]),
              ),
            if (_photos.length < 5)
              GestureDetector(
                onTap: _choosePhoto,
                child: Container(
                  width: 110,
                  decoration: BoxDecoration(
                      color: context.chip,
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_outlined, color: context.muted),
                        const SizedBox(height: 4),
                        Text(
                            _photos.isEmpty
                                ? 'Añadir fotos'
                                : '${_photos.length}/5',
                            style:
                                TextStyle(color: context.muted, fontSize: 12)),
                      ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Text(
            'Hasta 5 fotos con buena luz: de frente, detalles y etiqueta. Más fotos, más confianza.',
            style: TextStyle(color: context.muted, fontSize: 12)),
        if (_photos.isNotEmpty) ...[
          const SizedBox(height: 10),
          _MagicButton(busy: _scanning, hasPhoto: true, onTap: _scan),
        ],
        if (_fotoIa)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                'Te armamos una portada de catálogo. Los compradores verán también tus fotos reales; '
                'debes tener al menos una.',
                style: TextStyle(color: context.muted, fontSize: 12)),
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
            onChanged: (v) => setState(() {
                  _category = v;
                  final s = sizesFor(v);
                  if (!s.contains(_size)) _size = s.first;
                })),
        const SizedBox(height: 12),
        Row(children: [
          if (sizesFor(_category).length > 1) ...[
            Expanded(
                child: _Drop(
                    label: 'Talla',
                    value: _size,
                    items: sizesFor(_category),
                    onChanged: (v) => setState(() => _size = v))),
            const SizedBox(width: 12),
          ],
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

/// "Foto y listo": sin fotos, una tarjeta oscura tipo cámara; con foto, un botón.
class _MagicButton extends StatelessWidget {
  const _MagicButton(
      {required this.busy, required this.hasPhoto, required this.onTap});
  final bool busy;
  final bool hasPhoto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    if (hasPhoto) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: LP.ink, foregroundColor: Colors.white),
        onPressed: busy ? null : onTap,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.bolt_rounded),
        label: Text(
            busy ? 'Armando tu anuncio…' : 'Arma el anuncio con esta foto'),
      );
    }
    Widget step(String n, String t) => Expanded(
          child: Column(children: [
            CircleAvatar(
                radius: 14,
                backgroundColor: Theme.of(context).colorScheme.surface,
                child: Text(n,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: context.ink))),
            const SizedBox(height: 6),
            Text(t,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          ]),
        );
    return Column(children: [
      GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          height: 230,
          decoration: BoxDecoration(
              color: const Color(0xFF211D1A),
              borderRadius: BorderRadius.circular(20)),
          child: Stack(alignment: Alignment.center, children: [
            Positioned(
              left: 54,
              right: 54,
              top: 30,
              bottom: 76,
              child: Container(
                decoration: BoxDecoration(
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.8), width: 2),
                    borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.photo_camera_outlined,
                    color: Colors.white70, size: 40),
              ),
            ),
            const Positioned(
              bottom: 46,
              child: Text('Encuadra el artículo con buena luz',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
            Positioned(
              bottom: 8,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: 4)),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 18),
      Text('Foto y listo', style: display(24, color: context.ink)),
      const SizedBox(height: 4),
      Text('Nosotros escribimos el anuncio. Tú solo revisas el precio.',
          textAlign: TextAlign.center, style: TextStyle(color: context.muted)),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: context.soft, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          step('1', 'Haz la foto'),
          step('2', 'Revisa los datos'),
          step('3', 'Publica gratis'),
        ]),
      ),
    ]);
  }
}
