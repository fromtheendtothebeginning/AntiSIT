#!/usr/bin/env python3
"""生成 AntiSIT 启动图标母版（1024x1024，需 Pillow）。

用法:
    python tool/make_icon.py [f|g|d|e|a|b|c|all]

方案（j 为默认：白底 + 深绿宋体「应戴学位帽」，含上海应用技术大学意象，不照抄校徽）:
    j  白底深绿：宋体、字缩小、琥珀流苏
    h  应戴学位帽·镂空：帽板代广字头，字∪板∪流苏整形透底挖空
    i  应戴学位帽·实心：白字白板 + 琥珀流苏
    f  透底镂空：整顶学士帽从蓝渐变底上挖空（真透明），板面保留与底同色的「应」
    g  线稿镂空：白色线条学士帽 + 实心白「应」
    d  帽上「应」：蓝渐变 + 白色学士帽，板面印简体「应」
    e  大字「应」：蓝渐变 + 白色大字 + 琥珀流苏
    a  蓝底白帽：对角渐变 #3B82F6→#1D4ED8 + 白色学士帽 + 琥珀穗
    b  深蓝底白帽：#1E3A8A→#2563EB，更沉稳
    c  浅色底蓝帽：白→#DBEAFE + 蓝帽蓝穗（贴合网站白卡风格）

输出（tool/icon/，随仓库提交）:
    icon_<v>_1024.png   母版（圆角，用于传统 mipmap 与 Windows .ico）
    adaptive_bg_<v>.png 自适应图标背景层
    adaptive_fg_<v>.png 自适应图标前景层

接入: pubspec.yaml 的 flutter_launcher_icons 指向对应文件后执行
    dart run flutter_launcher_icons
"""

import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

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
    'g': dict(bg=((59, 130, 246), (29, 78, 216))),
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


def bold_font(size, prefer='sans'):
    """粗体简体中文字体。prefer：sans=Noto Sans SC（可变粗）；deng=等线 Bold；
    serif=Noto Serif SC；均回退 微软雅黑 Bold / 黑体。"""
    first = {'sans': r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
             'deng': r'C:\Windows\Fonts\Dengb.ttf',
             'serif': r'C:\Windows\Fonts\NotoSerifSC-VF.ttf'}.get(prefer)
    paths = ([first] if first else []) + \
        [r'C:\Windows\Fonts\NotoSansSC-VF.ttf', r'C:\Windows\Fonts\msyhbd.ttc',
         r'C:\Windows\Fonts\simhei.ttf']
    for path in paths:
        if not path or not os.path.exists(path):
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


def char_mask_img(char, cx, cy, size):
    """字的 L 掩码（白=笔画），视觉中心落在 (cx, cy)，SS 分辨率。"""
    m = Image.new('L', (S * SS, S * SS), 0)
    d = ImageDraw.Draw(m)
    f = bold_font(size * SS)
    x0, y0, x1, y1 = d.textbbox((0, 0), char, font=f)
    d.text((cx * SS - (x0 + x1) / 2, cy * SS - (y0 + y1) / 2), char, font=f, fill=255)
    return m


def cap_silhouette_mask(scale=1.0, keep_char=None):
    """帽形剪影 L 掩码（白=剪影，含穹顶/学位板/厚度/流苏）。
    keep_char 给定时从剪影中扣除该字（镂空保留字）。"""
    m = Image.new('L', (S * SS, S * SS), 0)
    d = ImageDraw.Draw(m)
    P = lambda x, y: (x * SS, y * SS)
    hw, hh = BOARD_W // 2, BOARD_H // 2
    d.polygon([P(512 - hw, 500 + TH), P(512, 500 + hh + TH),
               P(512 + hw, 500 + TH), P(512, 500 - hh + TH)], fill=255)
    d.polygon([P(512 - hw, 500), P(512, 500 - hh), P(512 + hw, 500), P(512, 500 + hh)], fill=255)
    d.ellipse([P(512 - DOME_RX, 540 - DOME_RY), P(512 + DOME_RX, 540 + DOME_RY)], fill=255)
    d.line([P(824, 505), P(824, 636)], fill=255, width=int(13 * scale * SS), joint='curve')
    d.rounded_rectangle([P(824 - 22, 624), P(824 + 22, 654)], radius=int(11 * scale * SS), fill=255)
    d.polygon([P(824 - 24, 652), P(824 + 24, 652), P(824 + 15, 724), P(824 - 15, 724)], fill=255)
    if keep_char:
        m = ImageChops.subtract(m, char_mask_img(keep_char, 512, 486, 196 * scale))
    return m


def ying_cap_masks(cx, cy, scale, prefer='sans', char_size=470):
    """「应戴学位帽」图层掩码（SS 分辨率）：字 / 帽板（代广字头）/ 流苏。
    帽板菱形盖住字顶的 点+横（广字头位置），撇与内件露在板下。"""
    gm = Image.new('L', (S * SS, S * SS), 0)
    dg = ImageDraw.Draw(gm)
    f = bold_font(char_size * scale * SS, prefer=prefer)
    x0, y0, x1, y1 = dg.textbbox((0, 0), '应', font=f)
    tx = cx * SS - (x0 + x1) / 2
    ty = cy * SS - (y0 + y1) / 2 + 70 * scale * SS  # 字心下移，顶部让给帽板
    dg.text((tx, ty), '应', font=f, fill=255)
    top, gh = ty + y0, y1 - y0

    bm = Image.new('L', (S * SS, S * SS), 0)
    db = ImageDraw.Draw(bm)
    bcx, bcy = cx * SS, top + 0.15 * gh
    bw = (x1 - x0) / 2 * 1.30 + 8 * scale * SS
    bh = 0.19 * gh
    db.polygon([(bcx - bw, bcy), (bcx, bcy - bh), (bcx + bw, bcy), (bcx, bcy + bh)], fill=255)

    tm = Image.new('L', (S * SS, S * SS), 0)
    dt = ImageDraw.Draw(tm)
    k = scale * SS
    px = bcx + bw - 12 * k
    dt.line([(px, bcy + 6 * k), (px, bcy + 148 * k)], fill=255, width=int(13 * k), joint='curve')
    dt.rounded_rectangle([(px - 20 * k, bcy + 138 * k), (px + 20 * k, bcy + 168 * k)],
                         radius=int(10 * k), fill=255)
    dt.polygon([(px - 22 * k, bcy + 166 * k), (px + 22 * k, bcy + 166 * k),
                (px + 14 * k, bcy + 238 * k), (px - 14 * k, bcy + 238 * k)], fill=255)
    return gm, bm, tm


def draw_cap_outline(img, cx, cy, scale=1.0, line='white', char_color='white'):
    """线稿镂空学士帽：菱形板与穹顶下弧描边，流苏线稿，板面实心字。"""
    overlay = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    P = lambda x, y: ((cx + (x - 512) * scale) * SS, (cy + (y - 512) * scale) * SS)
    lw = lambda v: max(1, int(v * scale * SS))
    hw, hh = BOARD_W // 2, BOARD_H // 2

    # 穹顶下半弧 + 学位板描边
    d.arc([P(512 - DOME_RX, 540 - DOME_RY), P(512 + DOME_RX, 540 + DOME_RY)],
          start=12, end=168, fill=line, width=lw(22))
    d.polygon([P(512 - hw, 500), P(512, 500 - hh), P(512 + hw, 500), P(512, 500 + hh)],
              outline=line, width=lw(24))

    # 流苏（挂右角）：线 + 结 + 穗身（小件实心）
    d.line([P(824, 505), P(824, 632)], fill=line, width=lw(12), joint='curve')
    d.rounded_rectangle([P(824 - 20, 624), P(824 + 20, 652)], radius=lw(10), fill=line)
    d.polygon([P(824 - 22, 650), P(824 + 22, 650), P(824 + 14, 718), P(824 - 14, 718)], fill=line)

    # 板面简体字（实心，保证小尺寸可读）
    draw_char(overlay, '应', 512, 486, 196 * scale, char_color)
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
    os.makedirs(OUT, exist_ok=True)

    # ── j 白底深绿「应戴学位帽」：等线 Bold、字缩小、琥珀穗 ──
    if v == 'j':
        gm, bm, tm = ying_cap_masks(512, 500, 1.0, prefer='deng', char_size=470)
        master = Image.new('RGBA', (S * SS, S * SS), (255, 255, 255, 255))
        green = Image.new('RGBA', master.size, (22, 101, 52, 255))  # green-800 深绿
        master.paste(green, (0, 0), ImageChops.lighter(gm, bm))
        master.paste(Image.new('RGBA', master.size, (245, 158, 11, 255)), (0, 0), tm)
        rounded_master(master.resize((S, S), Image.LANCZOS), os.path.join(OUT, 'icon_j_1024.png'))

        fg = Image.new('RGBA', (S * SS, S * SS), (0, 0, 0, 0))
        gm, bm, tm = ying_cap_masks(512, 512, 0.80, prefer='deng', char_size=470)
        fg.paste(green, (0, 0), ImageChops.lighter(gm, bm))
        fg.paste(Image.new('RGBA', fg.size, (245, 158, 11, 255)), (0, 0), tm)
        fg.resize((S, S), Image.LANCZOS).save(os.path.join(OUT, 'adaptive_fg_j.png'))
        Image.new('RGB', (S, S), (255, 255, 255)).save(os.path.join(OUT, 'adaptive_bg_j.png'))
        print(f'方案 {v} 完成 → {os.path.abspath(OUT)}')
        return

    # ── h 镂空「应戴学位帽」：字∪帽板∪流苏整形从底上挖空（透壁纸） ──
    if v == 'h':
        bg = gradient((59, 130, 246), (29, 78, 216))  # blue-500 → blue-700
        gm, bm, tm = ying_cap_masks(512, 506, 1.0)
        hole = ImageChops.lighter(ImageChops.lighter(gm, bm), tm)
        rounded = Image.new('L', (S * SS, S * SS), 0)
        ImageDraw.Draw(rounded).rounded_rectangle([0, 0, S * SS - 1, S * SS - 1],
                                                  radius=200 * SS, fill=255)
        master = bg.convert('RGBA').resize((S * SS, S * SS))
        master = master.resize((S, S), Image.LANCZOS)
        master.putalpha(ImageChops.subtract(rounded, hole).resize((S, S), Image.LANCZOS))
        master.save(os.path.join(OUT, 'icon_h_1024.png'))

        abg = bg.convert('RGBA')
        abg.putalpha(ImageChops.invert(hole).resize((S, S), Image.LANCZOS))
        abg.save(os.path.join(OUT, 'adaptive_bg_h.png'))
        Image.new('RGBA', (S, S), (0, 0, 0, 0)).save(os.path.join(OUT, 'adaptive_fg_h.png'))
        print(f'方案 {v} 完成 → {os.path.abspath(OUT)}')
        return

    # ── i 实心「应戴学位帽」：白字白板 + 琥珀流苏 ──
    if v == 'i':
        master = Image.new('RGBA', (S * SS, S * SS), (0, 0, 0, 0))
        master.paste(gradient((59, 130, 246), (29, 78, 216), size=S * SS), (0, 0))
        gm, bm, tm = ying_cap_masks(512, 500, 1.0)
        white = Image.new('RGBA', master.size, (255, 255, 255, 255))
        master.paste(white, (0, 0), ImageChops.lighter(gm, bm))
        master.paste(Image.new('RGBA', master.size, (251, 191, 36, 255)), (0, 0), tm)
        rounded_master(master.resize((S, S), Image.LANCZOS), os.path.join(OUT, 'icon_i_1024.png'))

        fg = Image.new('RGBA', (S * SS, S * SS), (0, 0, 0, 0))
        gm, bm, tm = ying_cap_masks(512, 512, 0.56)
        fg.paste(white, (0, 0), ImageChops.lighter(gm, bm))
        fg.paste(Image.new('RGBA', fg.size, (251, 191, 36, 255)), (0, 0), tm)
        fg.resize((S, S), Image.LANCZOS).save(os.path.join(OUT, 'adaptive_fg_i.png'))
        gradient((59, 130, 246), (29, 78, 216)).save(os.path.join(OUT, 'adaptive_bg_i.png'))
        print(f'方案 {v} 完成 → {os.path.abspath(OUT)}')
        return

    # ── f 透底镂空：帽形挖孔（字保留），母版与自适应背景都真透明 ──
    if v == 'f':
        bg = gradient((59, 130, 246), (29, 78, 216))  # blue-500 → blue-700
        hole = cap_silhouette_mask(scale=1.0, keep_char='应')
        rounded = Image.new('L', (S * SS, S * SS), 0)
        ImageDraw.Draw(rounded).rounded_rectangle([0, 0, S * SS - 1, S * SS - 1],
                                                  radius=200 * SS, fill=255)
        master = bg.convert('RGBA').resize((S * SS, S * SS))
        master = master.resize((S, S), Image.LANCZOS)
        master.putalpha(ImageChops.subtract(rounded, hole).resize((S, S), Image.LANCZOS))
        master.save(os.path.join(OUT, 'icon_f_1024.png'))

        abg = bg.convert('RGBA')
        abg.putalpha(ImageChops.invert(hole).resize((S, S), Image.LANCZOS))
        abg.save(os.path.join(OUT, 'adaptive_bg_f.png'))
        Image.new('RGBA', (S, S), (0, 0, 0, 0)).save(os.path.join(OUT, 'adaptive_fg_f.png'))
        print(f'方案 {v} 完成 → {os.path.abspath(OUT)}')
        return

    p = PALETTES[v]
    # ── g 线稿镂空：白色线条帽 + 实心字 ──
    if v == 'g':
        master = Image.new('RGBA', (S * SS, S * SS), (0, 0, 0, 0))
        master.paste(gradient(*p['bg'], size=S * SS), (0, 0))
        draw_cap_outline(master, 512, 496, scale=1.0, line='white', char_color='white')
        rounded_master(master.resize((S, S), Image.LANCZOS), os.path.join(OUT, 'icon_g_1024.png'))

        fg = Image.new('RGBA', (S * SS, S * SS), (0, 0, 0, 0))
        draw_cap_outline(fg, 512, 512, scale=0.56, line='white', char_color='white')
        fg.resize((S, S), Image.LANCZOS).save(os.path.join(OUT, 'adaptive_fg_g.png'))
        gradient(*p['bg']).save(os.path.join(OUT, 'adaptive_bg_g.png'))
        print(f'方案 {v} 完成 → {os.path.abspath(OUT)}')
        return

    # ── 其余实心方案 ──
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
    v = (sys.argv[1] if len(sys.argv) > 1 else 'j').lower()
    for x in (['j', 'h', 'i', 'f', 'g', 'd', 'e', 'a', 'b', 'c'] if v == 'all' else [v]):
        make_variant(x)


if __name__ == '__main__':
    main()
