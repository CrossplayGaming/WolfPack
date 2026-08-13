"""Contact sheet of a voxel animation cycle: side view of every pose in
a row (the silhouette read), plus front views beneath."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

src = Path(sys.argv[1])
out = Path(sys.argv[2])
views = sorted(src.glob("*_views.png"))
if not views:
    sys.exit("no _views.png in " + str(src))

# each _views.png is [front | side | top] side by side
tiles = []
for p in views:
    im = Image.open(p).convert("RGB")
    third = im.width // 3
    front = im.crop((0, 0, third, im.height))
    side = im.crop((third, 0, third * 2, im.height))
    tiles.append((p.stem.replace("_views", ""), front, side))

pad = 8
w = max(t[1].width for t in tiles)
h = max(t[1].height for t in tiles)
sheet = Image.new("RGB", (len(tiles) * (w + pad) + pad,
                          h * 2 + pad * 3 + 34), (22, 20, 16))
dr = ImageDraw.Draw(sheet)
dr.text((pad, 6), "SIDE (the run cycle read) / FRONT", fill=(230, 200, 140))
x = pad
for name, front, side in tiles:
    sheet.paste(side, (x + (w - side.width) // 2, 22))
    sheet.paste(front, (x + (w - front.width) // 2, 22 + h + pad))
    dr.text((x + 4, 22 + h * 2 + pad + 4), name, fill=(160, 200, 200))
    x += w + pad
sheet.save(out)
print("->", out)
