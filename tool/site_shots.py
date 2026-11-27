"""官网展示图导出：build/site_shots/*.png → site/public/img/shots/*.jpg

用法：python tool/site_shots.py
截图由 test/site_shots_test.dart 生成（SITE_SHOTS=1 flutter test test/site_shots_test.dart），
这里只做裁掉底部空白 + 缩到 900 宽 + 转 JPEG，控制官网首屏体积。
"""
import os

from PIL import Image

SRC = os.path.join("build", "site_shots")
DST = os.path.join("site", "public", "img", "shots")
TARGET_W = 900
PAGES = ["timetable", "ecard", "grades", "activities", "tools", "update"]
PALETTES = ["dark", "light"]

os.makedirs(DST, exist_ok=True)
for page in PAGES:
    for palette in PALETTES:
        src = os.path.join(SRC, f"{page}-{palette}.png")
        if not os.path.exists(src):
            print("skip", src)
            continue
        im = Image.open(src).convert("RGB")
        w, h = im.size
        im = im.resize((TARGET_W, int(h * TARGET_W / w)), Image.LANCZOS)
        out = os.path.join(DST, f"{page}-{palette}.jpg")
        im.save(out, "JPEG", quality=82, optimize=True, progressive=True)
        print(f"{out}  {im.size}  {os.path.getsize(out) // 1024} KB")