# Cómo confirmar un pago (por ahora a mano)

1. Revisa en tu banco que llegó el Pago Móvil con la referencia que escribió el comprador.
2. Supabase → Table Editor → tabla `orders`.
3. Busca el pedido en estado `revision` (la columna `pay_ref` trae la referencia).
4. Cambia `status` a `retenido` y guarda.
5. El vendedor ya puede enviar. Cuando el comprador confirma, el pedido pasa a `liberado` y tú pagas al vendedor por Pago Móvil.

Si el pago no llegó: cambia `status` a `cancelado`.
Más adelante esto se automatiza o se hace desde un panel de administración.
