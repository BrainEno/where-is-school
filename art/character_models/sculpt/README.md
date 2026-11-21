# 八位角色：Blender 头部精修

第一轮（#311）做整体头部轮廓。本轮恢复主角的刺猬头，另外七位只修五官，按各自的脸型和表情做不同处理。正式角色仍走原包装，三位同学和 B 仍限审看。不改肖像、衣服、材质、放置、骨架、表情偏移和嵌入动作。主角步行摆臂另由现有 `protagonist_motion.tres` 调整，不写进 GLB 动作。

| Blender 集合 | 角色 / 用途 | 本轮几何 |
| --- | --- | --- |
| `LEAD` | 主角 / 正式 | 从原数模取回长短不齐、向外炸开的刺束。顶发错开走向，额前留几束落下来，横穿耳廓的长刺向后收。沿用原索引和 `Head` 刚性绑定，脸保持上一轮。 |
| `Q` | Q / 正式 | 保留短发壳和笑意；眼睑与巩膜、虹膜一起收，眉尾留一点高低差，略收鼻尖并理顺唇峰和下唇。 |
| `N` | 代课老师 / 正式 | 保留短波波头，梳理窄鼻梁、鼻翼、上眼睑和左右眉线；眼睛几层跟随同一形变，唇部不单移接缝。 |
| `SEATED` | 坐姿学生 / 正式 | 保留原裁切眼片及虹膜、瞳孔、高光的位置，修眼眶、上睑、眉形、鼻孔过渡与唇线。 |
| `THIN` | 薄瘦同学 / 审看 | 连续的短发顶不动。加强眼窝与细眉的转折，收鼻尖及鼻翼，整理偏薄的中央嘴唇。 |
| `GENTLE` | 好友 / 审看 | 给柔和的下眼睑、眉弓、圆鼻与较饱满的下唇少量体积，保留原眼镜和笑时的嘴角。 |
| `COURT` | 球场同学 / 审看 | 保留单侧略高的眉及斜眼感，修较深的外眼角、鼻翼和唇形；不改红发和笑形。 |
| `B` | B 老师 / 审看 | 收眉峰、保留眼下纹和覆睑，缓和鼻尖、整理偏薄的唇线；不改发髻、眼镜和年龄感。 |

## 序章对话：Q 的近景修整

以 `0ac97d77f7a3407c8ca7bc6298d4a011186b8608` 的生产 Q 为对照。`forms.py` 的 `q_closeup_planes` 在已精修的脸上压出鼻翼转折、眼睑外沿、颊面和下唇平面；用同一深度场带动口内表面。只烘焙 `Q_Head` 的皮肤、口腔两个表面的位置与法线，最大位移小于 4 mm。不动眼球、眉片、发壳、口眼表情偏移、绑定、动作或其他角色。

正式教室 `QTalk.dialogue_shot` 跟随运行中 `Head` 骨骼的姿态瞄准脸，`SetSquareInspect.dialogue_shot` 锁定讲桌原尺的断口和叠胶。两者只由现有 `camera_focus` 效果触发，不替代普通互动镜头。手动新开游戏，分别选择 `look_square` 与 `watch_q`，停在下一行观察，继续对白确认回到原构图。书包对话里的 `square_again` 复用断口镜头。

## 打开、编辑、烘焙

1. 在 **Blender 4.5 LTS** 打开 [`Head_Studies.blend`](Head_Studies.blend)（制作及复烘用 **4.5.3**）。在 Outliner 只显示一位角色；局部对象按 Hair / Face / Eye / Ear 分组。角色在编辑视图内对齐眼高，不改变 GLB 的原点或尺寸。
2. 保留 `Basis`；选 `Sculpt` 键，值设为 1，在网格上编辑。设为 0 看最初基网格，不是本轮评审基线。其余表情键相对 `Basis`，预览原表情偏移。只有 Q 的独立发壳直接编辑网格，其隐藏对象 `| original` 可显示对照；主角的原刺束有可编辑的 `Sculpt`，不再用连续发壳。除 Q 发壳外不改顶点次序、三角形或对象标识。
3. 本文件是头部编辑源，不是完整绑定场景。四个审看角色的完整 `.blend` 在 [`classmates`](../classmates/) 和 [`teacher_b`](../teacher_b/)，沿用原重建指令。分件映射回同一雕刻层，不再从 Blender 重新导出全身 GLB。

从仓库根目录取八份精确输入。`BASE` 是最初雕刻前的运行 GLB，`REVIEW_BASE` 是本轮对照用的已整合版本（`fd11c183249ef43730fc2fdf36be77cf10669974`）。浅克隆缺快照时使用 `git fetch --no-tags --depth=1 origin <SHA>`。

```sh
PYTHONPATH=tools python3 - <<'PY'
from pathlib import Path
from subprocess import check_output
from character_sculpt import BASE, REVIEW_BASE, RUNTIME
for folder, ref in [('basis', BASE), ('previous', REVIEW_BASE)]:
    out = Path('build/sculpt') / folder
    out.mkdir(parents=True, exist_ok=True)
    for role, path in RUNTIME.items():
        (out / f'{role}.glb').write_bytes(check_output(['git', 'show', f'{ref}:{path}']))
PY

# Bake from the edited Blender file. Do not omit --export unless recreating the
# original brush layout into a separate --blend target; that would replace edits.
blender -b -t 2 --python-exit-code 1 -P art/character_models/sculpt/make_sculpt.py -- \
  --bases build/sculpt/basis --export

# Reinstall the baked streams; no Blender needed for this phase.
python3 tools/character_sculpt.py lead art/character_models/sculpt/lead_basis.glb \
  assets/models/protagonist/Protagonist_Character.glb
python3 tools/prepare_q.py
python3 tools/prepare_teacher_n.py
python3 tools/prepare_classroom_student.py
# Rebuild classmates and B with their existing pinned donor and source drivers.
```

`layers.json.gz` 记录来自 Blender 的位置与法线、Q 发壳索引，以及用于拒绝不匹配基线的几何指纹。其他网格仍用原索引，法线按实际局部形变旋转。其余 accessor，包括表情键的索引和值、顶点色、权重、inverse binds 和原动作 key，保持原字节。坐姿 GLB 仍登记原有 `KHR_materials_specular` 扩展，不改材质字段。

## 同条件复拍和回归

```sh
blender -b -t 2 --python-exit-code 1 -P art/character_models/sculpt/render_review.py -- \
  --comparison-base fd11c183249ef43730fc2fdf36be77cf10669974 \
  --bases build/sculpt/previous --out build/sculpt/frames --close --expressions
python3 tests/character_sculpt_test.py
```

每位角色的两版共用机位、灯光、焦距和帧，`--close` 放大五官；彩色使用原 GLB 材质，棚拍降低非玻璃高光，不改游戏着色。`--expressions` 只拍现成的闭眼、张口、松唇、笑或抬眉（以各模型支持为准）。`LipRelease` 是松唇，不是口型；N 与坐姿学生没有源表情键，B 只有闭眼。`MANIFEST.json` 记录两版 GLB 的 SHA-256 与实际启用的键。棚拍不入 Git，也不当作 Godot 画面。用原教室、同学和 B 审看场景另看运行时面孔；主角从侧面按住方向键走路，和小跑、坐下、起身区分开验收。

## 3D 精修的独立来源记录

所有新增网格编辑是本仓库制作（Arena 编码辅助，平台未显示具体模型版本）。主角的刺束来自既有 `lead_basis.glb`；The Cure 的主唱 Robert Smith 只作为凌乱、向外炸开的剪影参考，不拷贝照片、材质或面部特征。`lead_basis.glb` 是最初固定基线的主角运行副本，不是找到的原作者 Blender 源；SHA-256 为 `80239a44cbbfdd6eebf560750a904a124e1d0db8f2e503db67150dc1ea60c09d`。Q、N、坐姿三份 `*_source.glb` 保持原字节。三同学和 B 只沿用已固定的 [MakeHuman CC0 1.0 图形数据](https://github.com/makehumancommunity/makehuman/blob/1f508f6083b2f823dab15de924b3bde72e08d77c/LICENSE.md)；无新 donor、MakeHuman 应用代码或成品模型。无新外部素材入库，既有权利状态与发布范围不变；美术仍待所有者验收。
