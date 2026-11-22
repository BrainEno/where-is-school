# 01 教学楼外墙涂鸦

**来源与使用范围：** 照片 `IMG_1689.jpeg` 由项目所有者提供（SHA-256 `0969fac90558b11a78362c57bff73a30ba31138eb72e556e335737d3ea7720ae`），按其要求做成游戏内墙绘，并将处理后的游戏资源提交到本项目。处理过程未加入外部图像、生成式改绘或额外叙事文本；原照片和拍摄元数据不入库。入库范围仅限本项目的衍生资源，不据此确认原稿权属、单独再许可或商业发行许可。

## 放置与查看

- `corridor` 的教学楼 **01 层**，双玻璃门外沿着通往马棚的小路走。涂鸦在玻璃门西侧原有的玫瑰色灰泥上，不挡台阶、门或路牌。从街道返回双玻璃门外即可找到，开发版也可直接运行 `scenes/dev/school_room_tour.tscn`。
- 鼠标点画、触屏轻点，或走到外墙前面朝它按 **E（互动）**。使用「看看」后镜头滑向画面并停留数秒，随后自动返回跟随视角。站在内侧不能隔墙用 E 看画。无对白、剧情标记、存档或碰撞变化。
- `tools/build_teaching_block.py` 将 `wall_graffiti.tscn` 挂在 `EntranceWallWest` 下。颜料面离灰泥表面 4 毫米，不投影。平时和墙体一起淡出；查看时用 `CameraShot` 保持灰泥不透明，避免透出背后的室内。静默特写流程和售票员共用。

## 复现

原照片由作者单独保管。使用本地 Pillow、NumPy、SciPy 提取原笔迹；去掉纸底、加粗笔触，给边缘加由固定种子生成的细颗粒与雾边。透明底 PNG 为 896 × 1032，等比放在约 1.30 × 1.50 米的墙面上；原来的眼睛、锯齿、交叠线和小图案位置不变。`wall_graffiti_ink.tres` 由有颜料的像素块合并而来，悬停复用游戏的暖色轮廓，不描一个假画框。

在按 [`tools/requirements.txt`](../../../tools/requirements.txt) 安装的工具环境中运行。只想对照入库资源时，可加 `--output /path/to/scratch`，不覆盖项目资源。

```sh
python3 art/teaching_block/graffiti/prepare_wall_graffiti.py /path/to/IMG_1689.jpeg
python3 tools/build_teaching_block.py --check
godot --headless --path . --script res://tests/wall_graffiti_test.gd
godot --headless --path . --script res://tests/wall_graffiti_test.gd -- --mobile-preview
```

在有窗口的 Godot 上运行同一脚本可截下入场与特写，输出到仓库忽略的 `builds/`：

```sh
godot --path . --resolution 1600x900 --script res://tests/wall_graffiti_test.gd \
  -- capture=builds/wall-graffiti-review
```
