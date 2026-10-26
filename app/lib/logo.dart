import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Guacamaya de Pavito (con contorno). Mira a la izquierda, hacia el nombre.
const guacamayaSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">
  <g stroke="#161412" stroke-width="4" stroke-linejoin="round" stroke-linecap="round">
    <path d="M44 76c2 18 10 32 22 42h44c4-26-2-50-18-66" fill="#E0452C"/>
    <circle cx="72" cy="50" r="32" fill="#E0452C"/>
    <path d="M86 78c14 6 22 20 24 40H94c0-16-4-28-8-40z" fill="#F5B731"/>
    <path d="M99 94c6 6 10 14 11 24h-8c0-9-1-17-3-24z" fill="#1F5FBF"/>
    <path d="M48 40c6-10 20-12 28-5 8 8 7 22-2 28-9 6-21 4-27-4-4-6-3-13 1-19z" fill="#fff"/>
    <path d="M50 34C32 28 15 38 14 58c0 10 4 18 11 24-1-10 3-18 12-21l13-1z" fill="#F2E4CC"/>
    <path d="M37 61c-6 4-7 13-2 19 7-1 13-7 14-17z" fill="#161412"/>
  </g>
  <circle cx="64" cy="46" r="5" fill="#161412"/><circle cx="65.5" cy="44.5" r="1.5" fill="#fff"/>
</svg>
''';

class Guacamaya extends StatelessWidget {
  const Guacamaya({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) =>
      SvgPicture.string(guacamayaSvg, width: size, height: size, semanticsLabel: 'Pavito');
}

/// Nombre anterior del símbolo, por compatibilidad.
class LogoMark extends Guacamaya {
  const LogoMark({super.key, super.size});
}
