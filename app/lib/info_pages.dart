import 'package:flutter/material.dart';

/// Página de texto simple (ayuda, legales, funciones próximas).
class InfoPage extends StatelessWidget {
  const InfoPage({super.key, required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(body, style: const TextStyle(fontSize: 16, height: 1.5)),
        const SizedBox(height: 24),
      ]),
    );
  }
}

const _draft =
    '\n\n(Borrador informativo. Será revisado por un abogado antes del lanzamiento oficial.)';

const guideText = '''Cómo funciona La Percha

Comprar
1. Busca una prenda y ábrela.
2. Escribe al vendedor si tienes dudas.
3. Compra con "Compra protegida": tu dinero queda retenido y solo se entrega al vendedor cuando confirmas que recibiste la prenda.

Vender
1. Ve a "Vender", sube una foto y rellena los datos.
2. Cuando alguien compre, envía la prenda y marca el envío.
3. Cobras el precio completo: el vendedor no paga comisión.

Consejos
- Toma fotos con buena luz y muestra los detalles.
- Describe el estado con honestidad.
- Nunca pagues ni cobres fuera de La Percha: así no tendrás protección.''';

const helpText = '''Centro de ayuda

¿Algún problema con una compra o una venta? Escríbenos y lo revisamos.

Importante para tu seguridad
- La Percha nunca te pedirá tu contraseña por mensaje.
- No pagues por fuera de la app ni compartas códigos.
- Si algo no parece normal, usa la opción de denunciar o escríbenos.

Contacto de soporte: se publicará aquí antes del lanzamiento.''';

const aboutText =
    '''La Percha es un mercado de ropa usada para toda Venezuela. Queremos que la ropa tenga una segunda vida, que vender sea gratis y que comprar sea seguro.

Versión de prueba.''';

const legalText = '''Notas legales

La Percha es una plataforma que conecta a personas que compran y venden ropa usada. Las prendas las venden usuarios particulares.$_draft''';

const privacyText = '''Política de privacidad

Qué datos guardamos
- Tu correo, nombre de usuario y ciudad.
- Tus anuncios, fotos, favoritos y mensajes.

Quién los ve
- Tu nombre de usuario, ciudad y anuncios son públicos.
- Tu correo y tus mensajes solo los ves tú y la persona con quien hablas.

Tus derechos
- Puedes cambiar tus datos o eliminar tu cuenta desde Ajustes.

Nunca vendemos tus datos.$_draft''';

const termsText = '''Términos y condiciones

- Debes tener al menos 18 años o permiso de tus padres.
- Publica solo prendas que te pertenezcan y descríbelas con honestidad.
- Está prohibido vender artículos falsificados, robados o ilegales.
- Los pagos se hacen dentro de La Percha para tener protección.
- Podemos retirar anuncios o cuentas que incumplan estas reglas.$_draft''';

const cookiesText = '''Cookies

La Percha usa almacenamiento en tu dispositivo solo para mantener tu sesión iniciada. No usamos cookies de publicidad.''';
