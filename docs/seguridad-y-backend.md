# La Percha: seguridad y servidor

## Qué guardamos y quién lo ve
| Dato | Dónde | Quién lo ve |
|---|---|---|
| Nombre de usuario, ciudad, calificación | `users/{id}` | Todos |
| Teléfono, cuenta de cobro, dirección de entrega | `users/{id}/private` | Solo el dueño y el administrador |
| Anuncios y fotos | `listings`, Storage | Todos (solo el dueño los edita) |
| Chats y ofertas | `threads` | Solo comprador y vendedor |
| Pedidos y pagos | `orders` | Solo comprador, vendedor y administrador |
| Favoritos | `users/{id}/favs` | Solo el dueño |

## Defensas
1. **Entrada con SMS** (Firebase Auth): una cuenta = un teléfono real.
2. **Reglas del servidor** (`backend/firestore.rules`): el filtro vive en el servidor, no en la app. Aunque alguien modifique la app, no puede leer pedidos ajenos, inventar precios, calificarse a sí mismo ni marcar un pago como recibido.
3. **El dinero lo mueve solo el administrador**: el comprador avisa que pagó, el administrador verifica el Pago Móvil y pasa el pedido a "retenido"; al confirmar el comprador la recepción, el administrador paga al vendedor.
4. **Sin claves en el repositorio**: las claves de Binance Pay y cualquier secreto van en el servidor, nunca en el código ni en GitHub (el repositorio es público).
5. **App Check** (más adelante): rechaza peticiones que no vengan de la app oficial.
6. **Fotos**: solo imágenes, máximo 5 MB, cada usuario solo en su carpeta.
7. **Moderación**: botón de denuncia, y el administrador puede ocultar anuncios y bloquear usuarios.
8. **Copias de seguridad** programadas de la base de datos.

## Límites actuales y pendientes
- Verificar el pago Pago Móvil a mano al principio. Automatizarlo requiere un servicio con API bancaria, o confirmación por SMS del banco.
- Retener dinero de terceros puede exigir permisos o una figura legal: ver `docs/preguntas-contador.md`.
- Las funciones automáticas del servidor (avisos, liberación de pagos) necesitan el plan de pago de Firebase (Blaze). Lo mínimo para empezar (login, base de datos, reglas) funciona sin cobrar, pero las fotos y los SMS de más de unos pocos al día piden tarjeta.
- Política de privacidad y términos de uso: redactar con el abogado.
- Una cuenta de administrador se marca con un permiso especial (`admin`) que solo se asigna desde la consola de Firebase.
