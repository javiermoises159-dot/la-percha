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
SALIDAS = [
    (WEB / "Icon-192.png", 192, 0.84, True),
    (WEB / "Icon-512.png", 512, 0.84, True),
    (WEB / "Icon-maskable-192.png", 192, 0.64, False),
    (WEB / "Icon-maskable-512.png", 512, 0.64, False),
    (WEB / "apple-touch-icon.png", 180, 0.80, False),
    (WEB / "favicon.png", 64, 0.92, True),
    (ANDROID / "play-store-512.png", 512, 0.80, False),
]
for carpeta, lado in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
    SALIDAS.append((ANDROID / f"mipmap-{carpeta}/ic_launcher.png", lado, 0.80, True))


def html(lado, escala, redondo):
    radio = f"{int(lado * 0.22)}px" if redondo else "0"
    m = int(lado * escala)
    return (f"<html><body style='margin:0;background:transparent'>"
            f"<div style='width:{lado}px;height:{lado}px;background:{AMARILLO};border-radius:{radio};"
            f"display:grid;place-items:center'>"
            f"<div style='width:{m}px;height:{m}px'>{SVG.replace('<svg ', f'<svg width=\"{m}\" height=\"{m}\" ', 1)}</div>"
            f"</div></body></html>")


async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch()
        for ruta, lado, escala, redondo in SALIDAS:
            ruta.parent.mkdir(parents=True, exist_ok=True)
            pg = await b.new_page(viewport={"width": lado, "height": lado})
            await pg.set_content(html(lado, escala, redondo))
            await pg.screenshot(path=str(ruta), omit_background=True,
                                clip={"x": 0, "y": 0, "width": lado, "height": lado})
            await pg.close()
            print("ok", ruta.relative_to(RAIZ))
        await b.close()

asyncio.run(main())
