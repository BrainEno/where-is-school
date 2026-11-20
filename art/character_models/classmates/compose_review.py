#!/usr/bin/env python3
"""Lay out unretouched rendered frames for visual review; keep the PNGs intact."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from PIL import Image, ImageDraw, ImageFont

from designs import ACTING, DESIGNS

ROOT = Path(__file__).resolve().parents[3]
FONT = ROOT/'art/fonts/NotoSansSC-Regular.ttf'
SERIF = ROOT/'art/fonts/NotoSerifSC-Regular.otf'
LABELS = {
    'thin_classmate': ('新同学', '细线镜框　／　旧灰蓝衬衫　／　收肩前探', '小声抱怨', '#577a8a'),
    'gentle_classmate': ('主角的好友', '黑色板材眼镜　／　暖色针织背心　／　温和圆脸', '点头听完，再轻轻摊掌', '#9b614e'),
    'court_classmate': ('球场同学', '染红的发梢　／　原创 07 球衣　／　运动员体态', '观察场边，手腕一松', '#a23d3e'),
}
INK, PAPER, SECONDARY = '#202734', '#f4f0e7', '#52616b'


def label(draw, xy, text, size, color=INK, serif=False):
    draw.text(xy,text,font=ImageFont.truetype(str(SERIF if serif else FONT),size),fill=color,anchor='lt')


def frame(sheet, src, x, y, w, h):
    # Fit (never stretch/crop) the actual image. No retouch of face, colours or pose.
    image = Image.open(src).convert('RGB')
    image.thumbnail((w,h),Image.Resampling.LANCZOS)
    sheet.paste(image,(x+(w-image.width)//2,y+(h-image.height)//2))


def board(images, out, key):
    name, style, action, accent = LABELS[key]
    clip, _ = ACTING[key]
    num = list(DESIGNS).index(key)+1
    h = DESIGNS[key].height
    canvas = Image.new('RGB',(1920,1860),PAPER)
    d = ImageDraw.Draw(canvas)
    x0, gap, tile = 85, 20, 422
    label(d,(x0,72),f'WHERE IS SCHOOL   /   同学模型审看   /   {num:02}',26,SECONDARY)
    label(d,(x0,126),name,67,serif=True)
    label(d,(1550,132),f'{h:.2f} m',69,accent)
    label(d,(x0,226),style,31,SECONDARY)
    d.line((x0,297,1833,297),fill=accent,width=4)
    for j,(leaf,title) in enumerate([('01-front','正面'),('03-left','左侧'),('05-back','背面'),('07-right','右侧')]):
        x = x0+j*(tile+gap)
        frame(canvas,images/f'{leaf}.png',x,327,tile,633)
        label(d,(x+2,979),title,28)
    d.line((x0,1034,1833,1034),fill='#d6d2cb',width=2)
    # The second row gives a larger expression view and a frame of the real clip.
    frame(canvas,images/'02-front-quarter.png',x0,1061,422,633)
    label(d,(x0+2,1710),'前侧四分之三',28)
    frame(canvas,images/'10-face-quarter.png',542,1080,625,625)
    label(d,(544,1724),'眼神、发线与面部结构',28)
    frame(canvas,images/f'11-{clip}.png',1210,1080,625,625)
    label(d,(1212,1724),action,28)
    label(d,(x0,1797),'技术审看   /   Blender Cycles 从运行时 GLB 实拍   /   左右以角色为准',24,SECONDARY)
    canvas.save(out,quality=94,subsampling=0,optimize=True)


def cover(images, out):
    canvas = Image.new('RGB',(1840,1500),PAPER)
    d = ImageDraw.Draw(canvas)
    label(d,(84,72),'WHERE IS SCHOOL    /    CAST STUDIES',29,SECONDARY)
    label(d,(82,128),'三位同学 · 同尺度站姿',66,serif=True)
    label(d,(85,223),'相同相机和地面高度，按模型实测身高渲染，不单独缩放。',31,SECONDARY)
    frame(canvas,images/'00-trio-at-scale.png',81,301,1678,1130)
    for x,key in zip((350,772,1260),DESIGNS):
        name,_,_,accent = LABELS[key]
        label(d,(x,1412),f'{name}  {DESIGNS[key].height:.2f} m',29,accent)
    canvas.save(out,quality=94,subsampling=0,optimize=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('studio',type=Path)
    p.add_argument('output',type=Path)
    p.add_argument('--only',choices=DESIGNS)
    args = p.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    names = [args.only] if args.only else DESIGNS
    for key in names:
        index = list(DESIGNS).index(key)+1
        board(args.studio/key,args.output/f'{index:02}-{key}-turnaround.jpg',key)
    if not args.only:
        cover(args.studio,args.output/'00-classmates-at-scale.jpg')
        manifest = json.loads((args.studio/'MANIFEST.json').read_text())
        with ZipFile(args.output/'classmates-original-pngs.zip','w',ZIP_DEFLATED) as z:
            z.write(args.studio/'00-trio-at-scale.png','00-trio-at-scale.png')
            z.write(args.studio/'MANIFEST.json','MANIFEST.json')
            for key,m in manifest['models'].items():
                for v in m['views']:
                    z.write(args.studio/key/v,f'{key}/{v}')


if __name__=='__main__':
    main()
