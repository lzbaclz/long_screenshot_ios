# ReplayKit 捕捉扩展

扩展的 `NSExtensionPrincipalClass` 应为 `$(PRODUCT_MODULE_NAME).SampleHandler`，`NSExtensionPointIdentifier` 为 `com.apple.broadcast-services-upload`，`RPBroadcastProcessMode` 为 `RPBroadcastProcessModeSampleBuffer`。`SharedAppGroupIdentifier` 必须与主应用及两边的 App Group entitlement 一致。

`SampleHandler` 只处理 `.video`。按照 Apple 对回调生命周期的说明，样本不会在 `processSampleBuffer` 返回后被保留；每 0.15 秒至多同步分析一帧，无待处理帧队列。灰度输入只横向缩至最多 144 像素，完整保留纵向原始像素行，使核心拼接器的行数与原图裁切行数完全一致。

通过匹配的新增部分才进入连续长图。拒绝的画面从不拼接；已有长图时连续至少 8 秒且至少 6 个样本无法恢复可信重叠才结束，期间保留可信参考以等待恢复。向上和向下的新内容分别接入顶部、底部；回到已捕捉区间不会重复。旋转、尺寸变化和系统暂停结束后按实际已保存内容给出结果。

正式开始广播后将第一帧候选无损写入当前会话的共享存储，准备阶段不常驻原尺寸位图。没有确认滚动时，持续场景变化会用当前帧替换候选，且新图和清单发布成功后才释放旧候选；首次可信的任一方向位移才提交连续正文。首段提交成功确认之前保留候选，因此首次写盘失败或进程被系统结束后仍可恢复一张已保存的单屏。单屏、无图失败和连续长图分开标注。系统没有提供的内容无法补回。

完成、静止超时、达到长度/时长上限以及失败都先保存终态。ReplayKit 只提供 `finishBroadcastWithError` 供扩展主动结束；即使图片生成成功，系统仍可能显示结束提示，不能承诺静默结束。用户通过系统按钮结束则走 `broadcastFinished`。

## 必须通过真机确认的事项

- iOS 18 与当前系统上的广播入口、后台持续采集、主动停止提示、锁屏/电话打断。
- iPhone 实际 CPU、耗电、扩展峰值内存、20 屏分块存储与大图导出。Mac 合成帧性能不等于设备性能。
- 状态栏、导航栏、底栏和动态内容可能影响匹配。默认零比例用可信区域做内部接缝，保留完整原始首尾各一次；暂时不确定会等待，手动范围才按用户设置裁除。自动和手动两种方式都需要真机验证。
- 起点候选在系统弹层、应用切换动画下的可靠性，以及控制中心直接启动与主应用启动后切换的区别。

本机 SDK 26.2 可以编译 ReplayKit 代码。在线文档已为较新系统标记弃用，因此必须实际验证目标系统，不能由能够编译推导所有 iOS 版本均可用。

## 官方依据

- [RPBroadcastSampleHandler](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler)
- [processSampleBuffer 生命周期](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler/processsamplebuffer(_:with:))
- [屏幕方向附件](https://developer.apple.com/documentation/replaykit/rpvideosampleorientationkey)
- [扩展停止接口](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler/finishbroadcastwitherror(_:))
- [Image I/O 输出](https://developer.apple.com/documentation/imageio/cgimagedestination)
