# 原生移动端：构建、安装与验收

移动版和桌面版共用场景、剧情、寻路、记录和存档格式。不需要网络或常驻服务。本页描述构建入口及验收要求；实际通过哪些检查，以对应提交的 CI 产物和真机记录为准。

## 操作与屏幕

- 双向横屏；不支持竖屏游玩。场景铺满窗口，菜单、对话和 HUD 按系统安全区排版，避开刘海、圆角和系统手势区。Android 保留系统栏；不劫持 Home 手势。
- 进入可操作的游玩画面后，**左下角摇杆**按住即可移动，拖动可连续转向，松手即停。**点地面**仍可自动走路，**点物件或人物**仍可走近互动。摇杆正在转向或移动时不会排队自动走路；另一根手指仍可点选触手可及的目标，或按右下角的互动键。互动键无目标时置灰，不会把点击传到地面。有键鼠、手柄或容器的指针事件也不会隐藏触控；键盘或手柄接管、弹出对话、切后台或转屏时，摇杆不保留上一手势。
- **右上角「暂停」**打开紧凑暂停卡，突出「继续游戏」；其余常用入口能排两列就并排，大字或较窄时可滚动。HUD 上的「主菜单」与暂停页的「返回主菜单」使用同一个安全确认；「继续游戏」关闭确认并续玩当前内容。只有空闲稳定时才保存当前进度；对话、过场或保存失败时会提示此前存档或无存档。桌面仍通过 Esc（手柄 Start）打开原暂停布局。手机标题、设置和确认框也收紧尺寸，不改变对话字级和 48 点的触控目标。
- 对话用底部的“继续”；打字中先补完本句。长文本可上滑，长选项列表用 `‹`、`›` 翻页。对话记录、笔记、设置各有触摸返回入口。Android 系统返回先关闭最上层界面；游玩中默认打开暂停菜单，而不是直接退出。
- 手机基准画布按实际窗口展开；触摸控件目标为至少 48 个逻辑点（Android dp / iOS pt）。设置中的文字大小仍可调整，不显示桌面的窗口/全屏选项；键鼠和手柄仍走原有输入绑定。
- Android 以 GLES 3 Compatibility 渲染覆盖较旧设备，iOS 使用 Mobile/Metal。移动版限制 60 FPS 上限，并独立降低 3D 渲染比例，避免降低 2D 文字分辨率。这不是帧率保证；场景的雾、阴影、材质与性能须在目标 GPU 上复核。

## 在 iPhone 上打开剧情编辑

普通 iOS 包默认关闭编辑工具。进入 **设置 → 编辑模式 → 剧情编辑**，轻点开关；出现「已保存」后点「完成」。从暂停菜单选择 **剧情编辑** 打开编辑面板，回到游玩后也可使用画面上的编辑入口。重启仍保留开关；关闭会移除入口和编辑层，但不删除已保存的草稿。编辑草稿存于 `user://story_editor/`，不会改写剧情源文件或游玩存档。设备包支持通过系统「文件」交换草稿；普通 iOS 模拟器可验证开关和面板，但没有设备 Files bridge。Android 和桌面发行包不带该工具。

## 在 GitHub Actions 点击构建

两个工作流**相互独立**，可以同时触发。没有跨平台 `needs`、共享排队组或发布上传步骤。

| Actions 工作流 | 怎么用 | 成功产物 |
| --- | --- | --- |
| [Build Android APK](../.github/workflows/build-android.yml) | **Run workflow** → 选分支 → **Run workflow**；不需要签名配置 | 解压 `android-preview-apk-*` 得到 `where-is-school-preview.apk` 和 `BUILD.json`。同一个 APK 已通过 API 36 模拟器安装和启动测试。 |
| [Build iOS IPA](../.github/workflows/build-ios.yml) | 配置一次 `ios-signing`（见下文）；**Run workflow** → 选 `main` → 选与 profile 一致的 `development` 或 `ad-hoc` | 解压 `ios-signed-ipa-*`，在 `ipa/` 取签名 `.ipa`。只能装到描述文件里的 iPhone/iPad，不会上传 TestFlight。 |

`build_number=0` 使用各工作流自己的运行号。装过更高构建号时请显式填写更大的号码。
工件保留 14 天；`BUILD.json` 记录源码 SHA、引擎版本、版本号和文件 SHA-256。
Android 出包先检查签名和 Godot 稀疏索引中**每项**资源的路径、大小和哈希，再用真实 APK 检查
渲染和前台。iOS 打包后重新校验 IPA 内应用的签名、设备架构和游戏包。两边都不会用未验证工件替代成品。

日常改动不自动打两套包。`Mobile input regression` 在桌面 Godot 注入多指触控并验证手机/平板安全区（包含竖屏缩放夹具，不改变安装包的横屏限制），同时上传真实运行渲染的游戏画面、紧凑暂停卡、确认框和返回后的主菜单 PNG。这个工件不是 iOS 模拟器或真机验收；实体设备仍须验证系统手势、后台恢复、两种横屏方向和持续多指触控。只有
修改移动打包/工具链时，`Mobile build tooling validation` 才额外执行 Android 构建、Mac
模拟器及无签名归档、Windows ADB 脚本检查；该 PR 工作流不接触任何签名密钥。

### 首次配置签名 IPA（仓库所有者）

1. 在 Apple Developer 注册显式 App ID `io.github.braineno.whereisschool`，把要安装的设备加入
   对应的 **Development** 或 **Ad Hoc** profile。准备同一 Team 和 profile 授权的 Apple Development
   或 Apple Distribution 证书（带私钥、导出为密码保护的 `.p12`），以及未过期的 `.mobileprovision`。
2. 在 GitHub **Settings → Environments** 建立 `ios-signing`，把部署分支限制为 `main`，有条件时启用
   必须审阅。仅在这个环境设置以下 **Environment secrets**，不要放在仓库级 secrets，也不要发到聊天或 PR：

   | Secret | 内容 |
   | --- | --- |
   | `IOS_SIGNING_P12_BASE64` | `.p12` 的 Base64 |
   | `IOS_SIGNING_P12_PASSWORD` | `.p12` 的导出密码 |
   | `IOS_PROVISIONING_PROFILE_BASE64` | `.mobileprovision` 的 Base64 |

   可在自己的 Mac 用 `base64 -i /path/to/file | pbcopy` 编码并直接贴进对应 secret。团队 ID 从
   profile 读取并核对。每次变更证书/profile 后同步更新 secrets；签名作业只用临时钥匙串，退出时清理，
   不上传归档、证书、描述文件原件或钥匙串。
3. 运行 **Build iOS IPA**，必要时审批环境作业。签名 IPA 内嵌描述文件及已登记设备的 UDID。公开仓库的
   工件可被有读取权限的人下载；只在确认同意公开测试设备信息时勾选 `publish_device_profile`，否则请在
   私有仓库或受控 Mac 本地导出。缺少配置/签名失败时工作流标红，不生成“无签名 IPA”。
   解压下载，解锁授权 iPhone/iPad，用 Xcode 的 **Devices and Simulators** 或 Apple Configurator
   安装；Development 方式可能需要启用设备的开发者模式。App Store Connect / TestFlight 是另一个分发流程。

## 本地调试：Mac → iOS 模拟器

先安装完整 Xcode 和 Python 3.11+，打开 Xcode 完成首次许可与组件安装。在 Xcode **Settings → Locations**
选择完整 Xcode（或为本终端设置 `DEVELOPER_DIR`）。不需要 Apple 证书，也不会改变全机 Xcode 选择。

双击 [`tools/macos/ios/Debug.command`](../tools/macos/ios/Debug.command)，或从仓库根目录执行：

```bash
bash tools/macos/ios/debug.sh                             # 准备、选模拟器、编译、安装、启动
bash tools/macos/ios/debug.sh --setup-only                 # 只准备依赖
bash tools/macos/ios/debug.sh --setup-only --update-runtime # 让 Xcode 更新 iOS 运行时
bash tools/macos/ios/debug.sh --list                       # 获取可用机型/UDID
bash tools/macos/ios/debug.sh --device '<simulator-UDID>'  # 不再交互选机
```

若缺 iOS 运行时，脚本用 `xcodebuild -downloadPlatform iOS` 安装，并在 Xcode 支持的机型里准备默认机型。
它从官方 Godot 发布下载 `.godot-version` 对应的标准版编辑器和 iOS 模板，核对 SHA-256 后缓存；
以后工程升级引擎时会取新的固定版本，不会自动升级到未指定版本。下载较大（模板约 1.2 GB）；可以用
`--godot /path/to/Godot --no-download` 复用已安装的编辑器、模板和模拟器库。Python 不在 PATH 时设置 `WIS_PYTHON`。
Godot 4.7.2 官方 iOS 模板缺少实际的 Apple Silicon Simulator 库。首次构建遇到缺失时，脚本用 Git 取同版本、
与编辑器提交相符的官方源码，用独立环境中固定哈希的 SCons 4.10.1（MIT）编译 Debug 模拟器库。首次需要联网、
额外时间和数 GB 临时空间；结果按 Godot、Xcode、SDK 和架构缓存，只补进本次导出工程，不改全局模板或真机库。
CI 使用 `--non-interactive --no-open --shutdown`；本机默认保留模拟器和游戏。输出在
`build/mobile/ios-simulator/run-*/`，含模拟器 `.app`、Xcode 工程、日志和截图。要打断点，打开该目录
Xcode 工程，选择相同模拟器，选 **Debug** 后 Run 或附加进程。

**这是 Simulator Debug，不是 IPA。** Godot 的模拟器库没有 Metal/Vulkan；只在临时导出副本改用
Compatibility，设备 IPA 保持 Mobile/Metal。模拟器的画质或性能不能当真机结果。保留上一次输出或
显式使用空 `--output`，不会沿用旧 `.app`。

## 本地调试：Windows → Android USB 或模拟器

1. 双击 [`tools/windows/android/Setup.cmd`](../tools/windows/android/Setup.cmd)。默认在
   `%LOCALAPPDATA%\WhereIsSchool\Android\Sdk` 安装 Google Platform-Tools（ADB），无需管理员、
   Python 或 Android Studio；不改全机 PATH。`Setup.cmd -Update` 可更新，需先结束自己正在使用的 ADB 会话。
2. 下载并**解压** Actions 的 `android-preview-apk-*`。在手机上启用 USB 调试、接线并授权；需要时安装厂商
   USB 驱动。也可以先启动已配置的 Android Studio 模拟器。在 **PowerShell** 中：

   ```powershell
   .\tools\windows\android\Test.cmd -Apk "C:\Downloads\Android Build\where-is-school-preview.apk"
   # 有多个设备可用时交互选择，或按 adb devices -l 指定：
   .\tools\windows\android\Test.cmd -Apk "C:\Downloads\where-is-school-preview.apk" -Serial '<serial>'
   ```

   也可将 `.apk` 拖到 `Test.cmd` 上，或双击后输入路径（`build/mobile/` 下只有一个匹配 APK 时自动使用）。
   `Test.ps1` 在 ADB 缺失时会运行安装；如果相邻有 `BUILD.json`，会先核对 APK 哈希。脚本用 `adb install -r`，
   不卸载、不清空存档或设备日志；采集被测进程日志、前台状态和截图到 `build/mobile/android-debug/`，
   游戏留在设备上便于操作。`-NonInteractive` 拒绝不唯一的设备或包。
3. 要由脚本准备和启动专用 Android 模拟器，在 x64 Windows 启用 BIOS 虚拟化和 Windows Hypervisor Platform，
   安装 JDK 17。脚本不修改管理员设置，首次执行请确认 Android SDK 许可证：

   ```powershell
   .\tools\windows\android\Setup.cmd -Emulator -JavaHome "C:\Path To\jdk-17"
   .\tools\windows\android\Test.cmd -Emulator -Apk "C:\Downloads\where-is-school-preview.apk"
   ```

   使用自己的 SDK 根目录可传 `-SdkRoot`，配置和启动必须用同一路径。无 hypervisor 时请用 USB 真机。
   本地保留日志，不会把 USB 设备序列号、截图或存档上传到 Actions。

## 开发者直接导出（可选）

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

- 在 macOS 的 Xcode 上，可导出 **Xcode 工程**（旁边的 `.pck` 与 framework 也必须带上）：`python3 tools/export_mobile.py ios-project --output build/mobile/ios-project`。
- 在 macOS 的 Xcode 上，**无签名设备归档**：`python3 tools/export_mobile.py ios-unsigned --build 1 --output build/mobile/ios-unsigned`。它验证 ARM64、系统版本、横屏声明、iPhone/iPad 家族和游戏资源。这个 `.xcarchive` 不是可安装 IPA，也不是 iOS 模拟器构建。
- **有签名 IPA**：在受控 Mac 上安装 Xcode、证书与对应 provisioning profile，通过 `xcode-select` 选定 Xcode。确保 Apple Team 已注册 `io.github.braineno.whereisschool`，或在首发前统一定稿应用 ID 并更新包校验。使用本机 `IOS_TEAM_ID` 或 `--team`；从同团队的 Xcode 分发流程准备本机 `ExportOptions.plist`。归档按该文件选择手动或自动签名，使用本机证书；脚本不登录账号、不自动上传。iOS 应用最低系统版本为 15.0，目标包括 iPhone 和 iPad。

  ```sh
  python3 tools/export_mobile.py ios-ipa --build 42 \
    --export-options /path/to/ExportOptions.plist --output build/mobile/ios-release-42
  ```

  得到的 `.ipa` 在 `ipa/` 子目录下。能否在某一台手机上安装由分发方式与 profile 决定：Development / Ad Hoc 要授权对应设备；App Store Connect / TestFlight 的包需走对应分发渠道，不是把文件发给任意 iPhone 就能安装。不要把证书、私钥、设备清单或 provisioning profile 发到 PR。首发前确认 Apple 当期 SDK/隐私清单/商店审核要求。

## 真机验收

模拟器启动和桌面逻辑测试不代表完整手机通关或真机性能。测试 APK 不是正式发行版；如调试证书和已装包不一致，Android 会拒绝升级，不要在有存档时为绕过错误随意卸载。

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
5. iPhone 普通包确认剧情编辑默认关闭；开启、观察已保存、关掉应用重开，再从暂停菜单打开编辑。校验收起键盘、退出编辑后继续操作。关闭开关后两个入口均消失，原草稿和存档仍可用。
6. 在教室、走廊和室外持续游玩至少 15 分钟，记录机型、OS、画质、帧时间、发热、内存和崩溃。做不到稳定游玩先调整渲染预算再提最低设备承诺。桌面 Forward+ 与原有存档回归仍由桌面工作流负责。
