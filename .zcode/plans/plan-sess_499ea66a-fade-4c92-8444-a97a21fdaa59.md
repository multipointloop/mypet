# MyPet 桌宠应用 — 实施计划（最终版 v3，已并入全部修订）

## 执行顺序
**① 启动 SDK 下载（后台并行）→ ② 编写 tools 工具脚本 → ③ 装配 SDK + flutter doctor → ④ 素材管线 → ⑤ 工程脚手架 → ⑥ 核心代码 → ⑦ 平台服务 → ⑧ 双端构建测试 → ⑨ 文档与 dist 交付**

## 1. 环境安装（全 E 盘，绝不写 C 盘）
- **Python 3.11.9 embeddable** → `dev\py311\`（python.org/华为镜像），启用 pip 后所有脚本基于 3.11
- Flutter stable zip → `dev\flutter`；Temurin JDK 17 zip → `dev\jdk17`；Android cmdline-tools → `dev\android-sdk`（platform-tools/android-35/build-tools）
- 缓存重定向：GRADLE_USER_HOME / PUB_CACHE / U2NET_HOME → `dev\` 下；国内镜像加速；`dev\env.bat` 一键注入
- **【v3新增】`dev\env.bat` 显式注入 onnxruntime 依赖路径**（py311 site-packages 加入 PATH/PYTHONPATH），确保 rembg 运行稳定

## 2. tools/ 工具脚本
- **【v3新增】`tools/requirements.txt`**（rembg/onnxruntime/pillow/numpy 固定兼容版本区间）
- **【v3新增】`tools/setup_env.bat`**：启用 py311 的 pip → get-pip → 装依赖 → 预下载 u2net 模型到 E 盘，全程镜像加速、可重复执行
- `cutout.py`（rembg 抠图→透明 PNG）、`slice.py`（按 rig.json 切层）、`gen_sounds.py`（合成占位音效）
- **`coord_picker.html`**：零依赖 Canvas 取点工具（命名关键点+放大镜+生成 rig.json 片段），我先用本地裁剪预标初始坐标，你随时浏览器精修
- 音频容错：AudioService 文件缺失静默跳过

## 3. 工程结构与核心功能（同 v2）
- mypet/ Flutter 工程；分层渲染/等比缩放（Ctrl+Alt+↑↓/滚轮/滑块）；GetCursorPos 轮询眼球追踪+椭圆限幅+指数平滑
- 点击命中区（头/身/尾）→ 音效+动效；对话气泡（打字机+闲置随机）；拖拽+重力反弹；呼吸/眨眼/打瞌睡
- **【v3新增】cursor_poller.dart 自适应频率：鼠标静止 500ms 后降频至 10fps，检测到移动立即恢复 60fps，CPU 占用最低化**
- **【v3新增】Bongo Cat 键盘钩子在 windows/runner/ 原生 C++ 实现（WH_KEYBOARD_LL），经 MethodChannel 推送按键事件给 Flutter；设置页显式开关、默认关闭，提示杀软/反作弊风险；托盘菜单同步开关**

## 4. Android 保活（同 v2）
SYSTEM_ALERT_WINDOW + FOREGROUND_SERVICE + FOREGROUND_SERVICE_SPECIAL_USE(API34) + POST_NOTIFICATIONS + REQUEST_IGNORE_BATTERY_OPTIMIZATIONS；常驻低优先级通知；设置页电池白名单跳转；国产 ROM 自启说明写入 BUILD.md

## 5. 双端打包与交付
- Windows：`flutter build windows --release` → 头像图标 → `dist\MyPet-Windows.zip` + Inno Setup 脚本
- Android：JDK17 keytool 签名 → `dist\MyPet.apk`（applicationId com.mypet.pet, minSdk 24）
- `flutter run -d windows` 冒烟验证；docs：DESIGN.md（五步方案）/ASSET_GUIDE.md/BUILD.md

批准后我立即从第①步开始连续执行到交付。