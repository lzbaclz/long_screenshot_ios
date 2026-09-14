# 上滑长图重复状态栏与导航栏：根因与修复设计

原型记录日期：2026-09-14；实施补记日期：2026-09-15。依据用户在 0.1.3（4）上的真机反馈：向下浏览正常，从聊天最新消息向上翻时，长图每一段都带着一份状态栏和导航栏。本文保留已复现的根因、修复设计和原型验证历史；2026-09-15 的正式实施状态追加在文末，与原型结果分开。实际验收和 TestFlight 分发按 [开发约定](../AGENTS.md) 记录。

## 现象

用户截图（微信聊天，纯色背景，无键盘）自上而下依次是：

1. 状态栏（录屏红点胶囊）+ 导航栏 + 一小段更早消息；
2. 又一份状态栏（录屏胶囊）+ 导航栏 + 中段消息；
3. 又一份状态栏（无胶囊，时间旁有定位箭头）+ 导航栏 + 最新消息 + 输入栏。

截图中的消息看起来按阅读顺序排列，但截图本身不能证明消息没有丢行。每段重复出现“状态栏 + 导航栏”是可直接观察到的现象；这些固定像素进入正文条带后会占据原本应由正文填充的行，即使最终总高度不变，也不能据此认定正文完整。第 3 段是起始画面，其状态栏与后两段不同：起始帧还没有画上系统录屏指示，后续帧有。

## 已确认根因

失败发生在自动匹配区域的首次判定，而不在拼接器或存储层。链路如下（行号对应当时 `feat/scroll-capture-mvp` 分支的 `c973333`）：

1. `CaptureFramePipeline.verifyStart` 调用 `FixedRegionDetector.candidates(reference: 起始帧, current: 当前帧, displacement: -d)` 求内部匹配区域（[CaptureFramePipeline.swift:286-302](../iOS/Shared/CaptureFramePipeline.swift)）。
2. 位移为负时，`candidates` 与 `resolve` 都把两帧对调再按正位移处理（[FixedRegionDetector.swift:23-25、45-47](../Sources/ScrollCaptureCore/FixedRegionDetector.swift)）。对调后 **起始帧成了 `current`，后来的帧成了 `reference`**。这是几何上必需的：向上翻时只有起始帧的第 `y` 行能与后一帧的第 `y + d` 行对应。
3. `evidence(fromTop:)` 判定“某行在移动”的条件只有两个：`current` 第 `y` 行 ≈ `reference` 第 `y + d` 行（`motion <= 4`），且两帧同一行不同（`stationary - motion >= 4`）（[FixedRegionDetector.swift:66-75](../Sources/ScrollCaptureCore/FixedRegionDetector.swift)）。它不要求这一行真的有内容。
4. 微信状态栏、导航栏与聊天背景是同一个灰（#EDEDED）。后来的帧在状态栏里多了录屏胶囊，同一行因此“不同”；而起始帧这一行是空白，后一帧的第 `y + d` 行落在导航栏下方的空白背景上，两者都是纯灰，`motion ≈ 0`。空白对空白被当成了“移动特征”。第一处这样的行在胶囊下缘、时间数字之下，于是 `top` 落在状态栏内部（合成夹具中为第 114 行，真实导航栏底部约在第 300 行）。
5. `verifyStart` 用该区域重放起止两帧。区域里多出的约 190 行固定像素只占正文约 8%，评分的去尾均值把它们裁掉，重放仍返回 `.advanced` 且位移正确，于是错误区域被接受并固定为 `effectiveConfiguration`。
6. 此后每一帧向上扩展时，拼接器返回的新增行都是 `topInset..<(topInset + 新增行数)`，即从状态栏中部开始，必然包含下半个状态栏和整条导航栏；存储层只把 `0..<114` 当作头部边缘替换（[CaptureImageRenderer.swift:123-126](../iOS/Shared/CaptureImageRenderer.swift)），其余固定像素随正文条带永久落盘。输出就是每一接缝处重复一次“状态栏 + 导航栏”。

向下浏览不受影响的原因：不对调时录屏胶囊在 `current` 帧里，胶囊行与任何平移行都对不上，`motion` 很大，不会被记为移动。同样的判定在“胶囊只出现在起始帧、之后消失”的向下场景里会失败，说明问题在于哪一帧被当作 `current`，而不是方向本身。

已有测试没有发现它的原因：

- 核心与原生夹具的固定栏背景是 242，正文背景是 248，相差 6 个灰阶，空白对空白的 `motion` 为 6，恰好高于阈值 4；真实微信两者相同。
- `UpwardRegionRegressionTests.testReversingTheSameFramePairPreservesCandidateSymmetry` 比较的是对调前后的两次调用，而对调后它们是同一次计算，等式恒成立，覆盖不到“只有一帧有覆盖层”的情况。
- 模拟器真实滚动夹具没有模拟系统录屏指示在起始后才出现。

时好时坏的原因：只有当后一帧“状态栏行号 + 位移”落在空白背景上时才会触发；首次位移较大或恰好落在气泡上时不会触发。

## 复现证据

全部在本机 `.work/upward-header-investigation/` 下，使用仓库当前核心代码、无人工修改的生产 `CaptureFramePipeline.swift` 去掉 UIKit 条件编译后的无头副本、以及完全程序生成的 144×2556 聊天夹具（状态栏 0..<162、导航栏 162..<300、输入栏 2406..<2556，固定栏与正文背景同为 237；没有使用用户私人截图）。

| 项目 | 修复前 | 修复后（原型 v2） |
| --- | --- | --- |
| 区域判定（胶囊仅在后一帧，向上 300/500 像素） | `top=114/bottom=150`，重放 `advanced` | `top=300/bottom=150`（恰为导航栏底部），重放 `advanced` |
| 对照：胶囊两帧都有 | `top=300` | `top=300` |
| 对照：向下且胶囊仅在后一帧 | `top=300` | `top=300` |
| 对照：向下且胶囊仅在起始帧（500 像素） | `top=49` | `top=300` |
| 无头 pipeline 9 帧向上序列 | 有效区域 `top 114`；9 个条带中 8 个含状态栏／导航栏行 | 有效区域 `top 300`；只有头部边缘含 1 次 |
| 输出总高度 | 4556 | 4556（仅高度相同，不能证明未丢正文） |

日志：`detector-before.log`、`detector-v2.log`、`pipeline-before.log`、`pipeline-v2.log`。原型补丁：`detector.patch`（即 v2，相对 `Sources/ScrollCaptureCore/FixedRegionDetector.swift`，91 行 diff）。

## 修复设计

原则：不用像素颜色猜测状态栏，不按固定像素数裁剪，不在输出后擦除重复的固定栏。只修改“哪些行可以作为移动证据、区域最少要从哪里开始”的判定，输出契约（首尾原始边缘各保留一次）不变。

### A. 核心 `FixedRegionDetector`（已原型验证）

1. **固定结构带。** 新增 `fixedStructureBand(reference:current:)`：从上、下两端分别扫描至 30% 高度加一个支持窗口。某一行若两帧在同一屏幕行**共享同一批横向结构**（有梯度 ≥ 16 的列中，双方都有梯度且像素值相差 ≤ 3 的列多于 4 个，并占该行全部结构列的 60% 以上），即视为固定 UI 行。录屏胶囊、跳变的时钟数字只改变该行的一部分列，时间、信号图标、标题、返回键仍然一致，因此这些行照样计入；而表格竖线、气泡左缘这类只在少数列上重合的正文行不计入。相邻两条固定行之间允许最多一个支持窗口（`max(12, height/12)`）的空白或覆盖层。返回值是“区域至少要从这里开始”的排他距离。判定与哪一帧是 `current` 无关，天然对称。
2. **候选与精确边界都必须在带之外。** `evidence` 只在 `distance >= 带端` 的行里找移动；`movingInterior` 的候选若起点在带内则丢弃；`resolve` 得到的精确边界若落在带内则返回 `.ambiguous`，交由证据路径处理。
3. **移动行判定本身不改。** 原规则允许空白行凭“两帧同一行不同”成为边界，这是在留白处得到紧贴固定栏边界的必要条件（见下文 v1 教训）。带只负责把明显属于固定栏的行排除在证据之外。
4. **仅用于整页平移路径。** `candidates` 在 `ForegroundMotionRegistration` 返回 `.matched` 或 `.rejected` 时已提前返回，带只在 `.notLayered` 之后计算。固定壁纸下气泡之间露出的壁纸行也“一致且有结构”，但那是壁纸不是固定栏，所以分层路径不能套用此规则。

**v1 教训（已否决的做法）。** 最初的原型还要求“移动证据两侧都要有横向结构”。它同样能消除本次失败，但让朋友圈布局的自动区域从精确的 `44/36` 退到 `73/47`：匹配窗口缩小后，向上到最早位置的一帧被判 `ambiguous`，导出少了 50 行（原生 `testAutomaticMomentsLayoutHandlesPausePhotosAndBothDirections` 失败，`.work/upward-header-investigation/unit-after.xcresult`、`moments-replay-v1.log`）。结论：**inset 变大、有效匹配窗口缩小并不“无害”**，它会削弱重复版式下的证据；修复必须只排除固定栏，不能顺带把留白让出去。v2 在同一批 14 帧上恢复 `44/36` 与 630 行全高（`moments-replay-v2.log`）。

原型改动共 91 行 diff，见 `.work/upward-header-investigation/detector.patch`。

### B. 采集层 `CaptureFramePipeline.verifyStart`（原型阶段的第二道闸提议）

原计划用 `preferredInsets == nil` 判断整页候选，再在重放前检查 `insets.top >= band.top && insets.bottom >= band.bottom`。实施审查发现该来源判断不可靠：候选生成器在负位移对调后还会再次识别前景，可能在没有 preferred 区域的调用中返回壁纸前景区域。

正式实现改用 `FixedRegionDetector.candidateSet` 的明确 `source`。仅 `.wholePage` 候选在重放前受固定结构带复核；preferred 前景区域和候选内部识别的 `.foreground` 区域都豁免，前景拒绝不降级为整页猜测。这保留了第二道闸的目的，同时避免把壁纸当成固定栏。

### C. 诊断（原型阶段提议，正式语义见实施补记）

`CaptureDiagnostics` 目前不记录最终匹配区域。增加可选字段 `matchingTopInset`、`matchingBottomInset`、`fixedBandTop`、`fixedBandBottom`，由 pipeline 在起拼成功时写入并显示在“捕捉详情”。本次问题如果详情页显示 `top=114`，一眼就能定位，不必等合成复现。字段可选，旧记录无需迁移。

### D. 回归测试（待实现）

| 层 | 用例 | 通过要求 |
| --- | --- | --- |
| 核心 `FixedRegionDetectorTests` | 固定栏与正文同色；录屏胶囊只在后一帧；向上 300/500/1000 像素 | 首个候选 `top` ≥ 导航栏底部，重放 `advanced` 且位移正确 |
| 核心 | 同上但胶囊只在起始帧且向下 | 同上 |
| 核心 | `resolve` 在胶囊下方有内容、`boundary` 会返回状态栏内行的构造 | 返回 `.ambiguous` |
| 核心 | 用“只有一帧有覆盖层”的帧对替换现有 `testReversingTheSameFramePairPreservesCandidateSymmetry` | 正、反两次调用给出相同且在带外的候选 |
| 核心 | 固定壁纸夹具（`WallpaperAcceptance` 同类灰度图） | 分层路径结果与 0.1.3 完全一致 |
| 原生 `UpwardStartRegressionTests` | 1179 像素宽原生尺寸，固定栏与正文同色，第 2 帧起画上胶囊，向上 3–5 步后导出 | 导出像素等于“最后一帧 `0..<top`”+ 正文区间 + “起始帧输入栏”，且状态栏行只出现一次 |
| 模拟器 `ScrollCaptureSimulatorCapture` | `FixtureReader` 增加 `--recording-indicator-after-first-frame` 开关，在真实 `UIScrollView` 上叠加合成胶囊 | 三条路线输出高度与真实 `contentOffset` 范围一致，逐条消息核对通过 |

夹具生成代码可直接移植 `.work/upward-header-investigation/Fixture.swift`。

### E. 文档与发布

- [算法说明](algorithm.md)“自动匹配区域与原始首尾”一节补充“固定结构带”规则（共享结构行、链式支持窗口、候选与精确边界必须在带外），并写明分层路径豁免。
- 新建 `docs/release/0.1.4-testflight.md`，按约定写清现象、原因、修复、用户可见变化、实际验证与边界。
- 版本 `0.1.4`、构建 `5`；CI 保持仅手动。

## 用户可见变化

- 从最新消息向上翻，长图顶部只保留一次状态栏与导航栏，其余接缝处为连续正文。
- 起拼前后的系统录屏指示、时钟跳变、定位箭头不再影响区域判定。
- 匹配区域与以前一样贴着固定栏边缘或正文留白，只是不再可能从固定栏内部开始；首尾原始像素照旧各保留一次，不丢内容。
- 首次位移很大或起始两帧恰好没有共同结构时，与之前一样等待下一帧，不会提前结束。

## 原型验证结果

| 验证 | 结果 | 证据 |
| --- | --- | --- |
| 修复前无头复现 | 区域 `top 114`，8 个条带含固定栏 | `.work/upward-header-investigation/pipeline-before.log` |
| 修复后无头复现（v2） | 区域 `top 300`，固定栏仅头部边缘 1 次，总高度不变 | `pipeline-v2.log` |
| 区域判定五组对照（v2） | 全部在带外，向下路径不变 | `detector-before.log`、`detector-v2.log` |
| 朋友圈 14 帧真实灰度回放（原生用例附件） | v1：区域 `73/47`，第 9 帧 `ambiguous`，580 行；v2：区域 `44/36`，630 行 | `moments-replay-v1.log`、`moments-replay-v2.log` |
| Swift 核心回归（v2 副本） | 66 / 66 通过 | `core-tests-v2.log`，`swift test -c release` |
| 217 项合成基准（v2 副本） | 217 / 217，8,776 帧像素一致 | `benchmark-v2/report.json` |
| 原生单元与像素验收（v1 临时套用） | 74 项中 73 通过，1 失败（朋友圈用例，见上） | `unit-after.xcresult`、`unit-after.log` |
| 原生单元与像素验收（v2 临时套用后自动还原） | 74 / 74 通过，0 失败、0 跳过；iOS Simulator `Longlet-PhotosDenied`，含朋友圈、壁纸、短中文、键盘起步与每周额度用例 | `unit-v2.xcresult`、`unit-v2.log` |

## 验证边界

- 夹具是程序生成的同类画面，不是微信真实像素；真机 ReplayKit 回调序列与录屏指示出现的确切时机仍需用户更新后复测。
- 截至 2026-09-14 原型记录时，只覆盖 A；当时 B、C、D、E 尚未实现，原生与模拟器新增用例尚未编写，补丁仅在 `.work` 中。正式实现进度见下方 2026-09-15 补记。
- 夹具在首次位移 800 像素时，唯一候选重放被判 `ambiguous`，修复前后相同，属于既有的大步首滑保守边界，本次不处理。
- 透明导航栏（内容透过模糊可见）不会形成固定结构带，仍沿用原移动证据规则；它不是本次反馈场景。
- 分层壁纸路径未改动，其正确性仍由 0.1.3 的壁纸验收保证。

## 原型阶段的实施顺序建议（历史）

1. 把 `.work/upward-header-investigation/detector.patch` 套用到 `Sources/ScrollCaptureCore/FixedRegionDetector.swift`，先跑 `swift test -c release` 与基准确认 66 / 66、217 / 217。
2. 实现 B（`verifyStart` 第二道闸）与 C（诊断字段），补 D 中的核心与原生用例，用 `.work/upward-header-investigation/Fixture.swift` 派生同色固定栏夹具。
3. 跑原生单元、模拟器真实滚动三条路线与保存／分享回归；更新算法说明与 0.1.4 发布记录；手动上传 TestFlight。
4. 用户从同一聊天入口向上翻复测：检查顶部只有一次状态栏与导航栏、接缝处无重复固定栏、最早消息完整，并回传“捕捉详情”中的匹配区域数值。

## 2026-09-15 正式实施补记

当前工作分支为 `feat/scroll-capture-mvp`。以下描述正式源码的实施状态，不把 2026-09-14 临时副本的通过结果计入本轮验收。完整过程见 [Beta 5 开发与验收流程](validation/beta-5-acceptance.md)，发布状态见 [0.1.4（5）更新草稿](release/0.1.4-testflight.md)。

- **核心已实现。** 公开固定结构带 API，约束精确边界、移动证据、内部候选及两行回退。新增 `CandidateSource`、`CandidateSet` 和 `candidateSet`；旧 `candidates` 接口兼容返回区域数组。前景来源在正负位移归一化后仍保留，避免调用层误判。原移动行规则及歧义门槛保留。
- **采集复核已实现并冻结供主 agent 验收。** 第二道闸根据明确来源只约束整页候选，在重放前完成；真实壁纸前景与手动区域保持各自语义。
- **诊断与中英文展示已实现。** 可选 `matchingTopInset`、`matchingBottomInset`、`matchingFrameHeight`、`matchingRegionSource` 记录最终获采用、且首批条带成功生成的区域；`fixedBandTop`／`fixedBandBottom` 对应该次整页起拼。未成功起拼或旧 schema-1 缺字段表示“未记录”；前景／手动保护带表示“不适用”，不将 nil 当作 0。失败候选与后续拒绝不覆盖已采用区域，数值单位均为原始图像像素。
- **新增原生测试已编写，尚未执行 Xcode 验收。** `HeaderCaptureAcceptanceTests` 共 7 项，包括 1179×2556 与 886×1920 同色固定栏、第二帧胶囊出现和逐帧时钟变化后的向上六步、反方向胶囊消失变体、手动输出与诊断、壁纸前景豁免、旧记录与未采用区域 nil 语义。主路径经过生产 Core Image 转换、pipeline、`repository.commit` 与 PNG；期望来自独立文档坐标与完整原始上下端，严格逐像素比较，不使用算法返回 inset 来构造真值。原朋友圈期望未修改。
- **已执行的本轮检查。** 核心开发线报告 Swift 核心 76 / 76 通过；隔离旧 pipeline 配合新核心的条带追踪中，重复进入正文的 8 份固定栏消除，输出只在头部保留 1 份，总高度仍为 4556。此追踪仅证明条带来源与高度变化，不替代最终 PNG 完整像素验收。217 项基准仍在运行，结果尚未回填。采集开发线的 Swift 语法解析、双语言 strings 校验和 diff 检查通过；没有据此宣称新原生用例已经通过。
- **尚待本轮执行或确认。** 主 agent 统一运行完整原生与真实 UIScrollView 手势验收、保存／分享回归，完成版本、归档、签名审计与手动 TestFlight 分发后再填写实际结果。本文不预填通过、上传或内部组可用状态。

“只出现一次固定栏”“输出高度正确”“完整正文逐像素正确”是三个不同的检查。修复前与修复后的无头追踪都可得到 4556 高度；旧条带中的固定像素会占用原应有的正文行，因此修复前日志或用户截图均不能证明无丢失。本轮完整像素 oracle 正是为独立验证正文连续、原始首尾完整且没有重复固定栏而新增。


## 2026-09-15 主 agent 集中验收

正式源码已落地，新增明确候选来源与 padding 带外保护；第二道闸和诊断字段均已实现。原生 81 / 81（新增 Header 7 项）、核心 76 / 76、基准 217 / 217、新固定栏真实手势 3 / 3、原壁纸 3 / 3、保存／分享 1 / 1 全部通过。完整记录与验证边界见 [0.1.4 更新记录](release/0.1.4-testflight.md)。目前正在归档，内部可用状态以更新记录最终分发结果为准。
