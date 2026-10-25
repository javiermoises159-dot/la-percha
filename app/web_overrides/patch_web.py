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
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Outfit:wght@700&display=swap">
  <meta name="theme-color" content="#C92A58">
  <meta name="apple-mobile-web-app-title" content="La Percha">
  <meta name="description" content="La Percha: compra y vende ropa usada en toda Venezuela.">
  <link rel="apple-touch-icon" href="icons/apple-touch-icon.png">
  <style>
    html,body{margin:0;height:100%;background:#F2F4F0}
    #splash{position:fixed;inset:0;display:flex;flex-direction:column;align-items:center;
      justify-content:center;background:#F2F4F0;z-index:9999;transition:opacity .35s;
      font-family:'Outfit',system-ui,sans-serif;color:#14201B}
    #splash.hide{opacity:0;pointer-events:none}
    #splash svg{width:88px;height:88px;animation:pop .6s ease-out both}
    #splash h1{margin:16px 0 4px;font-size:30px;font-weight:700;letter-spacing:-.4px}
    #splash p{margin:0;font:16px system-ui,sans-serif;color:#56655E}
    @keyframes pop{from{opacity:0;transform:scale(.85)}to{opacity:1;transform:scale(1)}}
  </style>
"""
s = s.replace("</head>", head_extra + "</head>", 1)
s = re.sub(r"<title>.*?</title>", "<title>La Percha</title>", s, flags=re.S)

splash = """<div id="splash">
  <svg viewBox="0 0 48 48" aria-hidden="true">
    <rect width="48" height="48" rx="13" fill="#C92A58"/>
    <g fill="none" stroke="#fff" stroke-width="2.9" stroke-linecap="round" stroke-linejoin="round">
      <path d="M24 16.8a4.4 4.4 0 1 0-4.4-4.4"/>
      <path d="M24 16.8v3.7L10.9 30.1l.6 3.5h25l.6-3.5L24 20.5"/>
    </g>
  </svg>
  <h1>La Percha</h1>
  <p>Dale otra vida a tu ropa</p>
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
    "name": "La Percha",
    "short_name": "La Percha",
    "description": "Compra y vende ropa usada en toda Venezuela.",
    "background_color": "#F2F4F0",
    "theme_color": "#C92A58",
    "lang": "es",
})
m["icons"] = [
    {"src": "icons/Icon-192.png", "sizes": "192x192", "type": "image/png"},
    {"src": "icons/Icon-512.png", "sizes": "512x512", "type": "image/png"},
    {"src": "icons/Icon-maskable-192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable"},
    {"src": "icons/Icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable"},
]
json.dump(m, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
