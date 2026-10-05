#!/usr/bin/env python3
"""生成 AntiSIT 启动图标母版（1024x1024，需 Pillow）。

用法:
    python tool/make_icon.py [d|e|a|b|c|all]

方案（d 为默认，含上海应用技术大学意象——简体「应」字，不照抄校徽）:
    d  帽上「应」：蓝渐变 + 白色学士帽，板面印简体「应」
    e  大字「应」：蓝渐变 + 白色大字 + 琥珀流苏
    a  蓝底白帽：对角渐变 #3B82F6→#1D4ED8 + 白色学士帽 + 琥珀穗
    b  深蓝底白帽：#1E3A8A→#2563EB，更沉稳
    c  浅色底蓝帽：白→#DBEAFE + 蓝帽蓝穗（贴合网站白卡风格）

输出（tool/icon/，随仓库提交）:
    icon_<v>_1024.png   母版（圆角，用于传统 mipmap 与 Windows .ico）
    adaptive_bg_<v>.png 自适应图标背景层（满幅渐变）
    adaptive_fg_<v>.png 自适应图标前景层（透明底，图案落在安全区）

接入: pubspec.yaml 的 flutter_launcher_icons 指向对应文件后执行
    dart run flutter_launcher_icons
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 1024          # 画布
SS = 2            # 超采样倍数（抗锯齿）
OUT = os.path.join(os.path.dirname(__file__), 'icon')

# 帽体几何（1024 空间）：学位板菱形 + 板下窄穹顶 + 右侧流苏
BOARD_W = 660     # 学位板横向对角
BOARD_H = 330     # 学位板纵向对角
DOME_RX = 200     # 穹顶半径（窄于学位板，只在板下露出一条）
DOME_RY = 150
TH = 20           # 学位板厚度

# 各方案配色（bg=背景渐变两端，cap 系=帽体）
PALETTES = {
    'd': dict(bg=((59, 130, 246), (29, 78, 216)), cap='white', shade='#BFDBFE',
              tassel='#FBBF24', tassel_dark='#F59E0B', button='#93C5FD',
              board_char='应', char_color='#2563EB'),
    'a': dict(bg=((59, 130, 246), (29, 78, 216)), cap='white', shade='#BFDBFE',
              tassel='#FBBF24', tassel_dark='#F59E0B', button='#93C5FD'),
    'b': dict(bg=((30, 58, 138), (37, 99, 235)), cap='white', shade='#BFDBFE',
              tassel='#FBBF24', tassel_dark='#F59E0B', button='#60A5FA'),
    'c': dict(bg=((255, 255, 255), (219, 234, 254)), cap='#2563EB', shade='#1E40AF',
              tassel='#2563EB', tassel_dark='#1E40AF', button='#93C5FD', shadow_alpha=30),
    'e': dict(bg=((59, 130, 246), (29, 78, 216)), cap='white', shade='#BFDBFE',
              tassel='#FBBF24', tassel_dark='#F59E0B', button='#93C5FD'),
}


def lerp(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def gradient(c1, c2, diag=True, size=S):
    """低分辨率逐像素算渐变后放大（平滑且快）。"""
    n = 128
    img = Image.new('RGB', (n, n))
    px = img.load()
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2 * (n - 1)) if diag else y / (n - 1)
            px[x, y] = lerp(c1, c2, t)
    return img.resize((size, size), Image.BICUBIC)


def bold_font(size):
    """粗体简体中文字体：优先 Noto Sans SC（可变粗），回退微软雅黑 Bold / 黑体。"""
    for path in (r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
                 r'C:\Windows\Fonts\msyhbd.ttc',
                 r'C:\Windows\Fonts\simhei.ttf'):
        if not os.path.exists(path):
            continue
        try:
            f = ImageFont.truetype(path, int(size))
            try:
                f.set_variation_by_name('Bold')
            except Exception:
                pass
            return f
        except Exception:
            continue
    raise RuntimeError('未找到可用的中文粗体字体')


def draw_char(img, char, cx, cy, size, color):
    """把简体字的视觉中心落在 (cx, cy)。"""
    f = bold_font(size * SS)
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = d.textbbox((0, 0), char, font=f)
    d.text((cx * SS - (x0 + x1) / 2, cy * SS - (y0 + y1) / 2), char, font=f, fill=color)


def draw_cap(img, cx, cy, scale=1.0, shadow_alpha=46, board_char=None,
             char_color='#2563EB', **kw):
    """在 RGBA 图上画学士帽：(cx,cy)=学位板中心，scale 缩放整体。
    board_char：学位板面上印的简体字（学校意象，落在菱形安全区内）。"""
    cap = kw['cap']
    shade = kw['shade']
    tassel, tassel_dark = kw['tassel'], kw['tassel_dark']
    overlay = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    P = lambda x, y: ((cx + (x - 512) * scale) * SS, (cy + (y - 512) * scale) * SS)
    hw, hh = BOARD_W // 2, BOARD_H // 2

    # 地面阴影
    if shadow_alpha:
        sh = Image.new('RGBA', img.size, (0, 0, 0, 0))
        sd = ImageDraw.Draw(sh)
        sd.ellipse([P(512 - 265, 788), P(512 + 265, 840)], fill=(13, 35, 84, shadow_alpha))
        sh = sh.filter(ImageFilter.GaussianBlur(9 * SS))
        overlay.alpha_composite(sh)

    # 穹顶（帽体）
    d.ellipse([P(512 - DOME_RX, 540 - DOME_RY), P(512 + DOME_RX, 540 + DOME_RY)], fill=cap)

    # 学位板：先画下移的厚度层，再画本体
    d.polygon([P(512 - hw, 500 + TH), P(512, 500 + hh + TH),
               P(512 + hw, 500 + TH), P(512, 500 - hh + TH)], fill=shade)
    d.polygon([P(512 - hw, 500), P(512, 500 - hh),
               P(512 + hw, 500), P(512, 500 + hh)], fill=cap)

    # 板面简体字
    if board_char:
        draw_char(overlay, board_char, 512, 486, 196 * scale, char_color)

    # 板中心纽扣（无字时才画，避免与文字打架）
    if not board_char:
        d.ellipse([P(512 - 13, 500 - 13), P(512 + 13, 500 + 13)], fill=kw['button'])

    # 流苏：无字时从板中心引出；有字时挂右角，避免穿过板面文字
    if board_char:
        d.line([P(824, 508), P(824, 636)], fill=tassel, width=int(13 * scale * SS), joint='curve')
        tx = 824
    else:
        d.line([P(512, 500), P(748, 542)], fill=tassel, width=int(13 * scale * SS), joint='curve')
        d.line([P(748, 542), P(748, 664)], fill=tassel, width=int(13 * scale * SS), joint='curve')
        tx = 748
    d.rounded_rectangle([P(tx - 22, 652 if not board_char else 624),
                         P(tx + 22, 682 if not board_char else 654)],
                        radius=int(11 * scale * SS), fill=tassel_dark)
    ty0 = 680 if not board_char else 652
    d.polygon([P(tx - 24, ty0), P(tx + 24, ty0), P(tx + 15, ty0 + 72), P(tx - 15, ty0 + 72)],
              fill=tassel)

    img.alpha_composite(overlay)


def draw_tassel_only(img, x0, y0, drop=170, scale=1.0, tassel='#FBBF24',
                     tassel_dark='#F59E0B'):
    """无帽流苏：从 (x0,y0) 向右折再下垂（用于大字方案）。"""
    overlay = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    ex, ey = x0 + 84 * scale, y0 + 58 * scale
    d.line([(x0 * SS, y0 * SS), (ex * SS, ey * SS)], fill=tassel,
           width=int(13 * scale * SS), joint='curve')
    d.line([(ex * SS, ey * SS), (ex * SS, (ey + drop - 24) * scale * SS)], fill=tassel,
           width=int(13 * scale * SS), joint='curve')
    d.rounded_rectangle([(ex - 22 * scale) * SS, (ey + drop - 34) * scale * SS,
                         (ex + 22 * scale) * SS, (ey + drop - 4) * scale * SS],
                        radius=int(11 * scale * SS), fill=tassel_dark)
    d.polygon([(ex - 24 * scale) * SS, (ey + drop - 8) * scale * SS,
               (ex + 24 * scale) * SS, (ey + drop - 8) * scale * SS,
               (ex + 15 * scale) * SS, (ey + drop + 64) * scale * SS,
               (ex - 15 * scale) * SS, (ey + drop + 64) * scale * SS], fill=tassel)
    img.alpha_composite(overlay)


def rounded_master(img, out_path):
    """圆角母版：透明四角，用于传统 mipmap / Windows .ico。"""
    mask = Image.new('L', (S * SS, S * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S * SS - 1, S * SS - 1],
                                           radius=200 * SS, fill=255)
    mask = mask.resize((S, S), Image.LANCZOS)
    img.putalpha(mask)
    img.save(out_path)


def make_variant(v):
    p = PALETTES[v]
    os.makedirs(OUT, exist_ok=True)

    # 母版（2x 超采样绘制）
    master = Image.new('RGBA', (S * SS, S * SS), (0, 0, 0, 0))
    master.paste(gradient(*p['bg'], diag=(v != 'c'), size=S * SS), (0, 0))
    if v == 'e':
        draw_char(master, '应', 512, 516, 560, p['cap'])
        draw_tassel_only(master, 762, 300, scale=1.0,
                         tassel=p['tassel'], tassel_dark=p['tassel_dark'])
    else:
        draw_cap(master, 512, 496, scale=1.0, shadow_alpha=p.get('shadow_alpha', 46),
                 board_char=p.get('board_char'), char_color=p.get('char_color', '#2563EB'),
                 cap=p['cap'], shade=p['shade'], tassel=p['tassel'],
                 tassel_dark=p['tassel_dark'], button=p['button'])
    rounded_master(master.resize((S, S), Image.LANCZOS), os.path.join(OUT, f'icon_{v}_1024.png'))

    # 自适应背景层：满幅渐变（无圆角，启动器自行遮罩）
    gradient(*p['bg'], diag=(v != 'c')).save(os.path.join(OUT, f'adaptive_bg_{v}.png'))

    # 自适应前景层：透明底，图案缩到安全区（72/108 ≈ 0.62，再留余量取 0.56）
    fg = Image.new('RGBA', (S * SS, S * SS), (0, 0, 0, 0))
    if v == 'e':
        draw_char(fg, '应', 512, 512, 560 * 0.56, p['cap'])
        draw_tassel_only(fg, 762, 300, scale=0.56,
                         tassel=p['tassel'], tassel_dark=p['tassel_dark'])
    else:
        draw_cap(fg, 512, 512, scale=0.56, shadow_alpha=0,
                 board_char=p.get('board_char'), char_color=p.get('char_color', '#2563EB'),
                 cap=p['cap'], shade=p['shade'], tassel=p['tassel'],
                 tassel_dark=p['tassel_dark'], button=p['button'])
    fg.resize((S, S), Image.LANCZOS).save(os.path.join(OUT, f'adaptive_fg_{v}.png'))

    print(f'方案 {v} 完成 → {os.path.abspath(OUT)}')


def main():
    v = (sys.argv[1] if len(sys.argv) > 1 else 'd').lower()
    for x in (['d', 'e', 'a', 'b', 'c'] if v == 'all' else [v]):
        make_variant(x)


if __name__ == '__main__':
    main()
