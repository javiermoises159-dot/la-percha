# Copia de seguridad de Pavito

Cada día GitHub hace una copia cifrada de la base de datos (usuarios, anuncios, pedidos,
saldos, chats). Se guardan las de los últimos 30 días en **Actions → Copia de seguridad**.
Las fotos no van en la copia (están en Supabase Storage).

## Recuperar una copia
1. Descarga el archivo `pavito-AAAA-MM-DD.dump.gpg` desde Actions.
2. Descifra: `gpg -d pavito-AAAA-MM-DD.dump.gpg > pavito.dump` (pide tu COPIA_CLAVE).
3. Restaura (mejor en un proyecto nuevo de Supabase):
   `pg_restore --no-owner --no-privileges -d "<cadena del proyecto>" pavito.dump`

Sin la COPIA_CLAVE la copia no se puede abrir: guárdala en un lugar seguro.
