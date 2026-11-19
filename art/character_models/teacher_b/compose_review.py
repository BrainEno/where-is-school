#!/usr/bin/env python3
"""Arrange actual captures; never paint or synthesize model details in a sheet."""
import argparse
import base64
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'builds/teacher-b-review'
FONTS = ROOT / 'assets/fonts'
BG, WHITE, QUIET, GOLD = '#24282a', '#f1e9d4', '#bac0bb', '#d1b48b'


def text(draw, pos, message, size, color=WHITE, serif=False):
    font = FONTS / ('NotoSerifSC-Regular.otf' if serif else 'NotoSansSC-Regular.ttf')
    draw.text(pos, message, font=ImageFont.truetype(str(font), size), fill=color, anchor='lt')


def crop(img, size, padding=1.0, centre=(.5, .5)):
    # A crop only, not a scale chosen per individual. Same parameters for both.
    w, h = img.size
    box = (w * (centre[0] - .5*padding), h * (centre[1] - .5*padding),
           w * (centre[0] + .5*padding), h * (centre[1] + .5*padding))
    return ImageOps.fit(img.crop(box), size, Image.Resampling.LANCZOS)


def classroom():
    sheet = Image.new('RGB', (992, 736), BG)
    draw = ImageDraw.Draw(sheet)
    text(draw, (26, 20), '同位置 · 同灯光 · 同镜头', 29, serif=True)
    text(draw, (26, 62), 'Godot  教室审看场  /  上：生物老师 B    下：现任主角', 16, GOLD)
    # Rows are subjects, columns are the fixed match cuts. Full PNGs remain in the artifact.
    margin, top = 24, 129
    cols = [(218, '同尺度全身', 'body', .975), (310, '同尺度脸部', 'face', .89), (392, '2.5D 游戏镜头', 'game', .70)]
    for row, prefix in enumerate(('b', 'lead')):
        x = margin
        y = top + row * 297
        for width, label, key, padding in cols:
            if row == 0:
                text(draw, (x, 101), label, 15, QUIET)
            frame = Image.open(OUT / 'classroom' / f'{prefix}_{key}.png').convert('RGB')
            image = crop(frame, (width, 280), padding)
            sheet.paste(image, (x, y))
            x += width + 12
    # Portrait-scale evidence can travel in 40 numbered GitHub annotations. Error rather
    # than silently publishing a truncated JPEG. The uploaded PNGs are not affected.
    for quality in (93, 88, 82, 75, 68, 61):
        file = BytesIO()
        sheet.save(file, format='JPEG', quality=quality, optimize=True)
        encoded = base64.b64encode(file.getvalue()).decode('ascii')
        parts = [encoded[start:start+3900] for start in range(0, len(encoded), 3900)]
        if len(parts) <= 40:
            (OUT / 'classroom-comparison.jpg').write_bytes(file.getvalue())
            (OUT / 'crop-parts.txt').write_text(''.join(
                f'::notice title=teacher-b compare part {i}/{len(parts)}::{part}\n' for i, part in enumerate(parts, 1)))
            return
    raise ValueError('Comparison sheet exceeds the annotation budget')


def studio():
    sheet = Image.new('RGB', (1500, 1156), BG)
    draw = ImageDraw.Draw(sheet)
    draw.line((32, 128, 1466, 128), fill=GOLD, width=1)
    text(draw, (33, 23), '生物老师 B', 61, serif=True)
    text(draw, (34, 96), '角色模型   /   造型与绑定审看', 19, GOLD)
    text(draw, (1115, 35), '164 cm  ·  57 关节', 25, GOLD)
    text(draw, (1115, 78), 'Blender 4.5 LTS  /  实际网格', 17, QUIET)

    def put(name, at, size, note, extent=1.0):
        image = Image.open(OUT / 'studio' / f'{name}.png').convert('RGB')
        rendered = crop(image, size, extent)
        x, y = at
        sheet.paste(rendered, (x, y))
        text(draw, (x, y + size[1] + 10), note, 17, QUIET)

    put('face', (34, 152), (636, 652), '01  三分之四脸部 · 镜框、发际与领口')
    for i, name in enumerate(('front', 'side', 'back')):
        put(name, (692 + 260*i, 152), (248, 475), ['02  正', '03  侧', '04  背'][i])
    put('demonstrate', (692, 672), (370, 423), '05  屈肘 · 指节各自弯曲')
    put('stride', (1079, 672), (380, 423), '06  迈步 · 膝踝与裤脚', .99)
    text(draw, (35, 887), '眼镜、发髻与衣装零件在 Blender 源文件中可分开编辑。', 20, WHITE)
    text(draw, (35, 930), '立绘未定义的下装暂用直筒裤与平底鞋。', 20, QUIET)
    text(draw, (35, 1011), '此图取自模型，不是立绘或新肖像。', 17, GOLD)
    text(draw, (35, 1048), '动作是检验蒙皮的定格，不是序章演出。', 17, QUIET)
    sheet.save(OUT / 'teacher-b-model.png', optimize=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    which = parser.add_mutually_exclusive_group()
    which.add_argument('--classroom-only', action='store_true')
    which.add_argument('--studio-only', action='store_true')
    args = parser.parse_args()
    if not args.classroom_only:
        studio()
    if not args.studio_only:
        classroom()


if __name__ == '__main__':
    main()
