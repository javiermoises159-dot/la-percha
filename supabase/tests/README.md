# Pruebas de seguridad de la base de datos

`ataques.sql` intenta los abusos típicos (pagar menos, vender dos veces, ver datos
ajenos, hacerse admin, falsificar mensajes...) y comprueba que el servidor los bloquea.

Cómo correrlas en un PostgreSQL vacío (no en el de producción):

```
psql -d prueba -f supabase/tests/supabase_stub.sql
for f in supabase/migrations/*.sql; do psql -d prueba -v ON_ERROR_STOP=1 -f $f; done
psql -d prueba -f supabase/tests/ataques.sql
```

Cada línea `ERROR` de la salida es un ataque bloqueado; los pasos "ok" no deben dar error.
