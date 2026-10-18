#!/usr/bin/env python3
"""生成 AppIcon.icns：蓝色渐变圆角方块 + 白色遥控器剪影。"""
import math
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

S = 2048
OUT = Path(__file__).resolve().parent


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size, top, bottom):
    img = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        draw.line([(0, y), (size, y)], fill=lerp(top, bottom, t))
    return img


def main():
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # 背景 squircle
    radius = int(S * 0.225)
    margin = int(S * 0.075)
    bg_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(bg_mask).rounded_rectangle(
        [margin, margin, S - margin, S - margin], radius=radius, fill=255
    )
    grad = gradient(S, (26, 115, 232), (52, 168, 83))  # Google blue -> green
    canvas.paste(grad, (0, 0), bg_mask)

    # 高光
    shine = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shine)
    sd.ellipse([-S * 0.35, -S * 0.55, S * 1.15, S * 0.42], fill=(255, 255, 255, 34))
    canvas = Image.alpha_composite(canvas, shine)

    # 遥控器阴影
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sh = ImageDraw.Draw(shadow)
    body = [S * 0.335, S * 0.145, S * 0.665, S * 0.865]
    sh.rounded_rectangle(
        [body[0], body[1] + S * 0.012, body[2], body[3] + S * 0.02],
        radius=S * 0.105, fill=(0, 0, 0, 90)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.02))
    canvas = Image.alpha_composite(canvas, shadow)

    draw = ImageDraw.Draw(canvas)

    # 遥控器主体
    draw.rounded_rectangle(body, radius=S * 0.105, fill=(250, 251, 253, 255),
                           outline=(226, 232, 240, 255), width=int(S * 0.004))

    cx = S / 2

    # 麦克风小孔
    draw.rounded_rectangle([cx - S * 0.014, S * 0.185, cx + S * 0.014, S * 0.235],
                           radius=S * 0.014, fill=(203, 213, 225, 255))

    # D-pad 圆环
    ring_r = S * 0.115
    ring_cy = S * 0.395
    draw.ellipse([cx - ring_r, ring_cy - ring_r, cx + ring_r, ring_cy + ring_r],
                 fill=(232, 240, 254, 255), outline=(26, 115, 232, 255), width=int(S * 0.012))
    draw.ellipse([cx - S * 0.036, ring_cy - S * 0.036, cx + S * 0.036, ring_cy + S * 0.036],
                 fill=(26, 115, 232, 255))

    # 方向点
    for dx, dy in [(0, -1), (0, 1), (-1, 0), (1, 0)]:
        x = cx + dx * ring_r * 0.66
        y = ring_cy + dy * ring_r * 0.66
        draw.ellipse([x - S * 0.012, y - S * 0.012, x + S * 0.012, y + S * 0.012],
                     fill=(26, 115, 232, 255))

    # 下方功能键
    def dot(x, y, r, color):
        draw.ellipse([x - r, y - r, x + r, y + r], fill=color, outline=(226, 232, 240, 255),
                     width=int(S * 0.003))

    dot(cx - S * 0.085, S * 0.585, S * 0.043, (95, 99, 104, 255))
    dot(cx + S * 0.085, S * 0.585, S * 0.043, (26, 115, 232, 255))
    dot(cx, S * 0.705, S * 0.052, (234, 67, 53, 255))

    # 麦克风图标（白色）
    mic_w = S * 0.015
    draw.rounded_rectangle([cx - mic_w, S * 0.674, cx + mic_w, S * 0.704],
                           radius=mic_w, fill=(255, 255, 255, 255))
    draw.arc([cx - S * 0.026, S * 0.700, cx + S * 0.026, S * 0.734], 0, 180,
             fill=(255, 255, 255, 255), width=int(S * 0.006))
    draw.line([cx, S * 0.734, cx, S * 0.748], fill=(255, 255, 255, 255), width=int(S * 0.006))

    # 输出 iconset
    iconset = OUT / "AppIcon.iconset"
    if iconset.exists():
        subprocess.run(["rm", "-rf", str(iconset)], check=True)
    iconset.mkdir()
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    for size in sizes:
        img = canvas.resize((size, size), Image.LANCZOS)
        img.save(iconset / f"icon_{size}x{size}.png")
        if size <= 512:
            img2 = canvas.resize((size * 2, size * 2), Image.LANCZOS)
            img2.save(iconset / f"icon_{size}x{size}@2x.png")
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(OUT / "AppIcon.icns")],
                   check=True)
    print("wrote", OUT / "AppIcon.icns")


if __name__ == "__main__":
    main()
