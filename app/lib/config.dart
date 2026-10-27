/// Conexión con el servidor (Supabase).
/// Esta clave "publishable" es pública por diseño: la seguridad la imponen
/// las reglas de la base de datos (supabase/migrations/0001_init.sql).
/// NUNCA poner aquí la clave service_role ni ninguna "secret".
const supabaseUrl = 'https://udhyuyokrxggdnnepbmr.supabase.co';
const supabaseKey = 'sb_publishable_PFt4DdXlWbQEvyEgP58BZQ_CKXaoHGG';

/// Datos de Pago Móvil de Pavito, donde pagan los compradores.
/// OJO: son datos de EJEMPLO. Cámbialos por los reales antes de recibir pagos.
const pagoMovilBanco = '0102 - Banco de Venezuela (ejemplo)';
const pagoMovilCedula = 'J-00000000-0 (ejemplo)';
const pagoMovilTelefono = '0412-0000000 (ejemplo)';

/// Cobro en dólares, sin cuenta bancaria en Venezuela.
/// Deja el texto vacío ('') para ocultar ese método en la app.
/// OJO: son datos de EJEMPLO. Cámbialos por los reales antes de recibir pagos.
const binancePayId = '000000000 (ejemplo)'; // Binance → Pay → Recibir → "Pay ID"
const binancePayNombre = 'Pavito (ejemplo)';
const zinliCorreo = 'pagos@ejemplo.com'; // correo de tu cuenta Zinli
const zinliNombre = 'Pavito (ejemplo)';
