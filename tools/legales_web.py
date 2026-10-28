#!/usr/bin/env python3
"""Genera app/web_overrides/static/{terminos,privacidad}/index.html desde app/lib/terminos.dart."""
import re, html, pathlib
R = pathlib.Path(__file__).resolve().parent.parent
src = (R/"app/lib/terminos.dart").read_text(encoding="utf-8")
md = re.search(r"r'''(.*?)'''", src, re.S).group(1)
for a, b in [("[razón social], RIF [RIF], con domicilio en [dirección]", "el equipo de Pavito"),
             ("[razón social]", "Pavito"),
             ("[correo de soporte] · [teléfono o WhatsApp oficial de soporte]", "soporte@pavito.app"),
             ("[correo de soporte]", "soporte@pavito.app"),
             ("[ciudad]", "Venezuela")]:
    md = md.replace(a, b)

def inline(t):
    t = html.escape(t)
    return re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)

def render(lines):
    out, lst, tbl = [], None, []
    def cierra():
        nonlocal lst, tbl
        if lst: out.append(f"</{lst}>"); lst = None
        if tbl:
            rows = [r for r in tbl if not re.match(r"^\|\s*-", r)]
            out.append("<div class='t'><table>")
            for i, r in enumerate(rows):
                c = [x.strip() for x in r.strip().strip("|").split("|")]
                tag = "th" if i == 0 else "td"
                out.append("<tr>" + "".join(f"<{tag}>{inline(x)}</{tag}>" for x in c) + "</tr>")
            out.append("</table></div>"); tbl = []
    for l in lines:
        s = l.rstrip()
        if s.startswith("|"): 
            if lst: out.append(f"</{lst}>"); lst = None
            tbl.append(s); continue
        cierra()
        m = re.match(r"^(\s*)(\d+\.|-)\s+(.*)", s)
        if m:
            tipo = "ol" if m.group(2)[0].isdigit() else "ul"
            if lst != tipo:
                if lst: out.append(f"</{lst}>")
                out.append(f"<{tipo}>"); lst = tipo
            out.append(f"<li>{inline(m.group(3))}</li>"); continue
        if lst: out.append(f"</{lst}>"); lst = None
        if s.startswith("### "): out.append(f"<h3>{inline(s[4:])}</h3>")
        elif s.startswith("## "): out.append(f"<h2>{inline(s[3:])}</h2>")
        elif s.strip(): out.append(f"<p>{inline(s)}</p>")
    cierra()
    return "\n".join(out)

CSS = """html{color-scheme:light}body{margin:0;background:#FFFAF5;color:#1C1411;font:16px/1.6 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;padding:max(16px,env(safe-area-inset-top,0px)) max(16px,env(safe-area-inset-right,0px)) 40px max(16px,env(safe-area-inset-left,0px))}
main{max-width:720px;margin:0 auto}h1{font-size:28px;margin:24px 0 4px}h2{font-size:20px;margin:28px 0 8px;color:#C9381F}h3{font-size:17px}a{color:#C9381F}
.t{overflow-x:auto}table{border-collapse:collapse;font-size:14px}th,td{border:1px solid #F0E3D8;padding:6px 8px;text-align:left;vertical-align:top}th{background:#FBEFE3}
nav{display:flex;gap:16px;flex-wrap:wrap;font-size:14px}footer{margin-top:32px;font-size:14px;color:#7A6E66}"""

def pagina(carpeta, titulo, cuerpo):
    d = R/"app/web_overrides/static"/carpeta; d.mkdir(parents=True, exist_ok=True)
    (d/"index.html").write_text(f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{titulo} · Pavito</title><meta name="robots" content="index,follow"><link rel="icon" href="/favicon.png">
<style>{CSS}</style></head><body><main>
<nav><a href="https://pavito.app/inicio/">Pavito</a><a href="/terminos/">Términos y condiciones</a><a href="/privacidad/">Política de privacidad</a></nav>
<h1>{titulo}</h1>
{cuerpo}
<footer>Pavito · https://pavito.app</footer></main></body></html>
""", encoding="utf-8")

partes = re.split(r"(?m)^(?=## )", md)
intro, secs = partes[0], partes[1:]
priv = next(s for s in secs if s.startswith("## 10."))
priv_extra = ("\nEsta política describe qué datos guarda Pavito. Si inicias sesión con Google, solo recibimos tu nombre, "
              "tu correo y tu foto de perfil de Google para crear tu cuenta; no accedemos a tus contactos ni a otros datos de tu cuenta de Google.\n")
pagina("terminos", "Términos y condiciones", render((intro + "".join(secs)).splitlines()))
pagina("privacidad", "Política de privacidad", render((priv_extra + priv.replace("## 10. Tus datos", "## Tus datos")).splitlines()))
print("ok")
