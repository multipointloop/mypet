# MyPet 🐾 猫娘桌宠

> 基于一张静态立绘，用「自动抠图 → 分层 PNG → 代码驱动 Transform」实现全部动效的跨平台桌宠。
>
> **当前状态：Windows 端功能完整可用；Android 端为悬浮窗雏形（可运行，功能未对齐，开发暂缓）。**

![预览](source_assets/pet_preview.jpg)

## 功能特性

### 桌面形态（Windows）
- 透明无框、始终置顶、不进任务栏（Flutter + Win32 + DWM）
- **真·鼠标穿透**：穿透态下桌宠隐藏、只留「小眼睛」按钮，被遮挡区域的点击**真正落到下层应用**（跨进程，`SetWindowRgn` 窗口区域实现）
- 系统托盘：**左键单击**开/关设置面板；**右键**弹出原生简易调整栏（放大/缩小/鼠标穿透/设置面板/退出）
- 全局热键：`Ctrl+Alt+↑/↓` 缩放、`Ctrl+Alt+T` 穿透、`Ctrl+Alt+S` 设置面板
- 原生拖拽（HTCAPTION，零重影）+ 可选「松手重力下落」，落点贴合工作区底边
- 尺寸 0.35–2.5×，**上限按屏幕工作区自动换算**（不会出现腿部被切）

### 交互与动画
- **视线追踪**：`GetCursorPos` 自适应轮询（移动 60fps / 空闲 30fps），眼球 + 头部实时跟随；零钩子、零杀软风险
- **点击分区判定**：头 / 身体 / 尾巴 / 裙子以下
  - 头 —— 跳起 + 瞪眼 + 摇尾（音效「弹跳」）
  - 身体 —— 压扁回弹
  - 尾巴 —— 阻尼摆尾（「嘶嘶」）
  - 裙子以下 —— **「跳一跳」式折叠**：3 秒蓄力下沉 → 1 秒 Q 弹复位（带过冲）
- 闲置：呼吸起伏、随机眨眼、90 秒打瞌睡（半闭眼 + Zzz）
- 台词气泡：打字机效果、闲置随机弹出；**文案可在设置面板逐条自定义**
- **Bongo Cat**：C++ 全局键盘钩子（`WH_KEYBOARD_LL`，默认关闭）→ 左右猫爪拍击 + 音效；4 声部轮转，极速连击不丢音
- 常态/穿透态双透明度可调

### 设置面板
单窗口双形态：主窗口内切换为 640×460 面板（左侧控件 + **右侧实时预览**），关闭后按「脚底不动」还原，不闪不跳。

### 诊断
- 诊断日志（可开关）：`%APPDATA\com.mypet\mypet\logs`，单文件 2MB × 5 滚动，面板内可一键打开

> ⚠️ **平台差异**：以上均为 Windows 端行为。Android 端目前只实现「悬浮窗 + 触摸视线 + 基础设置」，无托盘/穿透/Bongo，且尚未做真机回归。

## 技术栈

| 层 | 技术 |
|---|---|
| UI / 业务逻辑 | **Flutter 3.47**（Dart 3.13），单代码库产出 Windows `.exe` 与 Android `.apk` |
| Windows 原生 | **C++**（Flutter Windows embedding）：`WH_KEYBOARD_LL` 全局键盘钩子、`RegisterHotKey` 热键、`WM_NCHITTEST` 区域命中、`SetWindowRgn` 跨进程穿透 |
| 窗口能力 | `window_manager`、`flutter_acrylic`（DWM 透明）、`system_tray`、`launch_at_startup` |
| 音频 | `audioplayers`（声部池 + 音源复用） |
| 存储 | `shared_preferences`（含自定义台词的 JSON） |
| 素材管线 | Python 3.11 + rembg(u2net) + Pillow + numpy（抠图 / 切层 / 边缘羽化 / 合成音效 / 图标） |

## 效果展示

<!-- 把截图/动图放进 docs/images/ 后替换下列路径 -->
| 桌宠 | 设置面板 | 穿透态 |
|---|---|---|
| ![桌宠](docs/images/pet.png) | ![设置面板](docs/images/settings.png) | ![穿透态](docs/images/passthrough.png) |

## 快速开始（Windows）

解压 `dist/MyPet-Windows-1.0.1.zip` → 双击 `mypet.exe`：

1. 桌面出现桌宠，托盘出现图标
2. 托盘**左键单击**打开设置面板；**右键**打开简易调整栏
3. 需要穿透时：面板开关 / `Ctrl+Alt+T`（穿透后桌宠隐藏，点屏幕上仅剩的「小眼睛」或再按 `Ctrl+Alt+T` 恢复）

## 本地构建

### 前置依赖

| 组件 | 版本 / 说明 |
|---|---|
| Flutter SDK | 3.47.x stable（Dart 3.13+） |
| **Visual Studio 生成工具 2022** | **必须**勾选「使用 C++ 的桌面开发」工作负载（含 MSVC v143 / CMake / Ninja）。只装 VS Code 或只装 .NET **无法**构建 Windows 端 |
| Windows 10/11 SDK | 10.0.26100 或相近版本（随上述工作负载安装） |
| JDK 17 | 仅 Android 构建需要 |
| Python 3.11 | 仅素材管线需要（rembg / onnxruntime / pillow / numpy） |

### 构建命令

```
# 1) 确认工具链：Visual Studio 那一行必须显示 √
flutter doctor -v

# 2) 拉取依赖
cd mypet
flutter pub get

# 3) 构建
flutter build windows --release   # 产物：build\windows\x64\runner\Release\
flutter build apk --release       # Android（可选，需 JDK17 + Android SDK）
```

### 踩坑记录（本项目实测）

- **`Unable to find suitable Visual Studio toolchain`** —— 没装 VS 的 C++ 工作负载（装 VS Code 不算）。装「Visual Studio 生成工具 2022」并勾选「使用 C++ 的桌面开发」即可。
- **`path_provider_foundation >= 2.5` 会打断 Windows 构建**（其 `objective_c` native-assets 钩子）：`pubspec.yaml` 已用 `dependency_overrides` 钉在 2.4.1，**请勿删除**。
- **不要给 `windows/runner/*.cpp|h` 添加中文注释**：MSVC 未开 `/utf-8` 时会按 GBK 误解析并吞掉下一行（本项目原生菜单文案一律用 unicode 转义写死，源文件保持纯 ASCII）。
- Android SDK 路径含空格会被 `flutter doctor` 警告，但实测不影响构建。

### 素材管线（改图时才需要）

```
cd tools
python cutout.py       # source_assets/1.jpg -> source_assets/pet_full.png（rembg 抠图，保持原画布）
python slice.py        # 按 assets/rig.json 切 5 图层 + 眼底修补 + 边缘羽化
python make_icon.py    # 头部裁剪 -> assets/icon/icon.png + tray.ico
python gen_sounds.py   # 合成占位音效
```

图层裁剪框、锚点、点击命中区**全部由 `mypet/assets/rig.json` 驱动**，可用 `tools/coord_picker.html` 在浏览器里拖拽微调——**改图、改坐标都不需要改代码**。

## 目录结构

```
.
├─ mypet/                  Flutter 工程（应用本体）
│  ├─ lib/
│  │  ├─ core/             rig 解析、分层渲染、配置持久化、日志、音频
│  │  ├─ features/pet/     引擎（视线/眨眼/反应/折叠/物理）、宿主页、气泡、台词
│  │  ├─ features/settings/设置面板（Windows）与设置页（Android）
│  │  └─ platform/         win（窗口服务/光标轮询/原生通道）、android（悬浮窗）
│  ├─ windows/runner/      C++ 原生层（键盘钩子、热键、命中测试、窗口区域）
│  ├─ android/             Android 工程（签名配置不入库）
│  ├─ assets/              rig.json、5 张图层 PNG、音效、托盘图标（参与打包）
│  └─ test/                单元测试
├─ tools/                  素材管线（Python）与坐标取点器
├─ source_assets/          原始立绘与抠图结果（不参与打包）
├─ docs/                   设计文档、构建手册、素材指南、自测清单
└─ dist/                   交付产物（不入库）
```

## 素材与自定义

- **改台词**：设置面板 → 台词（气泡），或直接编辑 `mypet/lib/features/pet/dialogue_lines.dart`
- **换音效**：同名覆盖 `mypet/assets/sounds/`（`bounce.mp3` / `click_body.wav` / `click_tail.wav` / `key.wav` / `land.wav` / `mew.wav` / `charge.wav` / `swoosh.wav`）后重新构建
- **换立绘**：替换 `source_assets/1.jpg`，依次执行 `cutout.py` / `slice.py` / `make_icon.py`（详见 `docs/ASSET_GUIDE.md`）

## 常见问题

| 现象 | 处理 |
|---|---|
| 桌宠被任务栏遮挡 | 置顶只在普通窗口层，任务栏可覆盖脚部；拖到屏幕上方即可 |
| 穿透后点不到桌宠 | 设计如此：点「小眼睛」按钮 / `Ctrl+Alt+T` / 托盘菜单恢复 |
| 键盘互动无反应 | Bongo Cat 默认关闭（防杀软误报与反作弊冲突），在面板中开启 |
| 眼睛不追鼠标 | 追踪基于 `GetCursorPos` 轮询；穿透态不影响。若仍不追，请查看日志 |
| 想排查异常 | 设置面板 → 系统 →「打开日志目录」（`%APPDATA\com.mypet\mypet\logs`） |

## 开源协议

本项目采用 **MIT License**，详见 [LICENSE](LICENSE)。

> 注：`source_assets/1.jpg` 为个人使用的立绘素材，二次分发前请自行确认素材版权。
