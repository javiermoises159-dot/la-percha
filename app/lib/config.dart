import 'package:supabase_flutter/supabase_flutter.dart';

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

/// Interruptor general de pagos: se abre desde Panel de administración → Pagos y cobro
/// (tabla config_app). Mientras esté cerrado, la app no deja comprar ni pagar destacados,
/// y el servidor también rechaza los pedidos.
bool get pagosAbiertos => ConfigApp.valor('pagos_abiertos') == 'true';

/// "Foto y listo" (la IA arma el anuncio con una foto). Apagado: se vende llenando los datos a mano.
/// Para activarlo hace falta una clave de Gemini con facturación en Supabase (GEMINI_API_KEY).
const iaActiva = false;

/// Datos de cobro de Pavito (donde pagan los compradores). Se cargan desde el panel
/// (Pagos y cobro). Vacío = ese método no se ofrece.
String get pagoMovilBanco => ConfigApp.valor('pm_banco');
String get pagoMovilCedula => ConfigApp.valor('pm_cedula');
String get pagoMovilTelefono => ConfigApp.valor('pm_telefono');
String get binancePayId => ConfigApp.valor('binance_id');
String get binancePayNombre => ConfigApp.valor('binance_nombre');
String get zinliCorreo => ConfigApp.valor('zinli_correo');
String get zinliNombre => ConfigApp.valor('zinli_nombre');

/// Ajustes públicos que el administrador cambia sin publicar otra versión de la app.
class ConfigApp {
  static Map<String, String> _v = {};
  static String valor(String k) => _v[k] ?? '';

  static Future<void> cargar() async {
    try {
      final r = await Supabase.instance.client.from('config_app').select('clave, valor');
      _v = {for (final x in r) '${x['clave']}': '${x['valor']}'};
    } catch (_) {/* sin conexión: pagos cerrados y sin datos */}
  }
}
