# iOS 长截图竞品与可行性初步调研

调研日期：2026-09-13。目标是假定不越狱、使用公开 API、通过 App Store 分发，捕捉微信等其他 App 中由用户手动滚动的内容。

## 判断

用户手动滚动、应用自动累计画面、结束后直接生成长图，技术上可行。实现可以直接处理系统提供的屏幕帧，不必先生成完整视频文件再让用户导入。系统的捕捉授权与指示仍然存在，不能承诺与 Android 系统截图入口及权限完全相同。

这个操作模式已有竞品。Picsew 的 Scrolling Capture、StitchShot、Reelscap、部分名为“滚动截屏”的产品都有直接启动捕捉、手动滑动、结束出图的流程。自动结束、往返滚动去重、本地处理等也已有产品提供，因此这些单项不能直接视为差异化。

iOS 原生也已有适用于 Safari 等受支持内容的“整页”截图，可保存图像或 PDF；市场缺口是跨应用、由用户选择范围的长截图体验。

## 平台方案

- 兼容 iOS 26 及较早版本：ReplayKit Broadcast Upload Extension 接收屏幕帧，图像算法估计滚动位移，保留新增区域，完成后合成长图。
- iOS 27 起：Apple 已公开 ScreenCaptureKit 在 iOS 上的示例，支持整个显示画面以及 screen-capture 后台模式。框架说明不再需要广播扩展。应评估这个新方案，同时为旧系统保留兼容路径。
- Apple 于 2026-09-09 宣布可使用 Xcode 27 RC 提交新版系统应用；新方案尚需目标机型实测，不能从文档直接推出拼接性能或上架保证。
- 不应把 Android 系统滚动截图理解为通用拼图算法。Android 的 ScrollCaptureCallback 可以由系统与滚动内容提供方协作；iOS 第三方应用不能据此访问其他 App 的滚动控件或离屏内容。
- 快速滚动造成画面缺失、加载中内容变化、固定及透明顶栏、聊天背景、重复内容、动态媒体和长图内存消耗，是主要工程验证项。
- 暂停后自动结束需要可配置，避免用户等图片加载时提前结束。发生匹配失败时应保留已经成功捕捉的部分，支持用户修正。
- 任意跨 App 悬浮长图预览及接管系统截图按键，不应作为公开 API 方案的承诺。后台采集与跨应用自由绘制界面是不同能力。

## 已核对的重点竞品

| 产品 | 公开资料能确认的操作方式 | 对该项目的意义 |
| --- | --- | --- |
| Picsew | 控制中心选择 Picsew 开始广播，手动滚动；支持上下及往返滚动、自动结束，回 App 看结果 | 最优先对标，核心流程高度接近 |
| 滚动截屏 / Auto Screenshots Stitch Tailor（1494098739） | 控制中心选择应用，滚动后静止约 3 秒结束，再打开结果 | 同类直接竞品，不能与 Foundry 63 的 Tailor 混淆 |
| StitchShot（1643120789） | 应用内开始广播，切换目标 App 手动滚动，结束生成长图；商店说明使用 ReplayKit | 证明入口不必只有控制中心 |
| Reelscap（6762419371） | 控制中心选 Reelscap，滚动并停止，返回查看长图；商店说明直接接收 ReplayKit 帧 | 与实时帧处理方向高度接近 |
| Scrollie | 录屏与图片拼接；新版说明包含停滑自动结束，开发者回复确认存在系统录屏扩展入口 | 不能仅按旧版介绍归为视频导入工具 |
| Stitch / ImgStitch（6785018218） | 明确提供系统录屏扩展，也提供视频导入及图片拼接 | 同时覆盖两条流程 |
| PPics | 商店说明屏幕录制直接生成长图，含去滚动条与辅助触控图标 | 相关竞品；商店版本较旧，兼容性待实测 |
| 滚动截屏（1486130680） | 商店宣传滚动捕捉、即时出图，版本记录提及录屏插件 | 相关竞品；实际速度不能由宣传直接确定 |
| 滚动截屏（1511360687） | 商店说明滑动其他应用生成长图；页面最新版本显示 2020 年 | 历史方案参考，当前可用性需实测 |
| Zeta | 明确写明先系统录屏，再回应用导入生成长图；也支持多截图拼接 | 符合用户想减少的传统步骤 |
| ScrollSnap（6759849068） | 从照片图库选择录屏，再自动拼图 | 传统视频转换竞品 |
| ScrollShot（6760192003） | 官网及商店说明视频抽帧与拼接，支持接缝编辑 | 需区分具体入口；不能仅凭名称认定实时 |
| Scrolla | 商店说明开启录屏后边滚动边捕捉，停止后生成长图 | 流程相关，是否内部保存完整视频未核实 |
| StitchPics / 长图拼接-轻松拼截屏 | 多图拼接、编辑，当前商店也列出滚动截图 | 不能按旧测评认定只支持静态截图 |
| Tailor（Foundry 63，926653095） | 用户先截多张有重叠的图片，再自动对齐拼接 | 静态拼图竞品，不是连续采集 |
| Stitch It | 导入截图、排序、裁剪、打码与导出 | 静态拼图编辑竞品 |
| LongShot（6798898681） | 先截若干图片，配置快捷指令和轻点背面后自动拼接保存；明确不录屏 | 简化入口的替代方案，仍需逐屏截图 |
| Web2Pics、WebCapture、Screenshot Web、web2screen 等 | 网页或 Safari 扩展内生成整页截图 | 只解决网页，不覆盖微信等原生页面 |

这里“直接捕捉”是用户操作方式的分类。除开发者明确披露的情况外，未反编译或运行产品，不能据此判断其内部是否缓存视频，也不能把商店宣称的“所有 App”“无损”“秒出图”当作实测结论。

## 建议的立项门槛

先验证“开启捕捉 → 用户在目标 App 滚动 → 结束后立即预览长图”。将 Picsew、StitchShot、Scrollie 作为首轮真机对照，用相同内容比较从起点到保存的耗时、操作次数、漏行/重复/接缝错误、失败后是否保留已完成内容以及长图导出稳定性。

建议优先覆盖微信聊天、网页长文章、一个常用信息流应用。新产品应在至少一个高频场景中显著更省事或更可靠，再扩大范围。仅以“iOS 可以长截图”或“录屏自动变长图”为卖点，差异化不足。公开资料不足以判断下载量、收入、留存或用户付费意愿，本调研不据评分数量推算这些指标。

## 检索范围与证据限制

在中国及美国区 Apple Search API 使用“长截图”“滚动截屏”“scrolling screenshot”“screenshot stitching”，分别返回 72、69、75、74 个结果。依据名称与描述匹配并按 App ID 去重，初筛得到 89 个候选条目；其中仍有拼图、截图美化、工具箱等周边产品，不能把 89 解释为直接竞争者数量。

另从 App Store 和开发者网站补充 7 个快捷指令或网页工具。下表保留这 96 个候选的检索记录，并用 Apple Lookup API 复核条目资料。名称相同而 App ID 不同的产品分别保留，国区与美区同一 App ID 只列一次。

本次没有逐款安装、购买或真机测试，也不保证覆盖全球所有商店、已下架产品、企业软件及所有新上架产品。表中价格仅指商店标示的下载价格，不能据此判断内购功能免费；当前地区查不到的条目不等于全球下架。

## 候选清单

| 序号 | 产品／开发者 | App ID | 可核对地区 | 版本更新日期 | 下载价 | 初步关联方式 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | [Picsew - 滚动截图 & 长图拼接](https://apps.apple.com/cn/app/picsew-%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%9B%BE-%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5/id1208145167?uo=4)<br>Yojio, Ltd. | 1208145167 | CN/US | 2026-09-08 | 免费 | 已有直接启动滚动捕捉流程；细节待实测 |
| 2 | [长图拼接-轻松拼截屏](https://apps.apple.com/cn/app/%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5-%E8%BD%BB%E6%9D%BE%E6%8B%BC%E6%88%AA%E5%B1%8F/id1175878538?uo=4)<br>磊 马 | 1175878538 | CN/US | 2024-12-02 | 免费 | 宣称滚动截图；具体流程待核实 |
| 3 | [长截图 - 滚动截屏 & 长图拼接](https://apps.apple.com/cn/app/%E9%95%BF%E6%88%AA%E5%9B%BE-%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%B1%8F-%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5/id6596735423?uo=4)<br>文婷 赖 | 6596735423 | CN/US | 2026-07-20 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 4 | [滚动截屏-自动长图拼接生成长截图](https://apps.apple.com/cn/app/%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%B1%8F-%E8%87%AA%E5%8A%A8%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5%E7%94%9F%E6%88%90%E9%95%BF%E6%88%AA%E5%9B%BE/id1494098739?uo=4)<br>Dehui Chengzhen | 1494098739 | CN/US | 2026-08-26 | 免费 | 已有直接启动滚动捕捉流程；细节待实测 |
| 5 | [Zeta长截图 - 滚动截屏 & 自动长图拼接](https://apps.apple.com/cn/app/zeta%E9%95%BF%E6%88%AA%E5%9B%BE-%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%B1%8F-%E8%87%AA%E5%8A%A8%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5/id1615913935?uo=4)<br>阳理 江 | 1615913935 | CN/US | 2026-09-04 | 免费 | 导入录屏后转长图；部分也支持多图 |
| 6 | [Stitch - 滚动截图 & 长图拼接](https://apps.apple.com/cn/app/stitch-%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%9B%BE-%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5/id1436797153?uo=4)<br>晓鹏 杨 | 1436797153 | CN/US | 2026-08-31 | 免费 | 宣称滚动截图；具体流程待核实 |
| 7 | [滚动截长图-手机滚动截屏&长图拼接大师](https://apps.apple.com/cn/app/%E6%BB%9A%E5%8A%A8%E6%88%AA%E9%95%BF%E5%9B%BE-%E6%89%8B%E6%9C%BA%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%B1%8F-%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5%E5%A4%A7%E5%B8%88/id1658935259?uo=4)<br>Hangzhou Keyi Network Technology Co., Ltd | 1658935259 | CN/US | 2025-11-10 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 8 | [滚动截屏 - 一键自动滚动截图长截图拼接](https://apps.apple.com/cn/app/%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%B1%8F-%E4%B8%80%E9%94%AE%E8%87%AA%E5%8A%A8%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%9B%BE%E9%95%BF%E6%88%AA%E5%9B%BE%E6%8B%BC%E6%8E%A5/id6762594285?uo=4)<br>Yingsong Technology Co., Ltd. | 6762594285 | CN/US | 2026-07-04 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 9 | [长图拼接大师](https://apps.apple.com/cn/app/%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5%E5%A4%A7%E5%B8%88/id1239801987?uo=4)<br>Shanghai Yuanlai Infomation Technology Co., Ltd. | 1239801987 | CN/US | 2026-08-14 | 免费 | 多图拼接／周边图片工具 |
| 10 | [滚动截屏 - 滑动截屏生成长图](https://apps.apple.com/cn/app/%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%B1%8F-%E6%BB%91%E5%8A%A8%E6%88%AA%E5%B1%8F%E7%94%9F%E6%88%90%E9%95%BF%E5%9B%BE/id1511360687?uo=4)<br>智帆 钟 | 1511360687 | CN/US | 2020-05-19 | 免费 | 宣称滚动截图；具体流程待核实 |
| 11 | [Scrolla - 滚动截图&长图拼接&长截图&滑动截屏生成](https://apps.apple.com/cn/app/scrolla-%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%9B%BE-%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5-%E9%95%BF%E6%88%AA%E5%9B%BE-%E6%BB%91%E5%8A%A8%E6%88%AA%E5%B1%8F%E7%94%9F%E6%88%90/id6800971397?uo=4)<br>玉春 蔡 | 6800971397 | CN/US | 2026-09-11 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 12 | [速拼 · 长图拼接与拼图](https://apps.apple.com/cn/app/%E9%80%9F%E6%8B%BC-%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5%E4%B8%8E%E6%8B%BC%E5%9B%BE/id1439758554?uo=4)<br>Hangzhou Onedium Technology Co., Ltd. | 1439758554 | CN/US | 2025-11-03 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 13 | [视频长截图 - 滚动截图](https://apps.apple.com/cn/app/%E8%A7%86%E9%A2%91%E9%95%BF%E6%88%AA%E5%9B%BE-%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%9B%BE/id6764253842?uo=4)<br>科华 刘 | 6764253842 | CN/US | 2026-07-23 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 14 | [简单长截图](https://apps.apple.com/cn/app/%E7%AE%80%E5%8D%95%E9%95%BF%E6%88%AA%E5%9B%BE/id6761009801?uo=4)<br>彩秀 林 | 6761009801 | CN/US | 2026-06-05 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 15 | [Scrollie: 长截图拼接+照片拼图](https://apps.apple.com/cn/app/scrollie-%E9%95%BF%E6%88%AA%E5%9B%BE%E6%8B%BC%E6%8E%A5-%E7%85%A7%E7%89%87%E6%8B%BC%E5%9B%BE/id6757146579?uo=4)<br>锋 邹 | 6757146579 | CN/US | 2026-08-20 | 免费 | 已有直接启动滚动捕捉流程；细节待实测 |
| 16 | [长截图 - 滚动截屏拼接](https://apps.apple.com/cn/app/%E9%95%BF%E6%88%AA%E5%9B%BE-%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%B1%8F%E6%8B%BC%E6%8E%A5/id6804013763?uo=4)<br>Yuya Takamoto | 6804013763 | CN/US | 2026-09-11 | 免费 | 导入录屏后转长图；部分也支持多图 |
| 17 | [滚动截屏-长截图拼接助手](https://apps.apple.com/cn/app/%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%B1%8F-%E9%95%BF%E6%88%AA%E5%9B%BE%E6%8B%BC%E6%8E%A5%E5%8A%A9%E6%89%8B/id6761741868?uo=4)<br>强强 王 | 6761741868 | CN/US | 2026-08-13 | 免费 | 宣称滚动截图；具体流程待核实 |
| 18 | [Easy拼图-多图拼接图片合成器，照片拼图鸭长截图拼图软件](https://apps.apple.com/cn/app/easy%E6%8B%BC%E5%9B%BE-%E5%A4%9A%E5%9B%BE%E6%8B%BC%E6%8E%A5%E5%9B%BE%E7%89%87%E5%90%88%E6%88%90%E5%99%A8-%E7%85%A7%E7%89%87%E6%8B%BC%E5%9B%BE%E9%B8%AD%E9%95%BF%E6%88%AA%E5%9B%BE%E6%8B%BC%E5%9B%BE%E8%BD%AF%E4%BB%B6/id1569287925?uo=4)<br>Deep Valley Art | 1569287925 | CN/US | 2026-05-18 | 免费 | 多图拼接／周边图片工具 |
| 19 | [PPics - 滚动截屏和图片编辑](https://apps.apple.com/cn/app/ppics-%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%B1%8F%E5%92%8C%E5%9B%BE%E7%89%87%E7%BC%96%E8%BE%91/id1435050126?uo=4)<br>万庄 黄 | 1435050126 | CN/US | 2021-01-03 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 20 | [Stitch - 滚动截屏 & 长图拼接](https://apps.apple.com/cn/app/stitch-%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%B1%8F-%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5/id6785018218?uo=4)<br>少泽 梁 | 6785018218 | CN/US | 2026-07-31 | 免费 | 已有直接启动滚动捕捉流程；细节待实测 |
| 21 | [微商截图助手-聊天长截图、微商文案、文字提取](https://apps.apple.com/cn/app/%E5%BE%AE%E5%95%86%E6%88%AA%E5%9B%BE%E5%8A%A9%E6%89%8B-%E8%81%8A%E5%A4%A9%E9%95%BF%E6%88%AA%E5%9B%BE-%E5%BE%AE%E5%95%86%E6%96%87%E6%A1%88-%E6%96%87%E5%AD%97%E6%8F%90%E5%8F%96/id6740615206?uo=4)<br>慧霞 龙 | 6740615206 | CN/US | 2026-06-17 | 免费 | 搜索候选／周边工具，关联程度待确认 |
| 22 | [LongStitch - 长截图拼接](https://apps.apple.com/cn/app/longstitch-%E9%95%BF%E6%88%AA%E5%9B%BE%E6%8B%BC%E6%8E%A5/id6779057481?uo=4)<br>HALOHUB., LTD | 6779057481 | CN/US | 2026-06-21 | 免费 | 导入录屏后转长图；部分也支持多图 |
| 23 | [一点长图：长截图与隐私检查](https://apps.apple.com/cn/app/%E4%B8%80%E7%82%B9%E9%95%BF%E5%9B%BE-%E9%95%BF%E6%88%AA%E5%9B%BE%E4%B8%8E%E9%9A%90%E7%A7%81%E6%A3%80%E6%9F%A5/id6806275802?uo=4)<br>一聪 张 | 6806275802 | CN/US | 2026-09-10 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 24 | [长截图 - 滚动截屏与长图拼接](https://apps.apple.com/cn/app/%E9%95%BF%E6%88%AA%E5%9B%BE-%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%B1%8F%E4%B8%8E%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5/id6759634662?uo=4)<br>杨柳 孙 | 6759634662 | CN/US | 2026-09-08 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 25 | [LoG 长截图 - 滚动录屏拼接](https://apps.apple.com/cn/app/log-%E9%95%BF%E6%88%AA%E5%9B%BE-%E6%BB%9A%E5%8A%A8%E5%BD%95%E5%B1%8F%E6%8B%BC%E6%8E%A5/id6789020145?uo=4)<br>鸿基 邬 | 6789020145 | CN/US | 2026-09-13 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 26 | [加解集 - 图片加密与解密工具合集](https://apps.apple.com/cn/app/%E5%8A%A0%E8%A7%A3%E9%9B%86-%E5%9B%BE%E7%89%87%E5%8A%A0%E5%AF%86%E4%B8%8E%E8%A7%A3%E5%AF%86%E5%B7%A5%E5%85%B7%E5%90%88%E9%9B%86/id1586436976?uo=4)<br>晓晶 卞 | 1586436976 | CN/US | 2023-03-15 | 免费 | 宣称滚动截图；具体流程待核实 |
| 27 | [截图王 -  截图做图神器](https://apps.apple.com/cn/app/%E6%88%AA%E5%9B%BE%E7%8E%8B-%E6%88%AA%E5%9B%BE%E5%81%9A%E5%9B%BE%E7%A5%9E%E5%99%A8/id6755377320?uo=4)<br>卓辉 容 | 6755377320 | CN/US | 2026-01-06 | 免费 | 多图拼接／周边图片工具 |
| 28 | [PixBond 录屏长截图与图片拼接](https://apps.apple.com/cn/app/pixbond-%E5%BD%95%E5%B1%8F%E9%95%BF%E6%88%AA%E5%9B%BE%E4%B8%8E%E5%9B%BE%E7%89%87%E6%8B%BC%E6%8E%A5/id6788737924?uo=4)<br>光顺 朱 | 6788737924 | CN/US | 2026-07-22 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 29 | [Picsnp-截图拼接&长截图](https://apps.apple.com/cn/app/picsnp-%E6%88%AA%E5%9B%BE%E6%8B%BC%E6%8E%A5-%E9%95%BF%E6%88%AA%E5%9B%BE/id1503981209?uo=4)<br>露 尹 | 1503981209 | CN/US | 2026-07-29 | 免费 | 多图拼接／周边图片工具 |
| 30 | [MediaBox - 智能抠图&长截图](https://apps.apple.com/cn/app/mediabox-%E6%99%BA%E8%83%BD%E6%8A%A0%E5%9B%BE-%E9%95%BF%E6%88%AA%E5%9B%BE/id6759212192?uo=4)<br>艳君 武 | 6759212192 | CN/US | 2026-03-18 | 免费 | 多图拼接／周边图片工具 |
| 31 | [截图编辑 & 长截图拼接 Screen Cut](https://apps.apple.com/cn/app/%E6%88%AA%E5%9B%BE%E7%BC%96%E8%BE%91-%E9%95%BF%E6%88%AA%E5%9B%BE%E6%8B%BC%E6%8E%A5-screen-cut/id6480429347?uo=4)<br>Programacion Viktor Seraleev EIRL | 6480429347 | CN/US | 2026-05-18 | 免费 | 搜索候选／周边工具，关联程度待确认 |
| 32 | [Reelscap 长截图](https://apps.apple.com/cn/app/reelscap-%E9%95%BF%E6%88%AA%E5%9B%BE/id6762419371?uo=4)<br>Guodong Wang | 6762419371 | CN/US | 2026-08-11 | 免费 | 已有直接启动滚动捕捉流程；细节待实测 |
| 33 | [简拼图 - 出圈拼图，实况照片拼图，无损拼图软件全能王](https://apps.apple.com/cn/app/%E7%AE%80%E6%8B%BC%E5%9B%BE-%E5%87%BA%E5%9C%88%E6%8B%BC%E5%9B%BE-%E5%AE%9E%E5%86%B5%E7%85%A7%E7%89%87%E6%8B%BC%E5%9B%BE-%E6%97%A0%E6%8D%9F%E6%8B%BC%E5%9B%BE%E8%BD%AF%E4%BB%B6%E5%85%A8%E8%83%BD%E7%8E%8B/id6449901617?uo=4)<br>Sihoooo Network Technology Co Ltd | 6449901617 | CN/US | 2026-09-05 | 免费 | 多图拼接／周边图片工具 |
| 34 | [截图拼接](https://apps.apple.com/cn/app/%E6%88%AA%E5%9B%BE%E6%8B%BC%E6%8E%A5/id6756376282?uo=4)<br>lecoo | 6756376282 | CN/US | 2026-09-09 | 免费 | 多图拼接／周边图片工具 |
| 35 | [JPics](https://apps.apple.com/cn/app/jpics/id961328776?uo=4)<br>捷 廖 | 961328776 | CN/US | 2024-04-22 | ¥1.00 | 多图拼接／周边图片工具 |
| 36 | [剪页：长图转 PDF](https://apps.apple.com/cn/app/%E5%89%AA%E9%A1%B5-%E9%95%BF%E5%9B%BE%E8%BD%AC-pdf/id6787395910?uo=4)<br>zhen liu | 6787395910 | CN/US | 2026-07-15 | 免费 | 搜索候选／周边工具，关联程度待确认 |
| 37 | [ScrollShot - 滚动长截图 & 拼接长图](https://apps.apple.com/cn/app/scrollshot-%E6%BB%9A%E5%8A%A8%E9%95%BF%E6%88%AA%E5%9B%BE-%E6%8B%BC%E6%8E%A5%E9%95%BF%E5%9B%BE/id6760192003?uo=4)<br>勇 袁 | 6760192003 | CN/US | 2026-08-25 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 38 | [Longa - 长截图拼接·隐私打码·纯离线](https://apps.apple.com/cn/app/longa-%E9%95%BF%E6%88%AA%E5%9B%BE%E6%8B%BC%E6%8E%A5-%E9%9A%90%E7%A7%81%E6%89%93%E7%A0%81-%E7%BA%AF%E7%A6%BB%E7%BA%BF/id6784653915?uo=4)<br>俊安 陈 | 6784653915 | CN/US | 2026-07-09 | 免费 | 多图拼接／周边图片工具 |
| 39 | [浪截图-截屏拼接和滚动截图](https://apps.apple.com/cn/app/%E6%B5%AA%E6%88%AA%E5%9B%BE-%E6%88%AA%E5%B1%8F%E6%8B%BC%E6%8E%A5%E5%92%8C%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%9B%BE/id6456409417?uo=4)<br>志远 王 | 6456409417 | CN/US | 2026-06-04 | 免费 | 多图拼接／周边图片工具 |
| 40 | [我爱截图 - 截图神器](https://apps.apple.com/cn/app/%E6%88%91%E7%88%B1%E6%88%AA%E5%9B%BE-%E6%88%AA%E5%9B%BE%E7%A5%9E%E5%99%A8/id6764007616?uo=4)<br>耀 李 | 6764007616 | CN/US | 2026-07-01 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 41 | [照片拼图-图片拼接&长图拼接](https://apps.apple.com/cn/app/%E7%85%A7%E7%89%87%E6%8B%BC%E5%9B%BE-%E5%9B%BE%E7%89%87%E6%8B%BC%E6%8E%A5-%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5/id6744727550?uo=4)<br>Urban Linkware LLC | 6744727550 | CN/US | 2025-04-25 | 免费 | 多图拼接／周边图片工具 |
| 42 | [Deep伴侣-智能问答美化截长图排版格式转换](https://apps.apple.com/cn/app/deep%E4%BC%B4%E4%BE%A3-%E6%99%BA%E8%83%BD%E9%97%AE%E7%AD%94%E7%BE%8E%E5%8C%96%E6%88%AA%E9%95%BF%E5%9B%BE%E6%8E%92%E7%89%88%E6%A0%BC%E5%BC%8F%E8%BD%AC%E6%8D%A2/id6742536712?uo=4)<br>YF Co., Ltd | 6742536712 | CN/US | 2025-06-01 | 免费 | 搜索候选／周边工具，关联程度待确认 |
| 43 | [滚动截屏](https://apps.apple.com/cn/app/%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%B1%8F/id1486130680?uo=4)<br>世品 周 | 1486130680 | CN/US | 2020-09-18 | 免费 | 宣称滚动截图；具体流程待核实 |
| 44 | [滚动截屏 - 长图拼接](https://apps.apple.com/cn/app/%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%B1%8F-%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5/id6774483183?uo=4)<br>茂元 生 | 6774483183 | CN/US | 2026-09-08 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 45 | [滚动截屏Pro](https://apps.apple.com/cn/app/%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%B1%8Fpro/id6450152251?uo=4)<br>Dehui Chengzhen | 6450152251 | CN/US | 2026-03-06 | ¥48.00 | 已有直接启动滚动捕捉流程；细节待实测 |
| 46 | [滚动截长图-滚动截屏·长图拼接·长图制作神器](https://apps.apple.com/cn/app/%E6%BB%9A%E5%8A%A8%E6%88%AA%E9%95%BF%E5%9B%BE-%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%B1%8F-%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5-%E9%95%BF%E5%9B%BE%E5%88%B6%E4%BD%9C%E7%A5%9E%E5%99%A8/id6737090208?uo=4)<br>文才 黄 | 6737090208 | CN/US | 2025-08-25 | 免费 | 宣称滚动截图；具体流程待核实 |
| 47 | [iFrame 带壳截屏](https://apps.apple.com/cn/app/iframe-%E5%B8%A6%E5%A3%B3%E6%88%AA%E5%B1%8F/id1209610705?uo=4)<br>INII Co., Ltd. | 1209610705 | CN/US | 2026-08-24 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 48 | [剪长图 - 长图拼接 & 滚动截屏](https://apps.apple.com/cn/app/%E5%89%AA%E9%95%BF%E5%9B%BE-%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5-%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%B1%8F/id6779287670?uo=4)<br>Beijing Qijian Technology Co., Ltd | 6779287670 | CN/US | 2026-09-13 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 49 | [简易长截屏](https://apps.apple.com/cn/app/%E7%AE%80%E6%98%93%E9%95%BF%E6%88%AA%E5%B1%8F/id6808936318?uo=4)<br>重庆滚石科技有限公司 | 6808936318 | CN/US | 2026-09-10 | ¥1.00 | 多截图拼接／快捷指令 |
| 50 | [照片拼图软件：图片长图拼接&照片组合拼图](https://apps.apple.com/cn/app/%E7%85%A7%E7%89%87%E6%8B%BC%E5%9B%BE%E8%BD%AF%E4%BB%B6-%E5%9B%BE%E7%89%87%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5-%E7%85%A7%E7%89%87%E7%BB%84%E5%90%88%E6%8B%BC%E5%9B%BE/id6740754853?uo=4)<br>Hefei Yiqidu Technology Co., Ltd. | 6740754853 | CN/US | 2026-08-05 | 免费 | 多图拼接／周边图片工具 |
| 51 | [FrameFuse长图拼接神器](https://apps.apple.com/cn/app/framefuse%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5%E7%A5%9E%E5%99%A8/id6763426211?uo=4)<br>友健 高 | 6763426211 | CN/US | 2026-09-13 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 52 | [Stitch It · 长截图](https://apps.apple.com/cn/app/stitch-it-%E9%95%BF%E6%88%AA%E5%9B%BE/id554594252?uo=4)<br>Thirty Seven Inc. | 554594252 | CN/US | 2026-09-08 | 免费 | 多截图拼接／快捷指令 |
| 53 | [长截图拼接工具 Scrollshot](https://apps.apple.com/cn/app/%E9%95%BF%E6%88%AA%E5%9B%BE%E6%8B%BC%E6%8E%A5%E5%B7%A5%E5%85%B7-scrollshot/id6747206621?uo=4)<br>Chanaka Caldera Helessage | 6747206621 | CN/US | 2026-06-07 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 54 | [Tailor](https://apps.apple.com/cn/app/tailor/id926653095?uo=4)<br>Foundry 63 | 926653095 | CN/US | 2023-02-20 | 免费 | 多截图拼接／快捷指令 |
| 55 | [ScrollSnap - Long Screenshot](https://apps.apple.com/cn/app/scrollsnap-long-screenshot/id6759849068?uo=4)<br>晔斌 范 | 6759849068 | CN/US | 2026-08-31 | 免费 | 导入录屏后转长图；部分也支持多图 |
| 56 | [StitchShot - ScreenShotCapture](https://apps.apple.com/us/app/stitchshot-screenshotcapture/id1643120789?uo=4)<br>国辉 满 | 1643120789 | US | 2026-05-29 | Free | 已有直接启动滚动捕捉流程；细节待实测 |
| 57 | [ScrollShot 长截图工具](https://apps.apple.com/cn/app/scrollshot-%E9%95%BF%E6%88%AA%E5%9B%BE%E5%B7%A5%E5%85%B7/id6762288514?uo=4)<br>雪梅 黄 | 6762288514 | CN/US | 2026-07-12 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 58 | [Stitch Photos](https://apps.apple.com/cn/app/stitch-photos/id1620846637?uo=4)<br>Le Giang Nam | 1620846637 | CN/US | 2026-05-07 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 59 | [图长长](https://apps.apple.com/cn/app/%E5%9B%BE%E9%95%BF%E9%95%BF/id6504781578?uo=4)<br>弦芳 梁 | 6504781578 | CN/US | 2024-12-05 | 免费 | 宣称滚动截图；具体流程待核实 |
| 60 | [Pics21](https://apps.apple.com/cn/app/pics21/id1502001934?uo=4)<br>高 孙 | 1502001934 | CN/US | 2020-04-02 | 免费 | 已有直接启动滚动捕捉流程；细节待实测 |
| 61 | [长截图鸭 - 滚动截图与长图拼接](https://apps.apple.com/cn/app/%E9%95%BF%E6%88%AA%E5%9B%BE%E9%B8%AD-%E6%BB%9A%E5%8A%A8%E6%88%AA%E5%9B%BE%E4%B8%8E%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5/id6443788457?uo=4)<br>扬志 张 | 6443788457 | CN/US | 2026-03-19 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 62 | [Picsion - 智能AI拼接长截屏](https://apps.apple.com/cn/app/picsion-%E6%99%BA%E8%83%BDai%E6%8B%BC%E6%8E%A5%E9%95%BF%E6%88%AA%E5%B1%8F/id6747472077?uo=4)<br>haoqiang shan | 6747472077 | CN/US | 2026-05-02 | 免费 | 多图拼接／周边图片工具 |
| 63 | [Automatic Screenshot Stitcher](https://apps.apple.com/cn/app/automatic-screenshot-stitcher/id1604646028?uo=4)<br>Arthur Eduardo Skaetta Alvarez Desenvolvimento de Software LTDA. | 1604646028 | CN/US | 2026-09-07 | 免费 | 多图拼接／周边图片工具 |
| 64 | [Screenshot Stitching -Long Pic](https://apps.apple.com/us/app/screenshot-stitching-long-pic/id6751709121?uo=4)<br>娴 李 | 6751709121 | US | 2026-04-10 | Free | 搜索候选／周边工具，关联程度待确认 |
| 65 | [LongShot: Screenshot Stitch](https://apps.apple.com/us/app/longshot-screenshot-stitch/id6745420963?uo=4)<br>Beijing Yangming Jiuha Technology Co., Ltd | 6745420963 | US | 2026-06-27 | Free | 描述涉及录屏；具体采集入口未逐项核实 |
| 66 | [Screenshot](https://apps.apple.com/us/app/screenshot/id484042862?uo=4)<br>华 庄 | 484042862 | US | 2026-04-09 | Free | 多图拼接／周边图片工具 |
| 67 | [Long: Full Screenshot Capture](https://apps.apple.com/cn/app/long-full-screenshot-capture/id6761002190?uo=4)<br>Nanjibhai Gorasiya | 6761002190 | CN/US | 2026-06-13 | 免费 | 搜索候选／周边工具，关联程度待确认 |
| 68 | [Pictool - Long Screenshot](https://apps.apple.com/us/app/pictool-long-screenshot/id6761059900?uo=4)<br>冉 姜 | 6761059900 | US | 2026-05-05 | Free | 描述涉及录屏；具体采集入口未逐项核实 |
| 69 | [SanpSave - 一键网页全截图 PDF 图片 视频提取](https://apps.apple.com/cn/app/sanpsave-%E4%B8%80%E9%94%AE%E7%BD%91%E9%A1%B5%E5%85%A8%E6%88%AA%E5%9B%BE-pdf-%E5%9B%BE%E7%89%87-%E8%A7%86%E9%A2%91%E6%8F%90%E5%8F%96/id6745111408?uo=4)<br>慧 王 | 6745111408 | CN/US | 2026-06-04 | 免费 | 搜索候选／周边工具，关联程度待确认 |
| 70 | [PicTailor: Stitch Screenshots](https://apps.apple.com/us/app/pictailor-stitch-screenshots/id1589654548?uo=4)<br>玉婉 祝 | 1589654548 | US | 2026-09-08 | Free | 描述涉及录屏；具体采集入口未逐项核实 |
| 71 | [长图拼接 - 截图截屏智能拼接软件](https://apps.apple.com/cn/app/%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5-%E6%88%AA%E5%9B%BE%E6%88%AA%E5%B1%8F%E6%99%BA%E8%83%BD%E6%8B%BC%E6%8E%A5%E8%BD%AF%E4%BB%B6/id1565117683?uo=4)<br>OCO Inc. | 1565117683 | CN/US | 2021-05-06 | 免费 | 多图拼接／周边图片工具 |
| 72 | [Long Screenshot](https://apps.apple.com/cn/app/long-screenshot/id1631964530?uo=4)<br>WX Hongyan Technology Co., Ltd. | 1631964530 | CN/US | 2023-04-11 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 73 | [长图拼接和台词拼接 - StitchKit](https://apps.apple.com/cn/app/%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5%E5%92%8C%E5%8F%B0%E8%AF%8D%E6%8B%BC%E6%8E%A5-stitchkit/id6504301273?uo=4)<br>APPWILL COMPANY LTD | 6504301273 | CN/US | 2025-12-09 | 免费 | 多图拼接／周边图片工具 |
| 74 | [Longshot - Long Screenshot](https://apps.apple.com/cn/app/longshot-long-screenshot/id6746498059?uo=4)<br>ALEX IOAN MARCUS | 6746498059 | CN/US | 2026-01-08 | 免费 | 多图拼接／周边图片工具 |
| 75 | [Stitcher: Full Screen Capture](https://apps.apple.com/cn/app/stitcher-full-screen-capture/id6789923252?uo=4)<br>Nikita Sharin | 6789923252 | CN/US | 2026-08-31 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 76 | [Sumix - Screenshot Stitching](https://apps.apple.com/cn/app/sumix-screenshot-stitching/id1559736366?uo=4)<br>Nguyen Huu Truong | 1559736366 | CN/US | 2023-02-11 | 免费 | 多图拼接／周边图片工具 |
| 77 | [无界截图](https://apps.apple.com/cn/app/%E6%97%A0%E7%95%8C%E6%88%AA%E5%9B%BE/id6762754449?uo=4)<br>Yachao Yang | 6762754449 | CN/US | 2026-09-11 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 78 | [unroll](https://apps.apple.com/cn/app/unroll/id6761370731?uo=4)<br>ROHYO RO | 6761370731 | CN/US | 2026-04-03 | 免费 | 导入录屏后转长图；部分也支持多图 |
| 79 | [Stitch: Screenshot Combiner](https://apps.apple.com/cn/app/stitch-screenshot-combiner/id6784175577?uo=4)<br>Muhammad Zikaria | 6784175577 | CN/US | 2026-09-08 | 免费 | 多图拼接／周边图片工具 |
| 80 | [Sewing SS-Screenshot Stitching](https://apps.apple.com/cn/app/sewing-ss-screenshot-stitching/id1496738162?uo=4)<br>Hyperlink Infosystem | 1496738162 | CN/US | 2020-05-29 | 免费 | 多图拼接／周边图片工具 |
| 81 | [妙缝](https://apps.apple.com/cn/app/%E5%A6%99%E7%BC%9D/id6743531863?uo=4)<br>杭州引力网络技术有限公司 | 6743531863 | CN/US | 2026-08-01 | 免费 | 多图拼接／周边图片工具 |
| 82 | [Picroll - Tiny Screen Stitcher](https://apps.apple.com/us/app/picroll-tiny-screen-stitcher/id1645275205?uo=4)<br>TinyWork Apps | 1645275205 | US | 2025-08-13 | $4.99 | 多图拼接／周边图片工具 |
| 83 | [长图拼接-截屏拼图专业版](https://apps.apple.com/cn/app/%E9%95%BF%E5%9B%BE%E6%8B%BC%E6%8E%A5-%E6%88%AA%E5%B1%8F%E6%8B%BC%E5%9B%BE%E4%B8%93%E4%B8%9A%E7%89%88/id6751446749?uo=4)<br>Liangzhi Zhang | 6751446749 | CN/US | 2025-09-27 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 84 | [Pic Stitch - screen shot app](https://apps.apple.com/cn/app/pic-stitch-screen-shot-app/id6748349736?uo=4)<br>Editr Apps Inc. | 6748349736 | CN/US | 2026-07-20 | 免费 | 多图拼接／周边图片工具 |
| 85 | [截图编辑器 - scr.shot](https://apps.apple.com/cn/app/%E6%88%AA%E5%9B%BE%E7%BC%96%E8%BE%91%E5%99%A8-scr-shot/id6753865418?uo=4)<br>Uladzislau Nasonau | 6753865418 | CN/US | 2026-07-08 | 免费 | 多图拼接／周边图片工具 |
| 86 | [Photo Stitch!](https://apps.apple.com/cn/app/photo-stitch/id6746974251?uo=4)<br>Thanh Hai Le | 6746974251 | CN/US | 2026-08-20 | 免费 | 多图拼接／周边图片工具 |
| 87 | [Montage - Pic Stitch](https://apps.apple.com/cn/app/montage-pic-stitch/id6448123812?uo=4)<br>APTE Ltd | 6448123812 | CN/US | 2023-07-14 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 88 | [截屏速记 - 用语音标注截图和照片](https://apps.apple.com/cn/app/%E6%88%AA%E5%B1%8F%E9%80%9F%E8%AE%B0-%E7%94%A8%E8%AF%AD%E9%9F%B3%E6%A0%87%E6%B3%A8%E6%88%AA%E5%9B%BE%E5%92%8C%E7%85%A7%E7%89%87/id1092862147?uo=4)<br>政武 刘 | 1092862147 | CN/US | 2023-08-09 | 免费 | 多图拼接／周边图片工具 |
| 89 | [Castly+](https://apps.apple.com/cn/app/castly/id6447676034?uo=4)<br>HONGKONG BLUE WHALE AND OCEAN TECHNOLOGY CO., LIMITED | 6447676034 | CN/US | 2026-08-28 | 免费 | 描述涉及录屏；具体采集入口未逐项核实 |
| 90 | [LongShot: Scrolling Screenshot](https://apps.apple.com/us/app/longshot-scrolling-screenshot/id6798898681?uo=4)<br>嘉琳 冯 | 6798898681 | US | 2026-09-08 | Free | 多截图拼接／快捷指令 |
| 91 | [Web2Pics: Full Page Screenshot](https://apps.apple.com/cn/app/web2pics-full-page-screenshot/id845013732?uo=4)<br>Bharti Verma | 845013732 | CN/US | 2026-01-29 | 免费 | 网页／Safari 整页截图 |
| 92 | [WebCapture- full page capture](https://apps.apple.com/cn/app/webcapture-full-page-capture/id901960139?uo=4)<br>Youngwan Choi | 901960139 | CN/US | 2026-08-08 | ¥15.00 | 网页／Safari 整页截图 |
| 93 | [截图 ／ Web](https://apps.apple.com/cn/app/%E6%88%AA%E5%9B%BE-web/id6743155823?uo=4)<br>Paran | 6743155823 | CN/US | 2026-08-27 | ¥12.00 | 网页／Safari 整页截图 |
| 94 | [Website Screenshot Capture](https://apps.apple.com/cn/app/website-screenshot-capture/id6763598896?uo=4)<br>Rodrigo Dutra de Oliveira | 6763598896 | CN/US | 2026-06-15 | ¥58.00 | 网页／Safari 整页截图 |
| 95 | [Page Screenshot: web2screen](https://apps.apple.com/cn/app/page-screenshot-web2screen/id6670213166?uo=4)<br>Pierre Stanislas | 6670213166 | CN/US | 2025-12-12 | ¥15.00 | 网页／Safari 整页截图 |
| 96 | [screenshat](https://apps.apple.com/cn/app/screenshat/id6769209381?uo=4)<br>LanguageCraft | 6769209381 | CN/US | 2026-07-28 | 免费 | 网页／Safari 整页截图 |

## 平台与流程来源

- [Apple：iPhone 截图与整页截图](https://support.apple.com/en-ie/guide/iphone/iphc872c0115/ios)
- [Picsew：Scrolling Capture 操作说明](https://docs.picsew.app/getting-started/extensions/scrolling-capture/)
- [ReplayKit 安全机制](https://support.apple.com/en-gb/guide/security/seca5fc039dd/web)
- [ScreenCaptureKit 框架说明](https://developer.apple.com/documentation/screencapturekit)
- [ScreenCaptureKit：Capturing screen content on iOS（iOS 27+）](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios)
- [Apple：2026-09-09 新系统应用提交说明](https://developer.apple.com/news/?id=k1mtkt1k)
- [Android：ScrollCaptureCallback](https://developer.android.com/reference/android/view/ScrollCaptureCallback)
- [Apple：运行时沙箱安全](https://support.apple.com/guide/security/security-of-runtime-process-sec15bfe098e/web)
- [App Review Guidelines，尤其 2.5.1、2.5.9、2.5.14](https://developer.apple.com/app-store/review/guidelines/)
- [ScrollShot 官方说明](https://scrollshot.work/)
- [LongShot 官方说明](https://getlongshot.app/)
