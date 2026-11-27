"""校徽三色拆分：assets/sit-mark.png → sit-mark-{light,dark,green}.png

用法：python tool/split_logo.py

启动动画要分层「画」校徽（浅蓝弧 / 深蓝弧 / 绿点各自扫出来），但手上只有一张
合成好的 PNG。这个脚本按「离哪种基色最近」把像素分到三层：三层都保留原图同一张
512 画布与各自的 alpha（抗锯齿靠 alpha），叠回去就是原标，位置天然对齐。

输出会再量化成 32 色调色板（每层其实只有一种颜色 + alpha），单层 2-3 KB。
改了原始 sit-mark.png 之后重跑一次即可。
"""
import os

import numpy as np
from PIL import Image

SRC = os.path.join("assets", "sit-mark.png")
OUT = os.path.join("assets")

# 三层各自的基色（取自原图的主色）
LIGHT = np.array([107, 204, 255])
DARK = np.array([7, 73, 170])
GREEN = np.array([23, 216, 132])


def main() -> None:
    im = Image.open(SRC).convert("RGBA")
    a = np.array(im)
    rgb = a[:, :, :3].astype(np.float64)
    opaque = a[:, :, 3] > 0

    refs = np.stack([LIGHT, DARK, GREEN]).astype(np.float64)
    flat = rgb.reshape(-1, 3)
    dist = ((flat[:, None, :] - refs[None, :, :]) ** 2).sum(axis=2)
    cls = dist.argmin(axis=1).reshape(a.shape[0], a.shape[1])

    for idx, name in enumerate(["light", "dark", "green"]):
        keep = opaque & (cls == idx)
        layer = a.copy()
        layer[:, :, 3] = np.where(keep, a[:, :, 3], 0)
        solid = np.zeros_like(layer)
        solid[:, :, :3] = refs[idx].astype(np.uint8)
        solid[:, :, 3] = layer[:, :, 3]
        dst = os.path.join(OUT, f"sit-mark-{name}.png")
        Image.fromarray(solid, "RGBA").convert(
            "P", palette=Image.ADAPTIVE, colors=32
        ).save(dst, optimize=True)
        print(f"{dst}  {int(keep.sum())} px  {os.path.getsize(dst)} B")


if __name__ == "__main__":
    main()
