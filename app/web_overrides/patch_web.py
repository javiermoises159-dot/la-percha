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
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Onest:wght@600;800&display=swap">
  <meta name="theme-color" content="#E0452C">
  <meta name="apple-mobile-web-app-title" content="Pavito">
  <meta name="description" content="Pavito: vende lo que ya no usas y compra con pago protegido en toda Venezuela.">
  <link rel="apple-touch-icon" href="icons/apple-touch-icon.png">
  <style>html,body{margin:0;height:100%;background:#E0452C}</style>
"""
# Quita las etiquetas de fábrica de Flutter ("A new Flutter project.") antes de poner las nuestras.
s = re.sub(r'\s*<meta name="description"[^>]*>', '', s)
s = re.sub(r'\s*<meta name="apple-mobile-web-app-title"[^>]*>', '', s)
# Vista previa al compartir el link (WhatsApp, Instagram, Telegram, Facebook, X).
head_extra += '''
  <script src="push.js" defer></script>
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Pavito">
  <meta property="og:title" content="Pavito · Compra y vende en toda Venezuela">
  <meta property="og:description" content="Lo que ya no usas, otra persona lo quiere. Tu pago queda protegido hasta que lo recibes. Vender es gratis.">
  <meta property="og:image" content="https://pavito.app/compartir.jpg">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:url" content="https://pavito.app/">
  <meta property="og:locale" content="es_VE">
  <meta name="twitter:card" content="summary_large_image">
'''
s = s.replace("</head>", head_extra + "</head>", 1)
s = re.sub(r"<title>.*?</title>", "<title>Pavito</title>", s, flags=re.S)

import os
splash = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "splash.html"), encoding="utf-8").read()
s = re.sub(r"(<body[^>]*>)", r"\1\n" + splash.replace("\\", "\\\\"), s, count=1)
instalar = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "instalar.html"), encoding="utf-8").read()
s = s.replace("</body>", instalar + "\n</body>", 1)
captcha = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "captcha.html"), encoding="utf-8").read()
s = s.replace("</body>", captcha + "\n</body>", 1)
open(p, "w", encoding="utf-8").write(s)

# ---- manifest.json: nombre, colores e iconos ----
p = f"{web}/manifest.json"
m = json.load(open(p, encoding="utf-8"))
m.update({
    "name": "Pavito",
    "short_name": "Pavito",
    "description": "Compra y vende ropa usada en toda Venezuela.",
    "background_color": "#E0452C",
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
