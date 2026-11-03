// Pavito — función "correo": manda por email un aviso de pedido recién creado.
// La llama la base de datos (solo con el número del aviso y la clave interna, igual que "push").
// Necesita el secreto RESEND_API_KEY en Supabase. Sin él no hace nada.
const SITIO = "https://pavito.app";
const DE = "Pavito <hola@pavito.app>";

function respuesta(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
function iguales(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}
function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return respuesta(405, { error: "Solo POST" });
  const url = Deno.env.get("SUPABASE_URL");
  const servicio = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resend = Deno.env.get("RESEND_API_KEY");
  if (!url || !servicio) return respuesta(503, { error: "Falta configuración" });
  if (!resend) return respuesta(200, { enviado: 0, motivo: "sin RESEND_API_KEY" });

  const hs = { apikey: servicio, Authorization: `Bearer ${servicio}` };
  const dada = req.headers.get("x-push-secret") ?? "";
  const fila = await fetch(`${url}/rest/v1/secretos?clave=eq.push&select=valor`, { headers: hs })
    .then((r) => r.json()).catch(() => []);
  const real = Array.isArray(fila) && fila[0] ? String(fila[0].valor) : "";
  if (!dada || !real || !iguales(dada, real)) return respuesta(401, { error: "No autorizado" });

  let id = 0;
  try { id = Number((await req.json())?.aviso); } catch { /* cuerpo no válido */ }
  if (!Number.isInteger(id) || id <= 0) return respuesta(400, { error: "Aviso no válido" });

  const avisos = await fetch(`${url}/rest/v1/avisos?id=eq.${id}&select=user_id,texto,tipo`, { headers: hs })
    .then((r) => r.json()).catch(() => []);
  const aviso = Array.isArray(avisos) ? avisos[0] : null;
  if (!aviso || aviso.tipo !== "pedido") return respuesta(200, { enviado: 0 });

  const usuario = await fetch(`${url}/auth/v1/admin/users/${aviso.user_id}`, { headers: hs })
    .then((r) => r.json()).catch(() => null);
  const correo = usuario?.email ? String(usuario.email) : "";
  if (!correo) return respuesta(200, { enviado: 0 });

  const texto = esc(String(aviso.texto));
  const html = `<div style="font-family:Arial,sans-serif;max-width:480px;margin:auto;padding:24px">
<h2 style="margin:0 0 12px;color:#1B1B1F">Pavito</h2>
<p style="font-size:17px;line-height:1.4;color:#1B1B1F">${texto}</p>
<p><a href="${SITIO}/?abrir=avisos" style="display:inline-block;background:#EDB132;color:#1B1B1F;font-weight:bold;text-decoration:none;padding:12px 22px;border-radius:12px">Abrir Pavito</a></p>
<p style="font-size:12px;color:#777">Recibes este correo porque tienes un pedido en Pavito. Si tienes dudas escribe a soporte@pavito.app</p></div>`;
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${resend}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: DE, to: [correo], subject: "Novedad en tu pedido de Pavito", html }),
  });
  return respuesta(200, { enviado: r.ok ? 1 : 0 });
});
