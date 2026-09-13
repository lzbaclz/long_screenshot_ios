# 共享存储与图片处理

主应用与广播扩展共同编译此目录。`CaptureSessionRepository` 使用 `SharedAppGroupIdentifier` 对应的 App Group；真实设备缺少签名共享容器时明确失败，仅模拟器允许主动指定本地演示回退。

## 宿主接口

```swift
let repository = try CaptureSessionRepository.application(allowLocalFallback: true)
try repository.saveConfiguration(.init(idleStopSeconds: 5))
try repository.recoverInterruptedSessions()
let sessions = try repository.listSessions()
let renderer = CaptureImageRenderer(repository: repository)
let image = try renderer.preview(sessionID: sessions[0].id)
let url = try renderer.export(sessionID: sessions[0].id, format: .png)
```

可选静止结束为手动、5 秒、10 秒；最长捕捉 120 秒，最长 20 屏。首次实际滚动后才启动静止结束判断，避免把准备阶段当成完成。

`CaptureFramePipeline` 在确认首次向下滚动之前只持有起点候选图。切换应用造成场景不匹配时，候选会替换为当前场景；首次可靠向下滚动后一起提交候选与新增尾部，保留起点内容。其后不再因场景变化重置起点，而是拒绝不可靠的接缝。结束时仍没有确认滚动，则显示没有可拼接内容，不把空结果标为成功。

应用切换与首次滑动过快产生的未知缺口可能无法单凭画面区分。凡是替换过候选起点，清单都会记录 `startWarning`，结束说明要求用户检查图片开头；不能把最终连续片段表述为保证覆盖最早显示的所有内容。

当上下忽略比例都为零时，管线会保守识别固定区域，并在首次输出前冻结 `effectiveConfiguration`。无法区分固定栏与页面留白时返回 `regionWarning`，扩展停止并引导手动设置。用户显式设置非零忽略比例会使用该设置。屏数上限按照最终有效视口高度计算，自动检测的实际准确率仍需真机矩阵验证。

`createSession(configuration:isDemo:)`、`appendStrip(image:sourceTopPixel:to:)` 和 `saveManifest(_:)` 可用于生成明确标记为演示的本地样本。正式捕捉中，只有扩展写清单；宿主通过单独的停止请求文件请求结束。

## 数据安全与恢复

- 每个原始分块以 UUID 命名的 PNG 原子发布，随后才原子更新清单。失败最多留下孤立分块，不会让清单引用尚未完成的文件。
- JSON、分块与导出使用首次解锁后可访问的文件保护；目录不参加备份。没有网络客户端或完整录屏文件。
- 扩展在整个捕捉期间持有每条记录的 POSIX 文件锁租约，并每秒更新心跳。宿主必须先成功取得同一租约、重新读取最新清单，才会把超过 15 秒未更新的捕捉标记为中断。活着但暂时繁忙的扩展不会被误判；进程被系统结束会自动释放锁。编辑、删除也取得同一租约，运行中的记录不能编辑或删除。
- 损坏的目录不自动删除。单个无法解码的目录不会使全部有效记录消失；其原文件保留，当前 UI 暂不提供损坏目录修复入口。
- 导出逐块解码，始终生成新文件。删除记录是用户明确触发的操作，会删除该记录及其导出。

## 编辑坐标与内存界限

`CaptureEditMetadata` 中的裁剪与黑色遮挡矩形使用 0 到 1 归一化坐标，参照**接缝裁去重复行后、最终裁剪前**的整个拼接画布。顺序为接缝裁行 → 拼接画布定位 → 裁剪 → 覆盖不透明黑色矩形。接缝编辑如果改变画布高度，既有归一化遮挡位置会随画布重新映射，编辑 UI 需要让用户检查遮挡位置。

`preview(..., editsOverride:)` 可无副作用地预览临时编辑。编辑器用仅含接缝信息的覆盖值获取裁剪前画布，再自行叠加草稿框。

PNG/JPEG 导出限制为最多 3,200 万像素、单边最多 32,000 像素。默认超限直接报错；调用方展示 `outputDimensions(..., allowDownscale: true)` 返回的尺寸并取得用户明确选择后，才可用 `export(..., allowDownscale: true)` 生成缩小版。原始分块不会降采样或覆盖。该限制意味着 20 屏高分辨率内容可能需要缩小导出，并非无条件支持 20 屏原分辨率单图。

输出画布有上限，但会创建完整的有限输出位图；逐块读取减少源图峰值，并不等于 PNG 编码完全逐行、恒定内存。3,200 万像素上限仍需低内存真机验证。

## 验证

`../SharedTests/CaptureStorageTests.swift` 检查恢复、非法路径、编辑保护、导出尺寸、不透明遮挡像素和原始数据不变。由主应用 XCTest target 执行。截图、图片编码与 ReplayKit 生命周期还需要真实设备验收。
