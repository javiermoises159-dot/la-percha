"""Ajusta web/index.html y web/manifest.json generados por Flutter."""
import json
import re
import sys

web = sys.argv[1]

# ---- index.html: título, colores, iconos y pantalla de carga ----
p = f"{web}/index.html"
s = open(p, encoding="utf-8").read()

head_extra = """
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Onest:wght@800&display=swap">
  <meta name="theme-color" content="#F5B731">
  <meta name="apple-mobile-web-app-title" content="Pavito">
  <meta name="description" content="Pavito: vende lo que ya no usas y compra con pago protegido en toda Venezuela.">
  <link rel="apple-touch-icon" href="icons/apple-touch-icon.png">
  <style>
    html,body{margin:0;height:100%;background:#F5B731}
    #splash{position:fixed;inset:0;display:flex;flex-direction:column;align-items:center;
      justify-content:center;background:#F5B731;z-index:9999;transition:opacity .35s;
      font-family:'Onest',system-ui,sans-serif;color:#161412}
    #splash.hide{opacity:0;pointer-events:none}
    #splash svg{width:88px;height:88px;animation:pop .6s ease-out both}
    #splash svg{animation:pop .6s ease-out both}
    #splash h1{margin:10px 0 6px;font-size:40px;font-weight:800;letter-spacing:-1.6px;animation:pop .6s ease-out both}
    #splash p{margin:0;font:600 16px system-ui,sans-serif;color:#161412;opacity:.75}
    @keyframes pop{from{opacity:0;transform:scale(.85)}to{opacity:1;transform:scale(1)}}
  </style>
"""
s = s.replace("</head>", head_extra + "</head>", 1)
s = re.sub(r"<title>.*?</title>", "<title>Pavito</title>", s, flags=re.S)

splash = """<div id="splash">
  <svg width="96" height="96" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">
  <g stroke="#161412" stroke-width="4" stroke-linejoin="round" stroke-linecap="round">
    <path d="M44 76c2 18 10 32 22 42h44c4-26-2-50-18-66" fill="#E0452C"/>
    <circle cx="72" cy="50" r="32" fill="#E0452C"/>
    <path d="M86 78c14 6 22 20 24 40H94c0-16-4-28-8-40z" fill="#F5B731"/>
    <path d="M99 94c6 6 10 14 11 24h-8c0-9-1-17-3-24z" fill="#1F5FBF"/>
    <path d="M48 40c6-10 20-12 28-5 8 8 7 22-2 28-9 6-21 4-27-4-4-6-3-13 1-19z" fill="#fff"/>
    <path d="M50 34C32 28 15 38 14 58c0 10 4 18 11 24-1-10 3-18 12-21l13-1z" fill="#F2E4CC"/>
    <path d="M37 61c-6 4-7 13-2 19 7-1 13-7 14-17z" fill="#161412"/>
  </g>
  <circle cx="64" cy="46" r="5" fill="#161412"/><circle cx="65.5" cy="44.5" r="1.5" fill="#fff"/>
</svg>
  <h1>pavito</h1>
  <p>Vende lo que ya no usas</p>
</div>
<script>
  (function () {
    function hide() {
      var el = document.getElementById('splash');
      if (!el) return;
      el.classList.add('hide');
      setTimeout(function () { el.remove(); }, 400);
    }
    window.addEventListener('flutter-first-frame', hide);
    setTimeout(hide, 15000);
  })();
</script>
"""
s = re.sub(r"(<body[^>]*>)", r"\1\n" + splash.replace("\\", "\\\\"), s, count=1)
open(p, "w", encoding="utf-8").write(s)

# ---- manifest.json: nombre, colores e iconos ----
p = f"{web}/manifest.json"
m = json.load(open(p, encoding="utf-8"))
m.update({
    "name": "Pavito",
    "short_name": "Pavito",
    "description": "Compra y vende ropa usada en toda Venezuela.",
    "background_color": "#F5B731",
    "theme_color": "#FFFFFF",
    "lang": "es",
})
m["icons"] = [
    {"src": "icons/Icon-192.png", "sizes": "192x192", "type": "image/png"},
    {"src": "icons/Icon-512.png", "sizes": "512x512", "type": "image/png"},
    {"src": "icons/Icon-maskable-192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable"},
    {"src": "icons/Icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable"},
]
json.dump(m, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
