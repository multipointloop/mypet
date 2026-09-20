# MyPet 构建与部署手册（Windows .exe / Android .apk）

> 本机环境全部位于 `E:\desktop pet\dev\`（Flutter / JDK17 / Android SDK / Python3.11 /
> Gradle 与 Pub 缓存），**不占用 C 盘**。任何终端先 `call dev\env.bat` 注入环境。

---

## 一、环境一览（已装好，可跳过）

| 组件 | 位置 | 版本 |
|---|---|---|
| Flutter SDK | `dev\flutter` | 3.47.4 stable（Dart 3.13.3） |
| JDK | `dev\jdk17` | Temurin 17（zip 解压版） |
| Android SDK | `dev\android-sdk` | platform 35/36 + build-tools 35/36 + platform-tools |
| Python | `dev\py311` | 3.11.9 embeddable + rembg/onnxruntime |
| VS 2022 Community | C 盘系统已有 | 17.14（含 C++ 桌面开发与 Win10 SDK） |

镜像：`PUB_HOSTED_URL=pub.flutter-io.cn`、`FLUTTER_STORAGE_BASE_URL=storage.flutter-io.cn`、
pip 走清华源、u2net 模型缓存在 `dev\models\`。

重建环境（换机/清空后）：
```bat
cd "E:\desktop pet\dev"
:: 1) 下载 flutter_windows_*.zip / OpenJDK17 zip / commandlinetools-win zip / python-3.11.9-embed-amd64.zip 到 downloads\
:: 2) 解压 flutter→dev\flutter，jdk→dev\jdk17，cmdline-tools→dev\android-sdk\cmdline-tools\latest，python→dev\py311
call env.bat
..\tools\setup_env.bat        :: pip + rembg + u2net 模型
setup_android.bat             :: sdkmanager 组件 + licenses + flutter config
flutter doctor                :: 应全绿（除 Chrome）
```

---

## 二、Windows 构建（.exe）

```bat
call "E:\desktop pet\dev\env.bat"
cd /d "E:\desktop pet\mypet"
flutter analyze                 &:: 静态检查，当前 0 issues
flutter build windows --release
```

产物：`build\windows\x64\runner\Release\`
（mypet.exe + flutter_windows.dll + 各插件 dll + data\）

**交付打包（便携版）**：
```bat
cd /d "E:\desktop pet\mypet\build\windows\x64\runner"
powershell Compress-Archive -Force Release "E:\desktop pet\dist\MyPet-Windows.zip"
```

**可选安装器**（Inno Setup 脚本已附 `dist\setup.iss`）：安装 Inno Setup 6 后
`ISCC.exe dist\setup.iss` 生成单文件安装程序。

### 已知构建注意点
- 本机已开启「开发人员模式」（设置 → 系统 → 开发者选项），插件 symlink 依赖它；
- 若出现 `Building native assets failed (package:objective_c)`，执行
  `flutter config --no-enable-native-assets`（Apple 专用包在 Windows 上无意义）；
- 项目路径含空格（`desktop pet`）已验证可构建，但如遇 CMake 奇异报错可迁移到无空格路径。

---

## 三、Android 构建（.apk 签名版）

### 1. 签名（已生成）
```
android\mypet-release.jks     PKCS12, alias=mypet, 密码 mypet2026, 有效期 10000 天
android\key.properties        storeFile=../mypet-release.jks
```
> 正式发布前请自签一把新钥匙并妥善保管 jks + 密码；丢失将无法应用内升级。
> build.gradle.kts 已按 key.properties 注入 signingConfigs；文件不存在时自动回落 debug 签名。

### 2. 构建
```bat
call "E:\desktop pet\dev\env.bat"
cd /d "E:\desktop pet\mypet"
flutter build apk --release          &:: 通用 apk（arm64+armeabi+v7a+x64）
:: 或分架构减小体积：
flutter build apk --release --split-per-abi
```
产物：`build\app\outputs\flutter-apk\app-release.apk`
→ 复制为 `dist\MyPet.apk`。

### 3. 安装验证
```bat
adb install -r dist\MyPet.apk        &:: platform-tools 已在 dev\android-sdk
```

### 4. 运行时权限引导（App 内已做）
1. 首次启动进入设置页 →「悬浮窗权限」→ 授权“显示在其他应用上层”；
2. 「跳过电池优化」→ 允许；
3. 「启动桌宠悬浮窗」→ 桌面出现猫娘。

### 5. 保活说明（前台服务）
- Manifest 权限：`SYSTEM_ALERT_WINDOW`、`FOREGROUND_SERVICE`、
  `FOREGROUND_SERVICE_SPECIAL_USE`(API 34+)、`POST_NOTIFICATIONS`、
  `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`、`WAKE_LOCK`；
- 悬浮窗运行期间常驻低优先级通知「MyPet 桌宠运行中」（用户可隐藏通知角标，不影响保活）；
- 国产 ROM 额外步骤（设置页有图文提示）：
  - **MIUI**：应用详情 → 自启动 ✓；省电策略 → 无限制；显示悬浮窗 ✓；
  - **EMUI/HarmonyOS**：应用启动管理 → 手动管理，三联全开；
  - **ColorOS/OriginOS**：允许自启动 + 关闭深度睡眠 + 悬浮窗权限 ✓。

---

## 四、发布清单核对

- [ ] `dist\MyPet-Windows.zip`（解压即用，托盘退出，开机自启可开关）
- [ ] `dist\MyPet.apk`（签名 release；`apksigner verify --print-certs` 校验）
- [ ] 素材更新流程：替换 `assets/parts/*.png` 或改 `rig.json` → `python tools\slice.py` → 重新构建
- [ ] 音效替换：同名 mp3/wav 放入 `assets/sounds/` → 重新构建
- [ ] 版本号：改 `pubspec.yaml` 的 `version:` 后两端重新构建

## 五、常见问题

| 现象 | 处理 |
|---|---|
| 桌宠被任务栏遮挡 | 任务栏会盖住桌宠脚部属正常（置顶在窗口层），拖到屏幕上方即可 |
| 穿透后点不到宠物 | 设计如此：托盘菜单/热键可随时关闭穿透 |
| 键盘互动无反应 | 设置里 Bongo Cat 开关默认关闭（防杀软误报/反作弊冲突） |
| 眼睛不追鼠标 | 全局追踪基于 GetCursorPos 轮询，检查是否处于穿透状态（不影响）|
| gradle 报 JDK 版本 | 确认 `call env.bat` 已执行（JAVA_HOME 指向 dev\jdk17） |
