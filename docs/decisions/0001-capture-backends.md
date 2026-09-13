# 屏幕采集后端

## 决定

当前可编译基线采用 ReplayKit Broadcast Upload Extension，最低部署 iOS 18。拼接核心仅依赖灰度帧和几何坐标，避免耦合具体采集 SDK。

本机 Xcode 26.3 仅包含 iPhoneOS SDK 26.2。此前调研引用的 iOS 27 ScreenCaptureKit 后台整屏采集应在获得对应 SDK 后单独实现、编译与验证；本轮不把未编译的猜测接口接入发布目标。

## ReplayKit 边界

- 用户主动通过系统选择器开始，保留系统指示。
- 扩展不持有回调结束后的 CMSampleBuffer；在串行回调内有界处理，跳过不需要的帧。
- 音频样本不参与处理，不请求麦克风。
- 先保存片段与会话状态，再结束广播；自动停止可能伴随系统提示，需要真机核验。
- 广播扩展必须使用有效 App Group。仅宿主的演示模式允许使用沙盒回退目录。

## iOS 27 启用清单

1. 安装并验证 Xcode 27 或更高 SDK 的官方可用版本。
2. 核对 SCContentSharingPicker、SCStream、screen-capture 后台模式及权限键的实际签名。
3. 接入同一有界帧管线，不引入完整视频中间文件。
4. 对后台、结束、系统中断、旋转、资源占用和隐私指示执行独立真机测试。
5. 将结果记录到设备验收报告后，决定是否启用该后端。

参考：[Apple ReplayKit](https://developer.apple.com/documentation/replaykit)、[Apple iOS ScreenCaptureKit 示例](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios)。
