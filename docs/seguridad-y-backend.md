# Pavito: seguridad y servidor (Supabase)

## Qué guardamos y quién lo ve
| Dato | Dónde | Quién lo ve |
|---|---|---|
| Nombre de usuario, ciudad, calificación | `profiles` | Todos |
| Teléfono, cuenta de cobro, dirección de entrega | `private_profiles` | Solo el dueño y el administrador |
| Anuncios y fotos | `listings`, Storage | Todos (solo el dueño los edita) |
| Chats y ofertas | `threads` | Solo comprador y vendedor |
| Pedidos y pagos | `orders` | Solo comprador, vendedor y administrador |
| Favoritos | `favorites` | Solo el dueño |

## Defensas
1. **Entrada con correo** (Supabase Auth, gratis). El SMS con teléfono se añade después, porque requiere un proveedor de pago (Twilio u otro).
2. **Reglas del servidor (Row Level Security)** (`supabase/migrations/0001_init.sql`): el filtro vive en el servidor, no en la app. Aunque alguien modifique la app, no puede leer pedidos ajenos, inventar precios, calificarse a sí mismo ni marcar un pago como recibido.
3. **El dinero lo mueve solo el administrador**: el comprador avisa que pagó, el administrador verifica el Pago Móvil y pasa el pedido a "retenido"; al confirmar el comprador la recepción, el administrador paga al vendedor.
4. **Sin claves en el repositorio**: las claves de Binance Pay y cualquier secreto van en el servidor, nunca en el código ni en GitHub (el repositorio es público).
5. **App Check** (más adelante): rechaza peticiones que no vengan de la app oficial.
6. **Fotos**: solo imágenes, máximo 5 MB, cada usuario solo en su carpeta.
7. **Moderación**: botón de denuncia, y el administrador puede ocultar anuncios y bloquear usuarios.
8. **Copias de seguridad** programadas de la base de datos.

## Límites actuales y pendientes
- Verificar el pago Pago Móvil a mano al principio. Automatizarlo requiere un servicio con API bancaria, o confirmación por SMS del banco.
- Retener dinero de terceros puede exigir permisos o una figura legal: ver `docs/preguntas-contador.md`.
- Supabase tiene plan gratis (sin tarjeta) con base de datos, fotos y usuarios suficientes para empezar. Se pausa tras una semana sin uso, y para producción conviene el plan de pago (unos 25 USD al mes).
- Política de privacidad y términos de uso: redactar con el abogado.
- Una cuenta de administrador se marca con un permiso especial (`is_admin`) que solo se asigna desde el panel de Supabase.


## Endurecimiento (0002)
Ver `supabase/migrations/0002_hardening.sql` y `docs/seguridad-checklist.md`.
