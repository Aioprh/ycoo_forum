#!/usr/bin/env python3
"""Render the YcooForum legacy launcher PNGs to match the adaptive vector icon.

Data mirrors android/app/src/main/res/drawable/ic_launcher_foreground_small.xml
on the 108x108 viewport, plus the gradient background.
"""
import math
import os
from PIL import Image, ImageDraw

VIEW = 108.0

def cubic(p0, p1, p2, p3, n=24):
    pts = []
    for i in range(n + 1):
        t = i / n
        mt = 1 - t
        x = mt**3 * p0[0] + 3 * mt**2 * t * p1[0] + 3 * mt * t**2 * p2[0] + t**3 * p3[0]
        y = mt**3 * p0[1] + 3 * mt**2 * t * p1[1] + 3 * mt * t**2 * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts

def build_book_outline():
    pts = []
    pts += cubic((35,45),(42,41.5),(49,40.4),(54,40.4))
    pts += cubic((54,40.4),(59,40.4),(66,41.5),(73,45))[1:]
    pts.append((73,67))
    pts += cubic((73,67),(66,70),(59,71),(54,71))[1:]
    pts += cubic((54,71),(49,71),(42,70),(35,67))[1:]
    pts.append((35,45))
    return pts


def lerp_color(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))

def make_flat_master(size):
    """Rounded-square icon (gradient bg + book + brackets), full square canvas."""
    s = size
    img = Image.new("RGBA", (s, s), (0,0,0,0))
    d = ImageDraw.Draw(img)
    scale = s / VIEW

    # vertical gradient background
    stops = [(0.0,(0x54,0xA8,0xFF)),(0.5,(0x2E,0x7B,0xF2)),(1.0,(0x17,0x46,0xC9))]
    bg = Image.new("RGBA", (s, s))
    bgd = ImageDraw.Draw(bg)
    for y in range(s):
        t = y / (s - 1)
        for i in range(len(stops)-1):
            if stops[i][0] <= t <= stops[i+1][0]:
                lt = (t - stops[i][0]) / (stops[i+1][0] - stops[i][0])
                col = lerp_color(stops[i][1], stops[i+1][1], lt)
                break
        else:
            col = stops[-1][1]
        bgd.line([(0,y),(s,y)], fill=col + (255,))
    img.paste(bg, (0,0))

    # white book
    outline = [(x*scale, y*scale) for x,y in build_book_outline()]
    d.polygon(outline, fill=(255,255,255,255))

    # spine crease
    d.line([(54*scale, 42*scale), (54*scale, 69*scale)],
           fill=(0x33,0x68,0xE8,255), width=max(2,int(2.2*scale)))

    # brackets
    def bracket(shape):
        for i in range(len(shape)-1):
            d.line([(shape[i][0]*scale, shape[i][1]*scale),
                    (shape[i+1][0]*scale, shape[i+1][1]*scale)],
                   fill=(255,255,255,255), width=max(2,int(4.5*scale)), joint="curve")
        # round caps
        rad = int(cal(4.5, scale))
        for (x,y) in [shape[0], shape[-1]]:
            d.ellipse([x*scale-rad, y*scale-rad, x*scale+rad, y*scale+rad], fill=(255,255,255,255))
    bracket([(40,27),(30,34),(40,41)])
    bracket([(68,27),(78,34),(68,41)])
    return img

def cal(v, scale):
    return v*scale

def rounded_corners(img, radius_ratio=0.196):
    """Apply rounded-corner alpha mask. radius_ratio fraction of size."""
    s = img.size[0]
    rad = int(s*radius_ratio)
    mask = Image.new("L", (s,s), 0)
    md = ImageDraw.Draw(mask)
    md.rectangle([rad,0,s-rad,s], fill=255)
    md.rectangle([0,rad,s,s-rad], fill=255)
    md.polygon([(rad,0),(s,0),(s,rad),(s,s),(0,s),(0,rad)], fill=255)
    md.rounded_rectangle([0,0,s,s], radius=rad, fill=255)
    out = Image.new("RGBA", (s,s), (0,0,0,0))
    out.paste(img, (0,0), mask)
    return out

BASE = "/workspace/android/app/src/main/res"

# ---- full launcher icons (legacy) ----
for den, size in [("mdpi",48),("hdpi",72),("xhdpi",96),("xxhdpi",144),("xxxhdpi",192)]:
    flat = make_flat_master(size)
    ico = rounded_corners(flat)
    path = f"{BASE}/mipmap-{den}/ic_launcher.png"
    ico.save(path)
    print("wrote", path)

# ---- foreground watermark (symbol only, transparent bg) ----
def make_foreground(size):
    s = size
    img = Image.new("RGBA", (s, s), (0,0,0,0))
    d = ImageDraw.Draw(img)
    scale = s / VIEW
    outline = [(x*scale, y*scale) for x,y in build_book_outline()]
    d.polygon(outline, fill=(255,255,255,255))
    d.line([(54*scale, 42*scale), (54*scale, 69*scale)],
           fill=(0x33,0x68,0xE8,255), width=max(2,int(2.2*scale)))
    rad = int(4.5*scale/2)
    for shape in [[(40,27),(30,34),(40,41)],[(68,27),(78,34),(68,41)]]:
        for i in range(len(shape)-1):
            d.line([(shape[i][0]*scale, shape[i][1]*scale),
                    (shape[i+1][0]*scale, shape[i+1][1]*scale)],
                   fill=(255,255,255,255), width=max(2,int(4.5*scale)), joint="curve")
        for (x,y) in [shape[0], shape[-1]]:
            d.ellipse([x*scale-rad, y*scale-rad, x*scale+rad, y*scale+rad], fill=(255,255,255,255))
    return img

for den, size in [("mdpi",108),("hdpi",162),("xhdpi",216),("xxhdpi",324),("xxxhdpi",432)]:
    fg = make_foreground(size)
    path = f"{BASE}/mipmap-{den}/ic_launcher_foreground.png"
    fg.save(path)
    print("wrote", path)

print("done")