# 八位角色：Blender 头发与面部精修

本轮只改 3D 头部几何。正式角色仍走原包装，三位同学和 B 仍限审看；不改对话肖像、服装、动作、灯光、材质字段、场景放置或发布排除。对照基线为 `25c3410c90a1825337f671648d42c344dbeb1416` 的**实际运行 GLB**。样例人偶、重定向测试用模型和布景中的箱形人不在此轮范围内。

| Blender 集合 | 角色 / 用途 | 本轮几何 |
| --- | --- | --- |
| `LEAD` | 主角 / 正式 | 碎刺改为一整块贴头的发壳，以几束长短不同的偏扫尖峰保留凌乱感；收平眼睑和眼球的凸度，理顺眼窝、鼻翼及下巴。 |
| `Q` | Q / 正式 | 一体短发、较低的额前发际和错开的短脊；眼睑与眼球一起减深，保留较圆的脸、原有嘴角和话多的神态。 |
| `N` | 代课老师 / 正式 | 保留短波波头和原发顶，把贴在脸侧的尖片向耳后、向内收；理顺窄面部的眼下、鼻梁和唇下。 |
| `SEATED` | 坐姿学生 / 正式 | 顺着斜分修额发和后脑的连接，轻压鼻尖，修脸颊和下巴；不单移原有低浮雕眼片。 |
| `THIN` | 薄瘦同学 / 审看 | 沿同一连续头皮修短发渐层和额角，不添加假发壳；加强清瘦的脸颊转折。 |
| `GENTLE` | 好友 / 审看 | 加深侧分沟、理顺扁弧形梳痕；颧部和嘴角依旧偏圆软，眼镜保留。 |
| `COURT` | 球场同学 / 审看 | 把红色高发冠偏向一侧、捏合发脊；轻修眉弓、下颌和不对称嘴角。 |
| `B` | B 老师 / 审看 | 理顺银发偏分到低发髻的体块，保留脸的棱角、眼镜、年龄特征和原发顶高度。 |

## 打开、编辑、烘焙

1. 在 **Blender 4.5 LTS** 打开 [`Head_Studies.blend`](Head_Studies.blend)（制作及复烘用 **4.5.3**）。在 Outliner 只显示一位角色；局部对象按 Hair / Face / Eye / Ear 分组。为方便比较，角色在编辑视图内对齐眼高，不改变 GLB 的原点或尺寸。
2. 保留 `Basis`；选中 `Sculpt` 键，值设为 1，在网格上编辑。设为 0 可看基准。其余表情键仍相对 `Basis`，用来预览原相对偏移。除了主角和 Q 的独立发壳，不改顶点顺序、三角形或对象标识。两顶新发壳直接编辑网格；相邻隐藏的 `| original` 保存旧发件，仅供查看。
3. 这是头部编辑源，不是完整绑定场景。四个审看角色的完整 `.blend` 在 [`classmates`](../classmates/) 和 [`teacher_b`](../teacher_b/)，沿用现有重建指令。审看版 `.blend` 从同一雕刻层映射回原分件，不另走一趟 Blender → GLB 全身导出。

从仓库根目录取精确基线。浅克隆缺基线时，先 `git fetch --no-tags --depth=1 origin 25c3410c90a1825337f671648d42c344dbeb1416`。

```sh
PYTHONPATH=tools python3 - <<'PY'
from pathlib import Path
from subprocess import check_output
from character_sculpt import BASE, RUNTIME
p = Path('build/sculpt/before')
p.mkdir(parents=True, exist_ok=True)
for role, path in RUNTIME.items():
    (p / f'{role}.glb').write_bytes(check_output(['git', 'show', f'{BASE}:{path}']))
PY

# Bake from the edited Blender file. Do not omit --export unless regenerating the
# original brush layout into a separate --blend target; that would replace edits.
blender -b -t 2 --python-exit-code 1 -P art/character_models/sculpt/make_sculpt.py -- \
  --bases build/sculpt/before --export

# Reinstall the baked head streams; no Blender needed for this phase.
python3 tools/character_sculpt.py lead art/character_models/sculpt/lead_basis.glb \
  assets/models/protagonist/Protagonist_Character.glb
python3 tools/prepare_q.py
python3 tools/prepare_teacher_n.py
python3 tools/prepare_classroom_student.py
# Rebuild classmates and B with their existing pinned donor and source drivers.
```

`layers.json.gz` 记录来自 Blender 的位置与法线、受限发壳索引，以及用于拒绝不匹配基线的几何指纹。非换拓扑面仍用原索引，法线从原来的 split normals 按实际局部形变旋转。发壳是带内收回边的单个封闭壳，沿用各自 `Head` 刚性绑定。其余 accessor，包括稀疏 morph 的索引和数值、顶点色、权重、inverse binds、动画 key，保持原字节。坐姿 GLB 补上既有 `KHR_materials_specular` 的扩展声明，未修改材质字段。

## 同条件复拍和回归

```sh
blender -b -t 2 --python-exit-code 1 -P art/character_models/sculpt/render_review.py -- \
  --bases build/sculpt/before --out build/sculpt/frames --expressions --clay
python3 tests/character_sculpt_test.py
```

两版各拍正面、37°、86°、背面和统一泥模三分之四。固定每位角色的机位、灯、焦距和帧；彩色从各自原 GLB 读入，棚拍统一降低非玻璃高光；泥模是棚拍对照用的统一材质。两者均不改游戏材质或贴图。带表情的脸另拍相同机位下的中性态与可用的闭眼或张口最大权重；`LipRelease` 是松唇，不是口型动画。N 和坐姿学生没有源表情键，B 只有闭眼。`MANIFEST.json` 记录每个镜头的输入 SHA-256 和实际启用的键。渲染不入 Git，也不当作 Godot 画面。继续用原来的课堂、同学及 B 审看场景验收游戏渲染和连续动作。

## 本次 3D 精修的独立来源记录

所有新增网格笔刷、发壳和 Blender 编辑层均为本仓库制作（Arena 编码辅助，平台未显示具体模型版本），无新外部网格、贴图、肖像、角色动作或参考图入库。`lead_basis.glb` 是从上述固定基线保存的主角运行副本，不是找到的原作者 Blender 源；其 SHA-256 为 `80239a44cbbfdd6eebf560750a904a124e1d0db8f2e503db67150dc1ea60c09d`。Q、N、坐姿三份 `*_source.glb` 保持原字节。三同学和 B 只沿用已固定的 [MakeHuman CC0 1.0 图形数据](https://github.com/makehumancommunity/makehuman/blob/1f508f6083b2f823dab15de924b3bde72e08d77c/LICENSE.md)；本轮无新 donor、无 MakeHuman 应用代码或成品模型。既有源文件的权利状态、认可范围和发布限制不因本轮变更。无档案室、UAL 或对话肖像出处变更；仍待所有者美术验收。
