#!/usr/bin/env python3
"""Koyu, sade duvar kâğıdını üretir (assets/istasyon-koyu.jpg).

Kullanım: python3 duvar_kagidi_uret.py [genişlik] [yükseklik] [çıktı]
Gereken: numpy, pillow. Dosya zaten depoda hazır; bu betik yalnızca yeniden üretmek içindir.
"""
import sys

import numpy as np
from PIL import Image

G = int(sys.argv[1]) if len(sys.argv) > 1 else 3840
Y = int(sys.argv[2]) if len(sys.argv) > 2 else 2160
CIKTI = sys.argv[3] if len(sys.argv) > 3 else "istasyon-koyu.jpg"


def renk(hex_kod):
    hex_kod = hex_kod.lstrip("#")
    return np.array([int(hex_kod[i : i + 2], 16) for i in (0, 2, 4)], dtype=np.float32) / 255.0


yy, xx = np.mgrid[0:Y, 0:G].astype(np.float32)
u = xx / G
v = yy / Y
oran = G / Y

# Taban: üstten alta çok hafif koyulaşan gece mavisi
ust, alt = renk("#0d111a"), renk("#07090e")
img = ust * (1 - v[..., None]) + alt * v[..., None]


def isik(cx, cy, yaricap, hex_kod, guc):
    """Yumuşak, gauss dağılımlı renk parlaması (ekran karışımı)."""
    d2 = ((u - cx) * oran) ** 2 + (v - cy) ** 2
    a = guc * np.exp(-d2 / (2 * yaricap**2))
    c = renk(hex_kod)
    return 1 - (1 - img) * (1 - c * a[..., None])


img = isik(0.16, 0.92, 0.42, "#2f55d4", 0.46)  # sol alt: derin mavi
img = isik(0.88, 0.08, 0.36, "#139aa6", 0.26)  # sağ üst: camgöbeği
img = isik(0.60, 1.05, 0.30, "#6c42d6", 0.20)  # alt orta: mor ipucu

# İnce yörünge çizgileri (çok düşük opaklık)
cx, cy = 0.80 * oran, 1.30
d = np.sqrt((u * oran - cx) ** 2 + (v - cy) ** 2)
kalinlik = 1.6 / Y
cizgi = np.zeros_like(d)
for i, r in enumerate(np.arange(0.62, 1.60, 0.11)):
    a = np.clip(1 - np.abs(d - r) / kalinlik, 0, 1) * (0.085 - i * 0.006)
    cizgi = np.maximum(cizgi, a)
img = img + cizgi[..., None] * renk("#9fb4ff")

# Kenar karartma
vin = ((u - 0.5) * oran) ** 2 + (v - 0.5) ** 2
img = img * (1 - 0.28 * np.clip(vin / 1.4, 0, 1))[..., None]

# Bantlaşmayı önlemek için üçgen dağılımlı titreşim (dither)
rng = np.random.default_rng(2026)
gurultu = (rng.random(img.shape, dtype=np.float32) - rng.random(img.shape, dtype=np.float32)) * 1.2
img8 = np.clip(img * 255 + gurultu, 0, 255).round().astype(np.uint8)

Image.fromarray(img8, "RGB").save(CIKTI, quality=94, subsampling=0, optimize=True)
print(f"Kaydedildi: {CIKTI} ({G}x{Y})")
