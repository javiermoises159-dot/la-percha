# Lista de seguridad de La Percha

Marca cada punto cuando lo hagas. Están ordenados por importancia.

## 1. Tus cuentas (lo que más pueden atacar)
- [ ] Activar verificación en dos pasos (2FA) en **GitHub**, **Supabase**, **Cloudflare**, **Codemagic** y tu **correo de Google**. Es la defensa más importante: quien entre a una de esas cuentas controla la app.
- [ ] Usar una contraseña distinta y larga en cada una (un gestor de contraseñas o el llavero del iPhone).
- [ ] Guardar la contraseña de la base de datos de Supabase en un lugar seguro (no en el chat ni en el repositorio).
- [ ] Nunca compartir las claves **service_role** ni **secret**. Solo la clave **publishable** puede ir dentro de la app.

## 2. Supabase (Authentication y Project Settings)
- [ ] Ejecutar `supabase/migrations/0002_hardening.sql` en SQL Editor.
- [ ] Authentication → Sign In / Providers → Email: **Confirm email** encendido (antes del lanzamiento público).
- [ ] Authentication → mínimo de contraseña: 8 o más; si el plan lo permite, activar la protección contra contraseñas filtradas.
- [ ] Authentication → Attack Protection: activar **CAPTCHA** (Cloudflare Turnstile, gratis) para frenar cuentas falsas.
- [ ] Authentication → Rate Limits: dejar los límites por defecto o más estrictos.
- [ ] Project Settings → activar **copias de seguridad** (Database → Backups) cuando haya usuarios reales; el plan gratuito no las incluye, el de pago sí.
- [ ] Tu cuenta de administrador: en SQL Editor, `update public.profiles set is_admin = true where username = 'TU_USUARIO';`

## 3. GitHub
- [ ] Settings → Code security: activar **Secret scanning** y **Push protection** (avisan si subes una clave por error) y **Dependabot alerts**.
- [ ] Settings → Branches: proteger la rama `main` (exigir revisión antes de cambios cuando haya más personas).
- [ ] Nunca subir contraseñas ni claves secretas al repositorio (es público).

## 4. Cloudflare (protección contra ataques que tumban la web)
- [ ] Cloudflare ya filtra ataques de saturación (DDoS) en tu página.
- [ ] Cuando tengas dominio propio: SSL/TLS en modo **Full (strict)**, **Always Use HTTPS** y **Bot Fight Mode** activados.
- [ ] Probar las cabeceras de seguridad (`app/web_overrides/_headers`): la política de contenido (CSP) está en modo de prueba; cuando confirmemos que no rompe nada, se pasa a modo estricto.

## 5. Antes de recibir dinero de verdad
- [ ] Consultar al contador o abogado (`docs/preguntas-contador.md`).
- [ ] Redactar con el abogado los términos y la política de privacidad definitivos (los actuales son borradores).
- [ ] Probar los pedidos y pagos con montos mínimos y personas de confianza.
- [ ] Verificar los pagos Pago Móvil a mano antes de pasar un pedido a "retenido".

## Qué protege ya el código (sin que hagas nada)
- Cada usuario solo ve sus datos privados, chats y pedidos (reglas por fila en el servidor).
- Nadie puede inventar precios, comisiones ni marcar pagos como recibidos.
- Límites contra spam: 30 anuncios al día, 20 mensajes por minuto, 10 pedidos por hora.
- Usuarios bloqueados no pueden publicar, escribir ni comprar.
- Las fotos solo pueden venir de la carpeta del propio vendedor, de máximo 5 MB.
- Historial de cada pedido para resolver disputas.
- Cada usuario puede eliminar su cuenta desde Ajustes.
