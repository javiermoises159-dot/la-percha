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
  <meta name="theme-color" content="#FFFFFF">
  <meta name="apple-mobile-web-app-title" content="Pavito">
  <meta name="description" content="Pavito: vende lo que ya no usas y compra con pago protegido en toda Venezuela.">
  <link rel="apple-touch-icon" href="icons/apple-touch-icon.png">
  <style>
    html,body{margin:0;height:100%;background:#FFFFFF}
    #splash{position:fixed;inset:0;display:flex;flex-direction:column;align-items:center;
      justify-content:center;background:#FFFFFF;z-index:9999;transition:opacity .35s;
      font-family:'Onest',system-ui,sans-serif;color:#161412}
    #splash.hide{opacity:0;pointer-events:none}
    #splash svg{width:88px;height:88px;animation:pop .6s ease-out both}
    #splash h1{margin:0 0 6px;font-size:40px;font-weight:800;letter-spacing:-1.6px;animation:pop .6s ease-out both}
    #splash p{margin:0;font:16px system-ui,sans-serif;color:#77716B}
    @keyframes pop{from{opacity:0;transform:scale(.85)}to{opacity:1;transform:scale(1)}}
  </style>
"""
s = s.replace("</head>", head_extra + "</head>", 1)
s = re.sub(r"<title>.*?</title>", "<title>Pavito</title>", s, flags=re.S)

splash = """<div id="splash">
  <h1>pavito<span style="color:#E0452C">.</span></h1>
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
    "background_color": "#FFFFFF",
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
