#!/usr/bin/env python3
"""Icons and Windows resources for the MAE Routing client.

usage: python3 mae/make-assets.py .
Writes tray icons (cmd/mae-routing-gui/icons/{on,off,warn}.ico), the app icon (mae/out/MAERouting.ico
+ PNG for the installer), and go-winres JSON for maeroutingd.exe, mae-routing.exe and MAERouting.exe.
The .syso files are then made with: go run github.com/tc-hib/go-winres@v0.3.3 make --in <dir>/winres.json
"""
import io
import json
import pathlib
import struct
import sys

from PIL import Image, ImageDraw

BRAND = (234, 88, 12, 255)      # MAE Routing orange #EA580C
GREY = (122, 127, 153, 255)
AMBER = (245, 158, 11, 255)
MINT = (255, 224, 138, 255)      # accent node #FFE08A
WHITE = (255, 255, 255, 255)
VERSION = '1.104.2.1'          # file version shown in Explorer (upstream 1.104.2, MAE build 1)
HERE = pathlib.Path(__file__).resolve().parent


def render(size, bg, badge=None, tray=False):
    """The MAE Routing mark: rounded square, an 'M' route with three nodes. Drawn at 4x, then downsampled."""
    S = size * 4
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    k = S / 40
    pad = 0 if not tray else S * 0.02
    d.rounded_rectangle((pad, pad, S - pad, S - pad), radius=10 * k, fill=bg)
    w = int((3.6 if tray else 2.8) * k)
    pts = [(11 * k, 28 * k), (11 * k, 14 * k), (20 * k, 22 * k), (29 * k, 14 * k), (29 * k, 28 * k)]
    d.line(pts, fill=WHITE, width=w, joint='curve')
    for x, y in pts[1:4:2]:
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=WHITE)
    r = (4.2 if tray else 3.4) * k
    for (x, y), c in (((11 * k, 28 * k), WHITE), ((29 * k, 28 * k), WHITE), ((20 * k, 22 * k), MINT)):
        d.ellipse((x - r, y - r, x + r, y + r), fill=c)
    if badge:
        br = 7.5 * k
        cx, cy = S - br - 0.5 * k, br + 0.5 * k
        d.ellipse((cx - br - 1.5 * k, cy - br - 1.5 * k, cx + br + 1.5 * k, cy + br + 1.5 * k), fill=WHITE)
        d.ellipse((cx - br, cy - br, cx + br, cy + br), fill=badge)
    return im.resize((size, size), Image.LANCZOS)


def write_ico(path, make, sizes=(16, 20, 24, 32, 40, 48, 64, 128, 256)):
    """Standard Windows ICO: 16-128 as 32-bit BMP + AND mask, 256 as PNG, planes=1 (same as MAE Remote;
    Pillow's all-PNG ICOs with planes=0 made Explorer show no icon)."""
    images = []
    for s in sizes:
        im = make(s).convert('RGBA')
        if s == 256:
            buf = io.BytesIO()
            im.save(buf, 'PNG')
            images.append((s, buf.getvalue()))
            continue
        px = im.load()
        xor, and_mask = bytearray(), bytearray()
        mask_row = ((s + 31) // 32) * 4
        for y in range(s - 1, -1, -1):
            row_bits = bytearray(mask_row)
            for x in range(s):
                r, g, b, a = px[x, y]
                xor += bytes((b, g, r, a))
                if a == 0:
                    row_bits[x // 8] |= 0x80 >> (x % 8)
            and_mask += row_bits
        header = struct.pack('<IiiHHIIiiII', 40, s, s * 2, 1, 32, 0, len(xor) + len(and_mask), 0, 0, 0, 0)
        images.append((s, header + bytes(xor) + bytes(and_mask)))
    out = struct.pack('<HHH', 0, 1, len(images))
    offset = 6 + 16 * len(images)
    for s, blob in images:
        dim = 0 if s == 256 else s
        out += struct.pack('<BBBBHHII', dim, dim, 0, 0, 1, 32, len(blob), offset)
        offset += len(blob)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(out + b''.join(blob for _, blob in images))
    print(f'  ico {path}')


def winres(path, ico, desc, filename, admin=False):
    manifest = {
        'identity': {}, 'description': desc, 'minimum-os': 'win7',
        'execution-level': 'require administrator' if admin else 'as invoker',
        'dpi-awareness': 'per monitor v2', 'use-common-controls-v6': True,
    }
    info = {
        'CompanyName': 'MAE Routing (maesuaisystem.com)', 'FileDescription': desc, 'FileVersion': VERSION,
        'InternalName': filename.removesuffix('.exe'), 'OriginalFilename': filename, 'ProductName': 'MAE Routing',
        'ProductVersion': VERSION,
        'LegalCopyright': '© 2026 MAE Routing · portions © Tailscale Inc & contributors (BSD-3-Clause)',
    }
    data = {
        'RT_GROUP_ICON': {'APP': {'0000': ico.name}},   # go-winres resolves paths from the json's folder
        'RT_MANIFEST': {'#1': {'0409': manifest}},
        'RT_VERSION': {'#1': {'0000': {'fixed': {'file_version': VERSION, 'product_version': VERSION},
                                      'info': {'0409': info}}}},
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    (path.parent / ico.name).write_bytes(ico.read_bytes())
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding='utf-8')
    print(f'  winres {path}')


def main():
    root = pathlib.Path(sys.argv[1]).resolve()
    icons = root / 'cmd/mae-routing-gui/icons'
    write_ico(icons / 'on.ico', lambda s: render(s, BRAND, tray=True), sizes=(16, 20, 24, 32, 40, 48, 64))
    write_ico(icons / 'off.ico', lambda s: render(s, GREY, tray=True), sizes=(16, 20, 24, 32, 40, 48, 64))
    write_ico(icons / 'warn.ico', lambda s: render(s, GREY, AMBER, tray=True), sizes=(16, 20, 24, 32, 40, 48, 64))
    app_ico = HERE / 'out/MAERouting.ico'
    write_ico(app_ico, lambda s: render(s, BRAND))
    render(512, BRAND).save(HERE / 'out/MAERouting-512.png')
    # NSIS wizard bitmaps: header 150x57, welcome/finish 164x314 (24-bit BMP)
    hdr = Image.new('RGB', (150, 57), (255, 255, 255))
    hdr.paste(render(44, BRAND), (96, 6), render(44, BRAND))
    hdr.save(HERE / 'out/header.bmp')
    side = Image.new('RGB', (164, 314), BRAND[:3])
    side.paste(render(96, (255, 255, 255, 40)), (34, 40), render(96, (255, 255, 255, 40)))
    side.paste(render(72, BRAND), (46, 52), render(72, BRAND))
    side.save(HERE / 'out/wizard.bmp')
    winres(root / 'cmd/tailscaled/winres/winres.json', app_ico, 'MAE Routing service', 'maeroutingd.exe')
    winres(root / 'cmd/tailscale/winres/winres.json', app_ico, 'MAE Routing command line', 'mae-routing.exe')
    winres(root / 'cmd/mae-routing-gui/winres/winres.json', app_ico, 'MAE Routing', 'MAERouting.exe')


if __name__ == '__main__':
    main()
