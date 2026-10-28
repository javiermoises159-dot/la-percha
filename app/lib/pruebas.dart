import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

/// Fotos y videos de un pedido (paquete enviado, reclamo, devolución).
/// Son privados: solo los ven comprador, vendedor y el equipo de Pavito.
SupabaseClient get _db => Supabase.instance.client;

const _maxVideo = 30 * 1024 * 1024; // 30 MB
const _titulos = {
  'envio': 'Paquete enviado (vendedor)',
  'reclamo': 'Reclamo (comprador)',
  'devolucion': 'Devolución recibida (vendedor)',
};

class PruebasBloque extends StatefulWidget {
  const PruebasBloque({
    super.key,
    required this.orderId,
    this.subirTipo,
    this.permitirVideo = false,
    this.onMisPruebas,
    this.ocultarSiVacio = false,
  });
  final String orderId;
  /// Tipo que esta persona puede subir aquí ('envio', 'reclamo', 'devolucion'); null = solo ver.
  final String? subirTipo;
  final bool permitirVideo;
  /// Avisa cuántas pruebas propias de [subirTipo] hay.
  final ValueChanged<int>? onMisPruebas;
  final bool ocultarSiVacio;

  @override
  State<PruebasBloque> createState() => _PruebasBloqueState();
}

class _PruebasBloqueState extends State<PruebasBloque> {
  List<Map<String, dynamic>> _items = [];
  Map<String, String> _urls = {};
  bool _cargando = true, _subiendo = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await _db
          .from('pruebas')
          .select('id, tipo, path, es_video, autor, creado')
          .eq('order_id', widget.orderId)
          .order('creado', ascending: true);
      final items = List<Map<String, dynamic>>.from(r);
      final urls = <String, String>{};
      if (items.isNotEmpty) {
        final firmadas = await _db.storage
            .from('pruebas')
            .createSignedUrls(items.map((e) => e['path'] as String).toList(), 3600);
        for (final f in firmadas) {
          urls[f.path] = f.signedUrl;
        }
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _urls = urls;
        _cargando = false;
      });
      final yo = _db.auth.currentUser?.id;
      widget.onMisPruebas?.call(
          items.where((e) => e['autor'] == yo && e['tipo'] == widget.subirTipo).length);
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _subir({required bool video, required ImageSource src}) async {
    final yo = _db.auth.currentUser?.id;
    if (yo == null || widget.subirTipo == null) return;
    final picker = ImagePicker();
    final x = video
        ? await picker.pickVideo(source: src, maxDuration: const Duration(seconds: 60))
        : await picker.pickImage(source: src, maxWidth: 1600, imageQuality: 82);
    if (x == null) return;
    setState(() {
      _subiendo = true;
      _error = null;
    });
    try {
      final bytes = await x.readAsBytes();
      if (video && bytes.length > _maxVideo) {
        throw 'El video pesa más de 30 MB. Graba uno más corto (máx. 1 minuto).';
      }
      final nombre = x.name.toLowerCase();
      final ext = video
          ? (nombre.endsWith('.mov') ? 'mov' : nombre.endsWith('.webm') ? 'webm' : 'mp4')
          : 'jpg';
      final tipoMime = video
          ? (ext == 'mov' ? 'video/quicktime' : ext == 'webm' ? 'video/webm' : 'video/mp4')
          : 'image/jpeg';
      final path = '${widget.orderId}/$yo/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _db.storage
          .from('pruebas')
          .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: tipoMime));
      await _db.from('pruebas').insert({
        'order_id': widget.orderId,
        'tipo': widget.subirTipo,
        'path': path,
        'es_video': video,
      });
      await _cargar();
    } on PostgrestException catch (e) {
      setState(() => _error = e.message.contains('Máximo')
          ? 'Ya subiste el máximo de 8 fotos o videos.'
          : 'No se pudo guardar. Intenta de nuevo.');
    } catch (e) {
      setState(() => _error = e is String ? e : 'No se pudo subir. Revisa tu conexión e intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  void _elegir({required bool video}) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(video ? Icons.videocam_outlined : Icons.photo_camera_outlined),
            title: Text(video ? 'Grabar un video' : 'Tomar una foto'),
            onTap: () {
              Navigator.pop(ctx);
              _subir(video: video, src: ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Elegir de la galería'),
            onTap: () {
              Navigator.pop(ctx);
              _subir(video: video, src: ImageSource.gallery);
            },
          ),
        ]),
      ),
    );
  }

  void _ver(Map<String, dynamic> p) {
    final url = _urls[p['path']];
    if (url == null) return;
    if (p['es_video'] == true) {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
      ),
    );
  }

  Widget _miniatura(Map<String, dynamic> p) {
    final url = _urls[p['path']];
    return Semantics(
      button: true,
      label: p['es_video'] == true ? 'Ver video' : 'Ver foto',
      child: InkWell(
        onTap: () => _ver(p),
        borderRadius: BorderRadius.circular(10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 84,
            height: 84,
            color: context.chip,
            child: p['es_video'] == true || url == null
                ? Icon(p['es_video'] == true ? Icons.play_circle_outline : Icons.image_outlined,
                    size: 36, color: context.muted)
                : Image.network(url, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(Icons.image_outlined, color: context.muted)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))));
    }
    if (_items.isEmpty && widget.subirTipo == null && widget.ocultarSiVacio) {
      return const SizedBox.shrink();
    }
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final p in _items) {
      (grupos[p['tipo'] as String] ??= []).add(p);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final g in grupos.entries) ...[
        Text(_titulos[g.key] ?? g.key,
            style: TextStyle(fontWeight: FontWeight.w700, color: context.ink, fontSize: 13.5)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final p in g.value) _miniatura(p)]),
        const SizedBox(height: 12),
      ],
      if (widget.subirTipo != null)
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: _subiendo ? null : () => _elegir(video: false),
            icon: const Icon(Icons.add_a_photo_outlined, size: 20),
            label: const Text('Añadir foto'),
          ),
          if (widget.permitirVideo)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _subiendo ? null : () => _elegir(video: true),
              icon: const Icon(Icons.videocam_outlined, size: 20),
              label: const Text('Añadir video'),
            ),
          if (_subiendo)
            const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
        ]),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
      ],
    ]);
  }
}

/// Pantalla para abrir un reclamo: exige al menos una foto propia antes de enviarlo.
/// Devuelve true si la persona confirmó el reclamo.
class ReclamoPage extends StatefulWidget {
  const ReclamoPage({super.key, required this.orderId, required this.tipo});
  final String orderId;
  final String tipo; // 'reclamo' (comprador) o 'devolucion' (vendedor)

  @override
  State<ReclamoPage> createState() => _ReclamoPageState();
}

class _ReclamoPageState extends State<ReclamoPage> {
  int _mias = 0;

  @override
  Widget build(BuildContext context) {
    final comprador = widget.tipo == 'reclamo';
    return Scaffold(
      appBar: AppBar(title: Text(comprador ? 'Tuve un problema' : 'La devolución llegó con problemas')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Sube fotos de lo que recibiste', style: display(22, color: context.ink)),
        const SizedBox(height: 8),
        Text(
            comprador
                ? 'Para revisar tu caso necesitamos ver la prenda y el paquete: la etiqueta, la talla, '
                  'el defecto o lo que no coincide con el anuncio. Mientras tanto, el pago queda congelado.'
                : 'Muéstranos lo que te devolvieron: la prenda, la etiqueta y el paquete. '
                  'Mientras tanto, el dinero queda congelado.',
            style: TextStyle(color: context.muted, height: 1.4)),
        const SizedBox(height: 10),
        Text('Si puedes, graba también un video abriendo el paquete.',
            style: TextStyle(color: context.muted, height: 1.4)),
        const SizedBox(height: 18),
        PruebasBloque(
          orderId: widget.orderId,
          subirTipo: widget.tipo,
          permitirVideo: true,
          onMisPruebas: (n) => setState(() => _mias = n),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _mias == 0 ? null : () => Navigator.of(context).pop(true),
          child: Text(_mias == 0 ? 'Sube al menos una foto' : 'Abrir reclamo'),
        ),
        const SizedBox(height: 8),
        Text('Cuéntale también al vendedor por el chat qué pasó.',
            textAlign: TextAlign.center, style: TextStyle(color: context.muted, fontSize: 13)),
      ]),
    );
  }
}
