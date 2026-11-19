# 原生移动端：构建、安装与验收

移动版和桌面版共用场景、剧情、寻路、记录和存档格式。不需要网络或常驻服务。本页描述构建入口及验收要求；实际通过哪些检查，以对应提交的 CI 产物和真机记录为准。

## 操作与屏幕

- 双向横屏；不支持竖屏游玩。场景铺满窗口，菜单、对话和 HUD 按系统安全区排版，避开刘海、圆角和系统手势区。Android 保留系统栏；不劫持 Home 手势。
- **点地面**走路，**点物件或人物**走近后互动。近处有合法目标时，右下方出现“使用 / 交谈”。拖动和双指不会发出走路指令，移动设备的模拟鼠标不应重复触发游戏行为。
- **右上角菜单**打开暂停、笔记、设置和既有的保存并退出（回到标题）。对话用底部的“继续”；打字中先补完本句。长文本可上滑，长选项列表用 `‹`、`›` 翻页。对话记录、笔记、设置各有触摸返回入口。Android 系统返回先关闭最上层界面；游玩中默认打开暂停菜单，而不是直接退出。
- 手机基准画布按实际窗口展开；触摸控件目标为至少 48 个逻辑点（Android dp / iOS pt）。设置中的文字大小仍可调整，不显示桌面的窗口/全屏选项；键鼠和手柄仍走原有输入绑定。
- Android 以 GLES 3 Compatibility 渲染覆盖较旧设备，iOS 使用 Mobile/Metal。移动版限制 60 FPS 上限，并独立降低 3D 渲染比例，避免降低 2D 文字分辨率。这不是帧率保证；场景的雾、阴影、材质与性能须在目标 GPU 上复核。

## 一次配置，重复构建

从包含移动支持的 **干净 Git checkout** 构建。使用 `.godot-version` 对应的 **标准版** Godot 和同版本官方导出模板。准备 Python 3.11+ 和 Git；下列命令在项目根目录执行，`godot` 应在 `PATH`，否则传 `--godot /path/to/godot`。构建脚本在临时目录使用 Git 跟踪的游戏文件，不修改项目预设或当前游戏的 `user://`。每个输出位置须为空，防止把上次的包误当本次产物。`BUILD.json` 记录源码提交、工作区是否改动、Godot 版本、版本号和单个包的 SHA-256。

### Android：APK

1. 安装 JDK 17、Android SDK Command-line Tools、`platform-tools`、`platforms;android-36` 与 `build-tools;36.1.0`，同意 SDK 许可。设置 `JAVA_HOME`、`ANDROID_HOME`。若本机 Godot 已配置其他路径，在 Editor Settings → Export → Android 检查与当前工具一致。使用官方预编译模板，不需要 Gradle 工程或 Android 插件。
2. 生成可侧载测试包（Android 7 / API 24 起，GLES 3；打包 ARM64 和 x86_64）。安装时可能需要为文件管理器允许“安装未知应用”，或打开 USB 调试用 `adb`：

   ```sh
   python3 tools/export_mobile.py android-preview --build 1 --output build/mobile/android-test
   adb install -r build/mobile/android-test/where-is-school-preview.apk
   ```

   测试包使用调试证书，应用 ID 为 `io.github.braineno.whereisschool.preview`。它与正式版分开安装和存档。CI 的调试证书不承诺跨运行保持一致；签名不同时 Android 拒绝覆盖。不要为更新而随意卸载有存档的安装。
3. 正式包：在受控发布机以环境变量提供 `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`、`GODOT_ANDROID_KEYSTORE_RELEASE_USER`、`GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`。不要把实际值、密钥库或凭据写入仓库或日志。保留正式应用 ID `io.github.braineno.whereisschool`、签名私钥和备份，并为每次发布增加 `--build`：

   ```sh
   python3 tools/export_mobile.py android-release --build 42 --output build/mobile/android-release-42
   ```

   这个入口验证 APK 签名、版本、ABI 和运行时内容。它不上传商店；Play 分发所需的 App Bundle/Play App Signing 是独立发布流程。本项目不承诺 ARM32 手机支持。

### iOS：Xcode 工程、无签名归档、签名 IPA

- 可审查的 **Xcode 工程**（旁边的 `.pck` 与 framework 也必须带上）：`python3 tools/export_mobile.py ios-project --output build/mobile/ios-project`。
- 在 macOS 的 Xcode 上，**无签名设备归档**：`python3 tools/export_mobile.py ios-unsigned --build 1 --output build/mobile/ios-unsigned`。它验证 ARM64、系统版本、横屏声明、iPhone/iPad 家族和游戏资源。这个 `.xcarchive` 不是可安装 IPA，也不是 iOS 模拟器构建。
- **有签名 IPA**：在受控 Mac 上安装 Xcode、证书与对应 provisioning profile，通过 `xcode-select` 选定 Xcode。确保 Apple Team 已注册 `io.github.braineno.whereisschool`，或在首发前统一定稿应用 ID 并更新包校验。使用本机 `IOS_TEAM_ID` 或 `--team`；从同团队的 Xcode 分发流程准备本机 `ExportOptions.plist`。签名步骤使用 Xcode 自动签名的归档与本机证书；脚本不登录账号、不自动上传。iOS 应用最低系统版本为 15.0，目标包括 iPhone 和 iPad。

  ```sh
  python3 tools/export_mobile.py ios-ipa --build 42 \
    --export-options /path/to/ExportOptions.plist --output build/mobile/ios-release-42
  ```

  得到的 `.ipa` 在 `ipa/` 子目录下。能否在某一台手机上安装由分发方式与 profile 决定：Development / Ad Hoc 要授权对应设备；App Store Connect / TestFlight 的包需走对应分发渠道，不是把文件发给任意 iPhone 就能安装。不要把证书、私钥、设备清单或 provisioning profile 发到 PR。首发前确认 Apple 当期 SDK/隐私清单/商店审核要求。

## 每次改动与设备验收

`Native mobile` 工作流对影响游戏和构建的 PR 运行（也可手动运行）。它用官方桌面引擎注入触摸回归，用真实 APK 跑 Android 模拟器启动，用 Xcode 构建设备归档。Actions 测试产物有保留期限，不是正式发行版。无签名验证不需要 Apple 账号，不接触发布密钥。正式发布用本地签名入口；不要把发布凭据交给来自 PR 的工作流。

| 代表尺寸（横屏） | 验收重点 |
| --- | --- |
| 667×375 pt，16:9（iPhone SE 类） | 小屏大字；暂停、设置底部返回和多选项仍可达 |
| 852×393 pt 左右（刘海 / Dynamic Island 类 iPhone） | 两个握持方向，左右安全区和底部 Home 指示条 |
| 800×360 dp 左右、20:9（Android 手机） | 手势/三键导航、状态栏、低内存与持续游玩 |
| 1024×768 pt，4:3（iPad 类） | 文字不贴边，布局不拉伸，摄像机与点击命中一致 |

桌面几何与触摸回归并不替代上述设备；测试用尺寸和 inset 是合成值而不是机型认证。新提交或引擎更新后，至少在一部 ARM64 Android 和一部有底部手势区的 iPhone 真机完成以下步骤。再用窄屏和 iPad 复核边缘条件：

1. 全新安装、无网络启动；切中英文及最大字号、调整音量，确认关闭与重开设置时可读可达。
2. 只用触摸从标题进游戏 → 主角起身 → 点地面寻路 → 点人物、物件和门走近互动。检查拖动、双指、长按后移出和遮挡时不会误触。
3. 对话补字、继续、自动、跳过、多选、翻页、长文滑动、打开和关闭记录。菜单暂停、笔记过滤与返回。前后台切换、系统返回、反向横屏时检查没有残留触点、自动推进或叠层错位。
4. 走到一个保存点，返回标题、杀进程重启、从存档继续。用同签名及更高构建号覆盖安装复验；移动 OS 在后台终止进程时回到最近的既有保存点，不承诺保存过场中途。
5. 在教室、走廊和室外持续游玩至少 15 分钟，记录机型、OS、画质、帧时间、发热、内存和崩溃。做不到稳定游玩先调整渲染预算再提最低设备承诺。桌面 Forward+ 与原有存档回归仍由桌面工作流负责。
