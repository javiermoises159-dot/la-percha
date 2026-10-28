#!/usr/bin/env python3
"""Genera los iconos de Pavito (guacamaya sobre amarillo) para web, Android y Play Store.

Uso: python3 tools/make_icons.py   (necesita playwright con Chromium)
"""
import asyncio
import pathlib
import re

from playwright.async_api import async_playwright

RAIZ = pathlib.Path(__file__).resolve().parent.parent
SVG = re.search(r"'''(.*?)'''", (RAIZ / "app/lib/logo.dart").read_text(), re.S).group(1).strip()
AMARILLO = "#F5B731"
WEB = RAIZ / "app/web_overrides/icons"
ANDROID = RAIZ / "app/android_icons"

# (archivo, tamaño, % del lado que ocupa la guacamaya, esquinas redondeadas)
# La guacamaya va "asomada": apoyada en el borde de abajo, con el cuerpo cortado por el borde.
SALIDAS = [
    (WEB / "Icon-192.png", 192, 0.84, True),
    (WEB / "Icon-512.png", 512, 0.84, True),
    (WEB / "Icon-maskable-192.png", 192, 0.74, False),
    (WEB / "Icon-maskable-512.png", 512, 0.74, False),
    (WEB / "apple-touch-icon.png", 180, 0.84, False),
    (WEB / "favicon.png", 64, 0.92, True),
    (ANDROID / "play-store-512.png", 512, 0.82, False),
]
for carpeta, lado in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
    SALIDAS.append((ANDROID / f"mipmap-{carpeta}/ic_launcher.png", lado, 0.82, True))
import os
if os.environ.get("PERFIL"):  # foto de perfil para redes (círculo)
    SALIDAS.append((pathlib.Path(os.environ["PERFIL"]), 1080, 0.80, False))


VISTA = "0 0 120 120"  # se recalcula con la caja real del dibujo (centrado óptico)


def html(lado, escala, redondo):
    radio = f"{int(lado * 0.22)}px" if redondo else "0"
    m = int(lado * escala)
    svg = re.sub(r'viewBox="[^"]*"', f'viewBox="{VISTA}"', SVG, count=1)
    return (f"<html><body style='margin:0;background:transparent'>"
            f"<div style='width:{lado}px;height:{lado}px;background:{AMARILLO};border-radius:{radio};"
            f"display:flex;justify-content:center;align-items:flex-end;overflow:hidden'>"
            f"<div style='width:{m}px;height:{m}px;flex:none;margin-bottom:-{m * 0.07:.1f}px;margin-left:{m * 0.06:.1f}px'>{svg.replace('<svg ', f'<svg width=\"{m}\" height=\"{m}\" ', 1)}</div>"
            f"</div></body></html>")


async def medir(b):
    """Caja real del dibujo (incluye el contorno) para centrarlo de verdad."""
    global VISTA
    pg = await b.new_page()
    await pg.set_content(f"<html><body>{SVG}</body></html>")
    x, y, w, h = await pg.evaluate("""() => { const g = document.querySelector('svg');
        const r = g.getBBox(); return [r.x - 2, r.y - 2, r.width + 4, r.height + 4]; }""")
    lado = max(w, h)
    VISTA = f"{x - (lado - w) / 2:.1f} {y - (lado - h) / 2:.1f} {lado:.1f} {lado:.1f}"
    print("caja del dibujo:", VISTA)
    await pg.close()


async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch()
        await medir(b)
        for ruta, lado, escala, redondo in SALIDAS:
            ruta.parent.mkdir(parents=True, exist_ok=True)
            pg = await b.new_page(viewport={"width": lado, "height": lado})
            await pg.set_content(html(lado, escala, redondo))
            await pg.screenshot(path=str(ruta), omit_background=True,
                                clip={"x": 0, "y": 0, "width": lado, "height": lado})
            await pg.close()
            print("ok", ruta.name)
        await b.close()

asyncio.run(main())
