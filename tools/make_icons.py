"""Genera los iconos PNG de La Percha (logo de la percha sobre fondo frambuesa)."""
from PIL import Image, ImageDraw
import sys

BG = (201, 42, 88)
FG = (255, 255, 255)
S = 4  # supersampling


def hanger(draw, k, ox, oy, w):
    """Dibuja la percha. k = píxeles por unidad (48 unidades), (ox, oy) = origen."""
    def P(x, y):
        return (ox + x * k, oy + y * k)

    def line(points):
        for a, b in zip(points, points[1:]):
            draw.line([P(*a), P(*b)], fill=FG, width=int(w))
        for pt in points:
            x, y = P(*pt)
            draw.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=FG)

    # gancho: arco que sube desde el cuello y se curva a la izquierda
    import math
    pts = [(24 + 4.4 * math.cos(math.radians(a)), 12.4 + 4.4 * math.sin(math.radians(a)))
           for a in range(180, 451, 6)]
    line(pts)
    # cuerpo
    line([(24, 16.8), (24, 20.5)])
    line([(24, 20.5), (10.9, 30.1), (11.5, 33.6), (36.5, 33.6), (37.1, 30.1), (24, 20.5)])


def icon(size, rounded=True, scale=1.0):
    big = size * S
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if rounded:
        d.rounded_rectangle([0, 0, big - 1, big - 1], radius=big * 13 / 48, fill=BG)
    else:
        d.rectangle([0, 0, big, big], fill=BG)
    k = big / 48 * scale
    off = (big - 48 * k) / 2
    hanger(d, k, off, off, 2.9 * k)
    return img.resize((size, size), Image.LANCZOS)


out = sys.argv[1] if len(sys.argv) > 1 else "."
icon(512).save(f"{out}/Icon-512.png")
icon(192).save(f"{out}/Icon-192.png")
icon(512, rounded=False, scale=0.78).save(f"{out}/Icon-maskable-512.png")
icon(192, rounded=False, scale=0.78).save(f"{out}/Icon-maskable-192.png")
icon(180, rounded=False).save(f"{out}/apple-touch-icon.png")
icon(64).save(f"{out}/favicon.png")
