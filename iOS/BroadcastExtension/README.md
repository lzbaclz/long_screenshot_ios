# ReplayKit 捕捉扩展

扩展的 `NSExtensionPrincipalClass` 应为 `$(PRODUCT_MODULE_NAME).SampleHandler`，`NSExtensionPointIdentifier` 为 `com.apple.broadcast-services-upload`，`RPBroadcastProcessMode` 为 `RPBroadcastProcessModeSampleBuffer`。`SharedAppGroupIdentifier` 必须与主应用及两边的 App Group entitlement 一致。

`SampleHandler` 只处理 `.video`。按照 Apple 对回调生命周期的说明，样本不会在 `processSampleBuffer` 返回后被保留；每 0.15 秒至多同步分析一帧，无待处理帧队列。灰度输入只横向缩至最多 144 像素，完整保留纵向原始像素行，使核心拼接器的行数与原图裁切行数完全一致。

通过匹配的新增部分才生成原分辨率 PNG 分块。拒绝的画面从不拼接；连续约 0.8 秒无法恢复可信重叠就结束，并保留连续部分。短距离回滚使用核心的有界历史引用去重，回到已捕捉区间不会再次追加。旋转、尺寸变化和系统暂停也结束并保存部分结果。

正式开始广播后立即持有第一帧候选。没有确认滚动时，场景变化会用当前帧替换起点候选，允许用户切换目标应用；首次可靠的向下位移才一起保存候选与新增部分。开始拼接后，场景变化会结束并保留已有连续内容。没有发生确认滚动就结束，会得到说明原因的空草稿。第一帧必须实际显示在采集流中，系统尚未提供的内容无法补回。

完成、静止超时、达到长度/时长上限以及失败都先保存终态。ReplayKit 只提供 `finishBroadcastWithError` 供扩展主动结束；即使图片生成成功，系统仍可能显示结束提示，不能承诺静默结束。用户通过系统按钮结束则走 `broadcastFinished`。

## 必须通过真机确认的事项

- iOS 18 与当前系统上的广播入口、后台持续采集、主动停止提示、锁屏/电话打断。
- iPhone 实际 CPU、耗电、扩展峰值内存、20 屏分块存储与大图导出。Mac 合成帧性能不等于设备性能。
- 状态栏、导航栏、底栏和动态内容可能影响匹配。默认零比例会保守识别固定区域；边界不确定时停止并引导设置上下裁除比例，不能静默裁掉正文。自动和手动两种方式都需要真机验证。
- 起点候选在系统弹层、应用切换动画下的可靠性，以及控制中心直接启动与主应用启动后切换的区别。

本机 SDK 26.2 可以编译 ReplayKit 代码。在线文档已为较新系统标记弃用，因此必须实际验证目标系统，不能由能够编译推导所有 iOS 版本均可用。

## 官方依据

- [RPBroadcastSampleHandler](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler)
- [processSampleBuffer 生命周期](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler/processsamplebuffer(_:with:))
- [屏幕方向附件](https://developer.apple.com/documentation/replaykit/rpvideosampleorientationkey)
- [扩展停止接口](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler/finishbroadcastwitherror(_:))
- [Image I/O 输出](https://developer.apple.com/documentation/imageio/cgimagedestination)
