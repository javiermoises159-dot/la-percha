// Pavito — función "push": envía al teléfono un aviso recién creado.
// La llama la base de datos (solo con el número del aviso). La función lee el aviso con
// permisos de servidor, lo envía una sola vez y borra los dispositivos que ya no existen.
// La clave privada VAPID vive SOLO aquí, como secreto de Supabase (VAPID_PRIVATE_KEY).
import webpush from "npm:web-push@3.6.7";

const VAPID_PUBLICA = "BHtmdF5vFPfoNDVd9Q3ZZd_BpDSiPX3Ucq5POaaPnue6QFOtQKx7qfpuf1gkpc9ddRBGasF0I3LO2U9AQSrWw40";
const SITIO = "https://pavito.app";

function respuesta(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

// Comparación que no revela, por el tiempo que tarda, cuántas letras acertó quien adivina.
function iguales(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return respuesta(405, { error: "Solo POST" });
  const url = Deno.env.get("SUPABASE_URL");
  const servicio = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const privada = Deno.env.get("VAPID_PRIVATE_KEY");
  if (!url || !servicio || !privada) return respuesta(503, { error: "Falta configuración" });

  // Solo la base de datos de Pavito puede llamar a esta función (lleva una clave interna).
  const dada = req.headers.get("x-push-secret") ?? "";
  const hs = { apikey: servicio, Authorization: `Bearer ${servicio}` };
  const filaClave = await fetch(`${url}/rest/v1/secretos?clave=eq.push&select=valor`, { headers: hs })
    .then((r) => r.json()).catch(() => []);
  const real = Array.isArray(filaClave) && filaClave[0] ? String(filaClave[0].valor) : "";
  if (!dada || !real || !iguales(dada, real)) return respuesta(401, { error: "No autorizado" });

  let id = 0;
  try {
    id = Number((await req.json())?.aviso);
  } catch { /* cuerpo no válido */ }
  if (!Number.isInteger(id) || id <= 0) return respuesta(400, { error: "Aviso no válido" });

  const h = { apikey: servicio, Authorization: `Bearer ${servicio}`, "Content-Type": "application/json" };
  // Toma el aviso solo si ese texto aún no se envió: aunque llegue dos veces, la segunda no hace nada.
  const tomado = await fetch(`${url}/rest/v1/rpc/push_tomar`, { method: "POST", headers: h, body: JSON.stringify({ p_aviso: id }) });
  const filas = await tomado.json().catch(() => []);
  const aviso = Array.isArray(filas) ? filas[0] : null;
  if (!aviso) return respuesta(200, { enviado: 0 });

  const subs = await (await fetch(`${url}/rest/v1/push_subs?user_id=eq.${aviso.user_id}&select=id,endpoint,p256dh,auth`, { headers: h })).json();
  webpush.setVapidDetails(SITIO, Deno.env.get("VAPID_PUBLIC_KEY") ?? VAPID_PUBLICA, privada);
  const destino = aviso.tipo === "anuncio" && aviso.ref_id ? `/a/${aviso.ref_id}` : "/?abrir=avisos";
  const carga = JSON.stringify({ title: "Pavito", body: String(aviso.texto).slice(0, 180), url: destino, tag: `${aviso.tipo}-${aviso.ref_id ?? id}` });

  let enviados = 0;
  for (const s of Array.isArray(subs) ? subs : []) {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, carga, { TTL: 86400 });
      enviados++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) {
        await fetch(`${url}/rest/v1/push_subs?id=eq.${s.id}`, { method: "DELETE", headers: h });
      }
    }
  }
  return respuesta(200, { enviado: enviados });
});
