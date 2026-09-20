# MyPet 素材切图与分层绑定指南

> 本工程的动效完全由 `assets/rig.json` 驱动：**改图/改坐标不需要改任何代码**。
> 当前交付包含一条全自动管线（rembg 抠图 + 坐标切层），本文同时给出
> Photoshop 手动精修与 Live2D Cubism 进阶路线。

---

## 一、当前自动管线（已完成，可随时重跑）

```bat
cd "E:\desktop pet\dev"
call env.bat
cd ..
python tools\cutout.py      :: 1.jpg → 抠图 pet_full.png（保持 992×1400 画布）
python tools\slice.py       :: 按 rig.json 切出 5 图层 + 眼底修补 + 尾巴擦除
python tools\make_icon.py   :: 头部 → icon.png / tray.ico
python tools\gen_sounds.py  :: 合成占位音效（可跳过）
```

图层清单（坐标 = 原图画布像素，左上原点）：

| 图层 | 文件 | 裁剪框 | 说明 |
|---|---|---|---|
| tail | parts/tail.png | 585,995 → 885,1175 | 绕尾根 (610,1125) 摆动 |
| body | parts/body.png | 198,615 → 872,1400 | 已做眼底修补 + 尾巴像素擦除 |
| head | parts/head.png | 195,322 → 840,615 | 已做眼底修补；含双马尾/耳/呆毛 |
| eyeL | parts/eyeL.png | 432,505 → 492,562 | 瞳孔中心锚点 (466,537) |
| eyeR | parts/eyeR.png | 528,512 → 580,570 | 瞳孔中心锚点 (556,545) |

---

## 二、coord_picker.html：浏览器里微调坐标（零依赖）

1. 双击打开 `tools/coord_picker.html`（Chrome/Edge 均可）；
2. 点「加载 ../1.jpg」或「加载抠图结果」（两者同坐标系）；
3. 右侧面板选中一个目标（如 `layer:head`）→ 模式切到"矩形"→ 在图上拖拽画框；
4. 锚点模式下点击放置 `eyeL/eyeR`（瞳孔中心）、`headPivot`（脖颈）、`tailPivot`（尾根）、`feet`；
5. 鼠标悬停有 8× 放大镜实时显示原始像素坐标；
6. 「生成 JSON」→「复制到剪贴板」→ 粘贴回 `mypet/assets/rig.json`（`params` 字段会自动保留）→ 重跑 `slice.py` 即生效。

---

## 三、Photoshop 手动精修（推荐替换自动抠图）

自动抠图在发丝缝隙处有少量背景残留（右耳后、马尾间隙）。精修步骤：

1. **抠图**：PS 打开 `1.jpg` → `选择主体`（或快速选择+边缘细化笔刷）→
   输出为**图层蒙版**；检查发丝边缘，用「选择并遮住」的净化颜色去除白边。
2. **图层拆分**（保持 992×1400 画布不动，**重要**）：
   - 复制人物层 5 份，分别命名 tail / body / head / eyeL / eyeR；
   - 每层用蒙版只保留自己区域（参考上表裁剪框；接缝处重叠 2-3px 更安全）；
   - **head 层记得把眼睛区域擦掉**（用吸管取脸颊肤色柔边画笔涂掉，或矩形羽化填充），
     这是眼睛能"移动"的关键；
   - **body 层把尾巴擦掉**（否则摆尾出现双尾巴）。
3. **导出**：每层 `文件 → 导出 → 导出为 PNG`（勾选透明），保持画布尺寸，
   覆盖 `mypet/assets/parts/<层名>.png`；
   然后运行 `python tools\slice.py` 重新裁剪（或直接让 slice.py 只做裁剪）。
   > 小技巧：手动导出时可以直接按裁剪框导出小图，并把 rig.json 的 crop 改成
   `crop: [0,0,0,0]` 后用 coord_picker 重新框选；也可以整图导出让 slice.py 代劳（推荐）。
4. **验收**：打开 `tools/_composite.jpg` 流程（slice.py 附带 QA 合成），确认
   眼睛移动/尾巴摆动无鬼影、无断缝。

### 命中区与锚点
`regions`（头/身/尾点击区）与 `anchors`（瞳孔中心等）直接改 rig.json 或用
coord_picker 点击生成。瞳孔中心必须点在**虹膜中心**，视线追踪的方向感才准。

---

## 四、Live2D Cubism 进阶路线（可选）

静态分层做到极致后，可升级为骨骼变形：

1. **导入**：Cubism Editor 新建模型 → 把 PS 分层 PSD 直接拖入（保持画布/图层名）；
2. **网格**：为每个 ArtMesh 自动生成网格，脸颊/马尾手动加密；
3. **参数绑定**（对应本工程 rig.json 的 params）：
   - `ParamAngleX/Y`（±30）← 头部跟随（对应 headShift/headRotDeg）
   - `ParamEyeBallX/Y`（±1）← 瞳孔（对应 pupilMax）
   - `ParamEyeLOpen/ROpen`（0-1）← 眨眼
   - `ParamBodyAngleX/Z` ← 呼吸/点击反应
   - `ParamTailWag`（自建）← 摇尾
4. **物理**：给马尾/尾巴挂 Fizzi 物理（摆动跟随头部位移自动下垂）；
5. **接入应用**：Cubism SDK for Flutter 暂无官方包，两条路：
   - Cubism Framework 编译成动态库 + FFI 封装（许可证：Cubism Core 免费发布需遵守 Live2D 规则）；
   - 或导出逐参数关键帧序列，仍由本工程 `RigView` 播放。
   在接入前，本工程的分层方案与 Live2D 参数一一对应，迁移成本最低。

---

## 五、音效替换

`assets/sounds/` 当前是程序合成的占位音效（click_head / click_body / click_tail /
land / surprise / key / mew）。**直接用同名 mp3/wav 覆盖再重新构建即可**；
播放器对缺失/损坏文件静默跳过，永远不会弹错误。
