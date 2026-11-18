"""Turns the class window images in art-src/ into the game textures in Art/.

    ../BeastCodex/.cache/venv/Scripts/python tools/make_art.py

Removes the magenta around the art and squeezes each image to fill a 512x1024
texture exactly (the game stretches it back to the window's 3:4 shape), then
saves it as BLP, the game's own compressed texture format (DXT5): about 0.5 MB
per theme instead of 2 MB as TGA. Needs Pillow 11.2+ (for the DXT5 encoder)
and Beast Codex's make_skin.py (for the magenta key).
"""
import io, os, struct, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "..", "BeastCodex", "tools"))
from make_skin import key_magenta

# source file in art-src/ -> texture name in Art/ (the name Core.lua's THEMES uses)
NAMES = {"guerreiro": "Warrior", "paladino": "Paladin", "hunter": "Hunter", "rogue": "Rogue", "priest": "Priest",
         "shaman": "Shaman", "mago": "Mage", "warlock": "Warlock", "druid": "Druid"}

W, H = 512, 1024


def blp(img):
    """BLP2 file bytes for an RGBA image: DXT5, one level (no mipmaps; a UI window is never drawn smaller)."""
    dds = io.BytesIO()
    img.save(dds, format="DDS", pixel_format="DXT5")
    data = dds.getvalue()[128:]  # drop the DDS header, keep the DXT5 blocks
    head = struct.pack("<4sI4B2I", b"BLP2", 1, 2, 8, 7, 0, img.width, img.height)  # 2 = DXT, 8-bit alpha, 7 = DXT5
    offsets = struct.pack("<16I", 1172, *[0] * 15)  # header 148 + unused palette 1024
    sizes = struct.pack("<16I", len(data), *[0] * 15)
    return head + offsets + sizes + bytes(1024) + data


for src, dst in NAMES.items():
    img = key_magenta(Image.open(os.path.join(ROOT, "art-src", src + ".jpg"))).resize((W, H), Image.LANCZOS)
    out = os.path.join(ROOT, "Art", dst + ".blp")
    with open(out, "wb") as f:
        f.write(blp(img))
    back = Image.open(out)  # self-check: the file reads back as the same picture
    assert back.size == (W, H) and back.mode == "RGBA", (back.size, back.mode)
    a, b = back.resize((64, 128)).tobytes(), img.resize((64, 128)).tobytes()
    assert sum(abs(x - y) for x, y in zip(a, b)) / len(a) < 4, "BLP differs from the source: " + dst
    print(dst)
