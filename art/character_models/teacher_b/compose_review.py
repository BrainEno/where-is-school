#!/usr/bin/env python3
"""Arrange actual captures; never paint or synthesize model details in a sheet."""
import argparse
import base64
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'builds/teacher-b-review'
# The review image is not packed; use the repository's full source fonts.
FONTS = ROOT / 'art/fonts'
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
    publish_jpeg(sheet, 'classroom-comparison.jpg', 'crop-parts.txt', 'teacher-b compare', 40)


def publish_jpeg(sheet, name, relay, title, limit):
    # Numbered annotations are just a compact relay; the artifact also holds the original frames.
    for quality in (93, 88, 82, 75, 68, 61, 54):
        file = BytesIO()
        sheet.save(file, format='JPEG', quality=quality, optimize=True)
        encoded = base64.b64encode(file.getvalue()).decode('ascii')
        parts = [encoded[start:start+3900] for start in range(0, len(encoded), 3900)]
        if len(parts) <= limit:
            (OUT / name).write_bytes(file.getvalue())
            (OUT / relay).write_text(''.join(
                f'::notice title={title} part {i}/{len(parts)}::{part}\n' for i, part in enumerate(parts, 1)))
            return
    raise ValueError(f'{name} exceeds the annotation budget')


def motion():
    cases = (('idle', '站立待机', '3.8 s 循环 · 呼吸与轻微转头', (0, 20, 41)),
             ('walk', '短步行走', '2.9 s · 四步，前进 0.90 m 后站定', (0, 17, 34)),
             ('explain', '抬手讲解', '3.2 s · 左手两次轻点，落回身侧', (0, 15, 23)))
    sheet = Image.new('RGB', (930, 747), BG)
    draw = ImageDraw.Draw(sheet)
    text(draw, (23, 16), '生物老师 B · 专属动作', 30, serif=True)
    text(draw, (23, 55), 'Godot 教室审看场  /  连续取样中的实际画面', 15, GOLD)
    movie, durations = [], []
    for row, (clip, label, detail, selects) in enumerate(cases):
        paths = sorted((OUT / 'motion' / clip).glob('*.png'))
        if len(paths) <= max(selects):
            raise ValueError(f'{clip} has insufficient rendered frames: {len(paths)}')
        y = 86 + 219*row
        text(draw, (23, y), f'0{row+1}  {label}     {detail}', 16, QUIET)
        for i, index in enumerate(selects):
            with Image.open(paths[index]) as source:
                thumb = source.convert('RGB').resize((286, 184), Image.Resampling.LANCZOS)
            x = 23 + 299*i
            sheet.paste(thumb, (x, y+26))
            draw.rounded_rectangle((x+6, y+32, x+65, y+54), radius=3, fill=BG)
            text(draw, (x+12, y+36), f'{index/12:.2f} s', 13, GOLD)
        header = Image.new('RGB', (560, 426), BG)
        head_draw = ImageDraw.Draw(header)
        text(head_draw, (18, 12), f'0{row+1}  生物老师 B · {label}', 23, serif=True)
        text(head_draw, (18, 42), detail + '  /  Godot 实拍', 14, GOLD)
        for i, path in enumerate(paths):
            frame = header.copy()
            with Image.open(path) as source:
                frame.paste(source, (0, 66))
            movie.append(frame)
            durations.append(83 + (350 if i == len(paths)-1 else 0))
    movie[0].save(OUT / 'teacher-b-motion.webp', save_all=True, append_images=movie[1:],
                  duration=durations, loop=0, quality=83, method=4)
    publish_jpeg(sheet, 'motion-poses.jpg', 'motion-parts.txt', 'teacher-b motion', 30)


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
    which.add_argument('--runtime-only', action='store_true', help='compose the Godot comparison and motion captures')
    args = parser.parse_args()
    if not args.classroom_only and not args.runtime_only:
        studio()
    if not args.studio_only:
        classroom()
    if args.runtime_only:
        motion()


if __name__ == '__main__':
    main()
