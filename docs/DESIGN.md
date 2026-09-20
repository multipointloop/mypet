# MyPet 猫娘桌宠 — 跨平台技术方案文档

> 单一代码库同时产出 Windows `.exe` 与 Android `.apk` 的桌宠应用。
> 素材：单张静态立绘（`source_assets/1.jpg`，992×1400）→ 自动抠图 → 分层 → 代码驱动动效。

---

## 第一步：技术栈选型对比及最终推荐

### 候选方案对比

| 维度 | **Flutter ✅** | Electron | Tauri v2 | Unity |
|---|---|---|---|---|
| Windows 透明无框窗口 | `flutter_acrylic`+`window_manager`，成熟 | 最成熟 | 良好 | 需要 hack（第三方库） |
| Windows 鼠标穿透 | `setIgnoreMouseEvents` 一行 | 一行 | 支持 | 困难 |
| Windows 托盘/自启 | system_tray / launch_at_startup | 成熟 | 需插件 | 困难 |
| **Android 悬浮窗** | `flutter_overlay_window` 成熟方案 | ❌ 不支持 | ❌ WebView 悬浮不可靠 | ❌ 无法悬浮 |
| 单代码库双端 | ✅ | ❌ 需另写 Android | ⚠️ 理论可但悬浮窗残废 | ✅ |
| 全局鼠标位置（视线追踪） | `GetCursorPos` FFI 轮询，无钩子 | 需原生模块 | 需原生模块 | 需插件 |
| 分层图像动画 | Transform/CustomPaint 原生支持 | PixiJS 可 | WebView 性能弱 | 重型 |
| 安装包体积 | ~20MB | ~120MB | ~8MB | ~60MB+ |
| 开发/构建链 | 一条命令双端 | 双工程 | Rust 工具链 | 重 |

### 最终推荐：**Flutter 3.x（stable）**

理由：唯一同时满足「Windows 透明/穿透/托盘」与「Android 悬浮窗」且保持单代码库的方案。
关键插件与版本（pubspec.lock 实际解析）：

| 插件 | 版本 | 用途 |
|---|---|---|
| flutter_acrylic | 1.1.4 | DWM 全透明窗口 |
| window_manager | 0.4.3 | 无框/置顶/穿透/位置控制 |
| system_tray | 2.0.3 | 托盘图标+菜单 |
| launch_at_startup | 0.4.0 | 开机自启 |
| audioplayers | 6.8.1 | 音效（静默容错） |
| flutter_overlay_window | 0.4.5 | Android 悬浮窗（静态 API） |
| win32 / ffi | 5.15 / 2.2 | GetCursorPos、工作区、SPI |
| shared_preferences | — | 设置持久化 |

原生扩展（`windows/runner/`，C++）：
- `win32_key_hook.cpp` — `WH_KEYBOARD_LL` 全局键盘钩子（**默认关闭**，设置页显式开关），`MethodChannel("mypet/native")` 推送 `{name, vk, down}`；附带 `Ctrl+Alt+↑/↓` 全局热键（`RegisterHotKey`）。
- 钩子默认关闭的原因：杀软对全局键盘钩子敏感、部分游戏反作弊会拒绝带钩子的进程。开启与否完全交给用户。

### 静态图动效路线

不引入 Rive/Live2D 运行时——**分层 PNG + 代码驱动 Transform**：
- 每个图层 = 一张与原图同坐标系裁出的 PNG；
- 动效 = Flutter `Transform`（位移/旋转/缩放）按帧合成，配合指数平滑；
- 优点：零额外依赖、素材即插即用（`rig.json` 驱动）、后文算法可直接迁移到 Live2D。

---

## 第二步：素材切图与分层绑定

### 2.1 自动抠图（tools/cutout.py）

`source_assets/1.jpg`（带火车站实景背景）→ `rembg`（u2net 模型，onnxruntime CPU）→
`source_assets/pet_full.png`（**保持 992×1400 原画布**，保证 rig 坐标与原图一致），
并输出棋盘格 QA 预览 `source_assets/pet_preview.jpg`。实测 alpha 覆盖率 28.3%。

### 2.2 图层切分（tools/slice.py + rig.json）

按 `rig.json` 定义的矩形裁剪框从透明大图上裁出 5 个图层：

| 图层 | 裁剪框 (x0,y0,x1,y1) | 运动能力 | z 序 |
|---|---|---|---|
| tail | 585,995 → 885,1175 | 绕尾根 ±12° 摆动 | 0（最底） |
| body | 198,615 → 872,1400 | 呼吸缩放 / 落地挤压 | 1 |
| head | 195,322 → 840,615 | 视线跟随位移+旋转 | 2 |
| eyeL | 432,505 → 492,562 | 瞳孔位移 / 眨眼压缩 | 3 |
| eyeR | 528,512 → 580,570 | 同上 | 4 |

接缝选线原则：**y=615**（下巴 y≈582 与领口 y≈619 之间）切分头/身，肩袖 y≈655 起不受影响；
双马尾整体划入 head 层随头移动（马尾跨越 y=615 接缝处的 2px 错位肉眼不可见）。

两个关键预处理：
1. **眼底修补（eyePatches）**：身体/头部层的原眼睛区域用「左右边界像素的逐行水平渐变」填充（动画面部是平涂，效果自然），眼睛图层在其上滑动，不会露出原眼睛的"鬼影"。
2. **尾巴擦除（eraseColorMask）**：body 层裁剪框包含静止尾巴像素，直接叠加会在摆尾时出现"双尾巴"。用粉色谓词 `r-g>12 ∧ r-b>6 ∧ r>170` 识别尾巴像素置 alpha=0，2px 膨胀捕食抗锯齿边缘，且**绝不侵蚀不透明非粉色像素**（保护裙边）。

### 2.3 手动精修指南（Photoshop / Live2D）

详见 [ASSET_GUIDE.md](ASSET_GUIDE.md)。要点：
- PS 抠图后按同画布导出 5 张同尺寸图层 PNG，替换 `assets/parts/*.png` 即可；
- `tools/coord_picker.html` 浏览器取点工具可在任意电脑微调 `rig.json`（锚点/裁剪框/命中区），改完重跑 `slice.py` 生效，**无需改代码**；
- 进阶：素材导入 Live2D Cubism 绑定标准 XY 参数后，可把本工程的 `RigView` 替换为 Cubism SDK 渲染器（参数映射表已预留）。

### 2.4 眼球追踪算法（lib/features/pet/pet_engine.dart）

```
输入：鼠标屏幕坐标 P（逻辑像素），眼睛锚点屏幕坐标 E
d = P - E                     // 局部向量
v = d / R                     // R = 360 × scale（归一化半径）
gazeTarget = |v|>1 ? v/|v| : v // 单位圆盘截断：方向 + 距离强度
θ = atan2(v.y, v.x)           // 极角
瞳孔位移 = (a·v.x, b·v.y) × scale     // 椭圆限幅 a=6px, b=3.5px（横宽纵窄，符合眼型）
头部跟随 = 1/3 瞳孔量 (3, 2)px + 绕颈点 rotZ = v.x × 4°
平滑：gaze += (target - gaze) × (1 - e^(-k·dt))，k=12/s
静止 3s：target 回零（视线缓缓回正）
```

**为什么用 `GetCursorPos` 轮询而不是鼠标钩子**：零杀软误报、零反作弊冲突、实现 10 行；
自适应频率：移动时 60fps，静止 500ms 后自动降到 11fps，CPU 占用趋近于零。

### 2.5 点击交互与动效

| 部位 | 音效 | 动效（spring/阻尼参数见 engine） |
|---|---|---|
| 头 | click_head + surprise | 跳起 `v₀=320px/s`、瞪眼 `+35%` 0.5s、摇尾 1.2s、50% 概率气泡 |

眨眼细节：双眼向**共享闭合线**（两眼锚点纵坐标中点）压缩，抵消原画双眼不等高的
先天差异；闭合线再跟随头部运动变换，永远贴合面部。
| 身体 | click_body | squash & stretch（压扁 12% 回弹 0.35s） |
| 尾巴 | click_tail | 阻尼正弦摆 `0.21·sin(2π·5t)·e^(-|Δ|·0.8)` 2s |

命中检测：`rig.json` 的 `regions` 矩形（头/身/尾），坐标从窗口局部反解到 rig 画布。

### 2.6 拖拽与穿透（Windows，最终架构）

**拖拽 = 原生 HTCAPTION 循环**：`onPanStart`（手势竞技场判定为拖动后）调用
`windowManager.startDragging()`，由系统合成器以光标同步频率移动窗口——
零 SetWindowPos 重影、零 Dart 每帧搬运。释放后 Future 完成，同步位置；
若开启"松手重力下落"则触发 v.y += g·dt 落体 + 底边反弹(e=0.35) + 落地音效/挤压；
默认关闭 → **拖到哪里停哪里**（垂直自由放置），双击宠物随时落回地面。

**穿透 = WM_NCHITTEST 区域穿透**（替代整窗 WS_EX_TRANSPARENT，解决"穿透后按钮
也失灵"的死锁）：C++ 层维护两个窗口本地物理像素矩形
- `pet`：宠物本体（可点、可拖）
- `button`：宠物右上的穿透开关按钮（**任何模式下都可点**）
其余像素返回 HTTRANSPARENT——点击直接落到后面的窗口。穿透开启时除按钮外
全部放行；退出途径：再点一次按钮 / 托盘菜单 / Ctrl+Alt+T。

**透明度**：常态与穿透态各一个滑杆（`windowManager.setOpacity`），设置面板可调。

### 2.7 对话气泡 / 闲置 / Bongo Cat

- 气泡：打字机 22 字/秒，点击触发 + 闲置 20–45s 随机弹出，4s 隐藏；台词池 `dialogue_lines.dart` 可自由增删；
- 闲置：呼吸 = 躯干 scaleY ±1.5%（3.2s 周期）、眨眼 = 眼层 scaleY 压缩（160ms，间隔 2–6s 随机）、90s 无交互进入打瞌睡（半闭眼 + Zzz 台词 + 呼吸幅度减半）；
- Bongo Cat：C++ 钩子推送按键 → WASD 区左手拍、其余右手拍（120ms 抬落）+ key.wav。

---

## 第三步：项目工程目录结构

```
<PROJECT_ROOT>\
├─ source_assets\           # 原始素材 1.jpg + 抠图结果 pet_full.png / pet_preview.jpg（不打包）
├─ docs\                    # DESIGN.md(本文) / ASSET_GUIDE.md / BUILD.md
├─ tools\                   # Python 3.11 素材管线（全部本地化，可重复执行）
│  ├─ requirements.txt      # rembg/onnxruntime/pillow 固定兼容区间
│  ├─ setup_env.bat         # 一键装配 py311 + pip + 依赖 + u2net 模型(E盘)
│  ├─ cutout.py             # rembg 抠图（保持原画布）
│  ├─ slice.py              # 按 rig.json 切层 + 眼底修补 + 尾巴擦除
│  ├─ gen_sounds.py         # stdlib 合成 7 个占位音效 WAV
│  ├─ make_icon.py          # 头部裁剪 → icon.png / tray.ico
│  └─ coord_picker.html     # 零依赖浏览器取点工具 → rig.json
├─ dev\                     # 全部开发环境（E盘，不碰 C 盘）
│  ├─ env.bat               # 一键注入 PATH/JAVA/ANDROID/缓存变量
│  ├─ setup_android.bat     # sdkmanager 装 platform-35/36 + licenses
│  ├─ flutter\ jdk17\ android-sdk\ py311\ models\ downloads\
│  └─ .gradle\ .pub-cache\  # Gradle/Pub 缓存重定向
├─ dist\                    # 最终交付：MyPet-Windows.zip + MyPet.apk
└─ mypet\                   # Flutter 工程
   ├─ pubspec.yaml
   ├─ assets\
   │  ├─ rig.json           # ★ 骨架配置：图层/锚点/命中区/物理参数
   │  ├─ parts\             # tail/body/head/eyeL/eyeR.png（5 个图层，参与打包）
   │  ├─ sounds\            # 7 个占位 WAV（可直接替换同名 mp3）
   │  └─ icon\              # icon.png / tray.ico
   ├─ lib\
   │  ├─ main.dart          # 三入口：Windows 桌宠 / Android 设置页 / 悬浮窗引擎
   │  ├─ core\
   │  │  ├─ rig_model.dart  # rig.json 解析
   │  │  ├─ rig_view.dart   # ★ 分层渲染器（PetPose → Transform 合成）
   │  │  ├─ config.dart     # 设置持久化 + 平台同步
   │  │  └─ audio_service.dart # 静默容错音频
   │  ├─ features\pet\
   │  │  ├─ pet_engine.dart # ★ 大脑：视线/眨眼/反应/气泡/物理 Ticker
   │  │  ├─ pet_widget.dart # Windows/Android 两种宿主页
   │  │  ├─ dialogue_bubble.dart # 气泡 + Bongo 猫爪绘制
   │  │  └─ dialogue_lines.dart  # 台词池
   │  ├─ features\settings\settings_page.dart # Windows 面板 + Android 页
   │  └─ platform\
   │     ├─ win\ window_service.dart  cursor_poller.dart  native_channel.dart
   │     └─ android\ overlay_service.dart
   ├─ windows\runner\       # + win32_key_hook.cpp/h（C++ 键盘钩子+热键）
   └─ android\              # Manifest 权限 / MainActivity 保活通道 / 签名
```

---

## 第四步：核心功能模块代码讲解

（完整代码在工程内，此处讲设计要点与关键片段）

### 4.1 分层渲染器（core/rig_view.dart）

每帧把 `PetPose`（gaze/blink/squash/wag/jump/breathe）翻译为每个图层的
`Transform`：眼睛在自身锚点上做椭圆限幅位移 + 眨眼 scaleY；头部绕颈点位移+旋转；
尾巴绕尾根旋转；身体从脚底做呼吸/挤压缩放。`Stack(clipBehavior: none)` 保证旋转出框的
尾巴尖端不被裁剪。

### 4.2 自适应光标轮询（platform/win/cursor_poller.dart）

```dart
void _tick() {
  GetCursorPos(pt);                       // Win32 FFI，无钩子
  final logical = Offset(pt.ref.x / dpr, pt.ref.y / dpr);
  if (移动) _period = 16ms;               // 60fps
  else if (静止 > 500ms) _period = 90ms;  // 11fps 省电
  onCursor?.call(logical);
  _schedule(_period);                     // 动态间隔链
}
```

### 4.3 原生键盘钩子（windows/runner/win32_key_hook.cpp）

```cpp
LRESULT CALLBACK KeyProc(int nCode, WPARAM w, LPARAM l) {
  if (nCode == HC_ACTION && g_channel) {
    const auto* info = (KBDLLHOOKSTRUCT*)l;
    if (!(info->flags & LLKHF_INJECTED)) {          // 忽略程序注入，防自激
      bool down = (w == WM_KEYDOWN || w == WM_SYSKEYDOWN);
      if (down ? g_held.insert(vk).second            // 去重自动重复
               : g_held.erase(vk) > 0)
        g_channel->InvokeMethod("onKey", ...);       // → Dart
    }
  }
  return CallNextHookEx(nullptr, nCode, w, l);
}
// 默认关闭；Dart 调 setKeyHook(true/false) 动态装卸
```

### 4.4 音频静默容错（core/audio_service.dart）

预加载时 `rootBundle.load` 探测每个音效，缺失进 `_missing` 黑名单；播放全程
try-catch，任何失败静默降级——**用户随时把真实 mp3 命名同名扔进 assets/sounds 重编译即可替换**，不存在的音效永远不会报错。

### 4.5 Android 悬浮窗与保活

- 架构：主 Activity = 设置页；`overlayMain()` 入口 = 悬浮窗引擎（独立 FlutterEngine）；
  两者经 `shareData / overlayDataListener` 双向通信（尺寸/开关实时下发）。
- 悬浮窗：`showOverlay(alignment: bottomCenter, enableDrag: true)`，系统托管拖拽，
  应用不与 WMS 抢事件。
- 保活三件套：
  1. `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_SPECIAL_USE`(API34) + 常驻低优先级通知；
  2. 设置页一键跳转 `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`（MainActivity.kt 通道）；
  3. 文档化国产 ROM 白名单步骤（MIUI/EMUI/ColorOS 四项开关）。

### 4.6 尺寸调节四通道

`Ctrl+Alt+↑/↓`（C++ 热键）· 托盘菜单 · 设置页/面板滑块 · 滚轮（预留）；
所有通道汇聚到 `Config.petScale`（0.35–2.5），窗口尺寸按
`canvas × kBasePetWidth/canvasW × petScale + 气泡区` 等比重算，宽高比恒定。

---

## 第五步：Windows / Android 打包部署

详见 [BUILD.md](BUILD.md)（环境安装、构建命令、签名、图标、交付清单）。
摘要：

- **Windows**：`flutter build windows --release` → `build/windows/x64/runner/Release/`
  → 压缩为便携版 `dist/MyPet-Windows.zip`（免安装）；附 Inno Setup 脚本可做安装器。
- **Android**：`keytool` 生成 `mypet-release.jks`（PKCS12，有效期 10000 天）+
  `key.properties` → `signingConfigs` 注入 → `flutter build apk --release` → `dist/MyPet.apk`。
  权限：SYSTEM_ALERT_WINDOW / FOREGROUND_SERVICE(+SPECIAL_USE) / POST_NOTIFICATIONS /
  REQUEST_IGNORE_BATTERY_OPTIMIZATIONS。
- 升级素材：替换 `assets/parts/*.png` 或调整 `rig.json` → 重跑 `slice.py` → 重新构建。

---

*生成于 MyPet 项目交付；算法参数均可在 `rig.json`/`PetEngine` 中调参。*
