from PIL import Image, ImageDraw

SS = 4
BASE = 256
W = BASE * SS

BG = (24, 42, 56, 255)         # ardoise profonde, lisible sur toute ambiance
WHITE = (250, 252, 253, 255)
ACCENT = (91, 200, 232, 255)
MESH = (24, 42, 56, 255)


def build():
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = SS

    # Fond arrondi : garantit le contraste quelle que soit l'ambiance
    d.rectangle([0, 0, W - 1, W - 1], fill=BG)

    # Corps de l'ecouteur, legerement a droite pour laisser la place aux ondes
    head_cx, head_cy, head_r = 168 * s, 94 * s, 43 * s

    # Tige
    stem_w = 34 * s
    d.rounded_rectangle([head_cx - stem_w // 2, head_cy,
                         head_cx + stem_w // 2, 196 * s],
                        radius=stem_w // 2, fill=WHITE)

    # Tete
    d.ellipse([head_cx - head_r, head_cy - head_r,
               head_cx + head_r, head_cy + head_r], fill=WHITE)

    # Grille du haut-parleur
    d.ellipse([head_cx - 15 * s, head_cy - 15 * s,
               head_cx + 15 * s, head_cy + 15 * s], fill=MESH)

    # Ondes : trois arcs concentriques, symbole du controle du bruit
    for radius in (70, 96, 122):
        r = radius * s
        d.arc([head_cx - r, head_cy - r + 22 * s,
               head_cx + r, head_cy + r + 22 * s],
              start=148, end=212, fill=ACCENT, width=int(7 * s))

    return img.resize((BASE, BASE), Image.LANCZOS)


icon = build()
icon.save("icon-master.png")

for size in (86, 108, 128, 172):
    icon.resize((size, size), Image.LANCZOS).save("harbour-magicpods-%d.png" % size)

print("icones generees")
