# Cómo confirmar un pago (por ahora a mano)

1. Revisa en tu banco que llegó el Pago Móvil con la referencia que escribió el comprador.
2. Supabase → Table Editor → tabla `orders`.
3. Busca el pedido en estado `revision` (la columna `pay_ref` trae la referencia).
4. Cambia `status` a `retenido` y guarda.
5. El vendedor ya puede enviar. Cuando el comprador confirma, el pedido pasa a `liberado` y tú pagas al vendedor por Pago Móvil.

Si el pago no llegó: cambia `status` a `cancelado`.
También puedes hacerlo desde la app: Perfil → Panel de administración.

## Lo que el servidor hace solo (cada 15 minutos)
- Pedido **sin pagar en 24 h** → se cancela y la prenda vuelve a la venta.
- Pedido **enviado hace 7 días sin queja** → se libera; ya puedes pagar al vendedor.
- **30 días** después de terminar un pedido se borra la dirección del comprador.

Requiere la extensión **pg_cron** (Supabase → Database → Extensions → pg_cron → Enable).
Si estaba apagada, actívala y vuelve a ejecutar la migración `0006_seguridad_pedidos.sql`.

## Reglas que el servidor impone
- El precio del pedido es siempre el del anuncio; nadie puede pagar menos.
- Una prenda solo puede tener un pedido vivo; al pedirla queda reservada.
- Una referencia de Pago Móvil no se puede usar en dos pedidos.
- El vendedor ve teléfono y dirección del comprador solo después de confirmar el pago.
