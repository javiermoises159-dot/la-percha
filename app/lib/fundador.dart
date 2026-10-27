import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'theme.dart';

/// Programa "Vendedor fundador": los primeros 200 vendedores que publican reciben
/// una insignia con su número y 3 destacados gratis. Lo asigna el servidor.
SupabaseClient get _db => Supabase.instance.client;

const fundadoresTotal = 200;
final _cache = <String, Future<int?>>{};

Future<int?> fundadorDe(String userId, {bool fresco = false}) {
  if (fresco) _cache.remove(userId);
  return _cache.putIfAbsent(userId, () async {
    try {
      final r = await _db.from('profiles').select('fundador_n').eq('id', userId).maybeSingle();
      return (r?['fundador_n'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  });
}

Future<int> fundadoresRestantes() async {
  try {
    return ((await _db.rpc('fundadores_restantes')) as num?)?.toInt() ?? 0;
  } catch (_) {
    return 0;
  }
}

/// Insignia "Fundador #N" junto al nombre del vendedor. No ocupa nada si no lo es.
class FundadorChip extends StatelessWidget {
  const FundadorChip({super.key, required this.sellerId, this.grande = false});
  final String sellerId;
  final bool grande;
  @override
  Widget build(BuildContext context) => FutureBuilder<int?>(
        future: fundadorDe(sellerId),
        builder: (context, s) {
          final n = s.data;
          if (n == null) return const SizedBox.shrink();
          return Tooltip(
            message: 'Uno de los primeros $fundadoresTotal vendedores de Pavito',
            child: Container(
              margin: const EdgeInsets.only(top: 3),
              padding: EdgeInsets.symmetric(horizontal: grande ? 10 : 7, vertical: grande ? 4 : 2),
              decoration: BoxDecoration(color: const Color(0xFFFFF1C7), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.workspace_premium_rounded, size: grande ? 16 : 13, color: const Color(0xFF8A5A00)),
                const SizedBox(width: 4),
                Text('Fundador #$n',
                    style: TextStyle(
                        color: const Color(0xFF6B4500), fontWeight: FontWeight.w800, fontSize: grande ? 13 : 11.5)),
              ]),
            ),
          );
        },
      );
}

/// Cartel en Inicio mientras queden puestos y la persona aún no sea fundadora.
class FundadorBanner extends StatefulWidget {
  const FundadorBanner({super.key, this.onVender});
  final VoidCallback? onVender;
  @override
  State<FundadorBanner> createState() => _FundadorBannerState();
}

class _FundadorBannerState extends State<FundadorBanner> {
  int? _quedan;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final me = appState.account?.id;
    if (me != null && await fundadorDe(me) != null) return;
    final q = await fundadoresRestantes();
    if (mounted) setState(() => _quedan = q);
  }

  @override
  Widget build(BuildContext context) {
    final q = _quedan;
    if (q == null || q <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: const Color(0xFFFFF1C7),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => explicarFundador(context, q, widget.onVender),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.workspace_premium_rounded, color: Color(0xFF8A5A00), size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Sé vendedor fundador', style: display(16, color: const Color(0xFF3D2800))),
                  Text('Publica tu primera prenda: insignia + 3 destacados gratis. Quedan $q puestos.',
                      style: const TextStyle(color: Color(0xFF6B4500), fontSize: 13, height: 1.3)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF6B4500)),
            ]),
          ),
        ),
      ),
    );
  }
}

void explicarFundador(BuildContext context, int quedan, VoidCallback? onVender) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Vendedores fundadores', style: display(22, color: c.ink)),
        const SizedBox(height: 10),
        const Text('Los primeros $fundadoresTotal vendedores que publiquen en Pavito reciben:', style: TextStyle(height: 1.4)),
        const SizedBox(height: 8),
        const Text('• La insignia "Fundador" con su número, para siempre en su perfil.\n'
            '• 3 destacados gratis de 7 días: tus prendas salen primero en Inicio.',
            style: TextStyle(height: 1.5)),
        const SizedBox(height: 8),
        Text('Quedan $quedan puestos. Solo tienes que publicar tu primera prenda con el botón Vender (+).', style: TextStyle(color: c.muted)),
        if (onVender != null) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
                onPressed: () {
                  Navigator.pop(c);
                  onVender();
                },
                child: const Text('Publicar mi primera prenda')),
          ),
        ],
      ]),
    ),
  );
}

/// Tras publicar: si con esta prenda la persona entró como fundadora, se lo celebramos.
Future<void> celebrarSiFundador(BuildContext context) async {
  final me = appState.account?.id;
  if (me == null) return;
  try {
    final n = await fundadorDe(me, fresco: true);
    if (n == null) return;
    final mios = (await _db.from('listings').select('id').eq('seller_id', me).limit(2).count(CountOption.exact)).count;
    if (mios != 1 || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.workspace_premium_rounded, color: Color(0xFF8A5A00), size: 44),
        title: Text('¡Eres el vendedor fundador #$n!'),
        content: const Text('Tu insignia ya aparece en tu perfil. Tienes 3 destacados gratis de 7 días: '
            'úsalos en Yo → Herramientas de promoción.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('¡Genial!'))],
      ),
    );
  } catch (_) {}
}
