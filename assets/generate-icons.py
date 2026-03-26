"""Generate app icons for Smartiecoin Wallet iOS."""
from PIL import Image, ImageDraw, ImageFont
import os

DIR = os.path.dirname(os.path.abspath(__file__))

def create_icon(size, filename, is_splash=False):
    bg_color = (15, 23, 42)       # slate-900
    primary = (99, 102, 241)      # indigo-500
    white = (248, 250, 252)

    img = Image.new('RGBA', (size, size), bg_color)
    draw = ImageDraw.Draw(img)

    if is_splash:
        # Splash: centered circle with S
        r = size // 8
        cx, cy = size // 2, size // 2
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=primary)
        font_size = int(r * 1.4)
        try:
            font = ImageFont.truetype("arial.ttf", font_size)
        except:
            font = ImageFont.load_default()
        bbox = draw.textbbox((0, 0), "S", font=font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        draw.text((cx - tw // 2, cy - th // 2 - bbox[1]), "S", fill=white, font=font)
    else:
        # Icon: large circle with S, with rounded corners feel
        margin = size // 10
        draw.rounded_rectangle(
            [0, 0, size, size],
            radius=size // 5,
            fill=bg_color
        )
        r = size // 3
        cx, cy = size // 2, size // 2
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=primary)
        font_size = int(r * 1.3)
        try:
            font = ImageFont.truetype("arial.ttf", font_size)
        except:
            font = ImageFont.load_default()
        bbox = draw.textbbox((0, 0), "S", font=font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        draw.text((cx - tw // 2, cy - th // 2 - bbox[1]), "S", fill=white, font=font)

    img.save(os.path.join(DIR, filename))
    print(f"Created {filename} ({size}x{size})")

create_icon(1024, "icon.png")
create_icon(1024, "adaptive-icon.png")
create_icon(1284, "splash.png", is_splash=True)

print("Done! Icons ready.")
