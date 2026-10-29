import 'package:flutter/material.dart';

/// Opciones de rebaja programada: (porcentaje, días). null = sin rebaja.
const rebajaOpciones = <(int, int)?>[
  null,
  (5, 7),
  (10, 14),
  (15, 14),
  (20, 30),
  (25, 30),
];

String rebajaTexto((int, int)? r) =>
    r == null ? 'No bajar el precio' : 'Bajar ${r.$1} % si no se vende en ${r.$2} días';

/// Selector de "rebaja programada" para publicar o editar un anuncio.
class RebajaPicker extends StatelessWidget {
  const RebajaPicker({super.key, required this.valor, required this.onChanged});
  final (int, int)? valor;
  final ValueChanged<(int, int)?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<(int, int)?>(
        initialValue: rebajaOpciones.contains(valor) ? valor : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Rebaja programada (opcional)'),
        items: [
          for (final o in rebajaOpciones)
            DropdownMenuItem<(int, int)?>(value: o, child: Text(rebajaTexto(o))),
        ],
        onChanged: onChanged,
      ),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text(
            'Si nadie lo compra en ese tiempo, el precio baja solo una vez y avisamos a quienes lo tienen en favoritos.',
            style: TextStyle(fontSize: 12.5)),
      ),
    ]);
  }
}
