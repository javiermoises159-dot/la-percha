/// Conexión con el servidor (Supabase).
/// Esta clave "publishable" es pública por diseño: la seguridad la imponen
/// las reglas de la base de datos (supabase/migrations/0001_init.sql).
/// NUNCA poner aquí la clave service_role ni ninguna "secret".
const supabaseUrl = 'https://udhyuyokrxggdnnepbmr.supabase.co';
const supabaseKey = 'sb_publishable_PFt4DdXlWbQEvyEgP58BZQ_CKXaoHGG';

/// Cloudflare Turnstile (anti-bots). Esta "Site Key" es pública. Vacía = desactivado.
/// Ponerla ANTES de activar CAPTCHA en Supabase (Authentication → Attack Protection).
const turnstileSiteKey = '0x4AAAAAAFoRRXPnmlkb5ipJ';

/// Dirección pública de la web (la usa Android para la comprobación anti-bots).
/// Su dominio debe estar en la lista de "Hostnames" del widget de Turnstile.
const webBase = 'https://pavito.app';

/// Clave PÚBLICA de las notificaciones (Web Push). La privada vive solo en Supabase.
const vapidPublica = 'BHtmdF5vFPfoNDVd9Q3ZZd_BpDSiPX3Ucq5POaaPnue6QFOtQKx7qfpuf1gkpc9ddRBGasF0I3LO2U9AQSrWw40';

/// Interruptor general de pagos. Mientras sea false, la app no deja comprar ni pagar
/// destacados y muestra "Estamos en fase de prueba". Ponlo en true SOLO cuando haya
/// al menos un método de pago con datos REALES abajo.
const pagosAbiertos = false;

/// "Foto y listo" (la IA arma el anuncio con una foto). Apagado: se vende llenando los datos a mano.
/// Para activarlo hace falta una clave de Gemini con facturación en Supabase (GEMINI_API_KEY).
const iaActiva = false;

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
