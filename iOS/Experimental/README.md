# iOS 27 ScreenCaptureKit 实验后端

状态：已按 Apple 官方 iOS 27 示例及符号文档实现。设备 SDK 27 CI 已进入实验适配器类型检查，发现五个实际标为 iOS 不可用的配置属性；本地已移除这些调用，**修复尚待新一轮 SDK 27 编译，也未通过真机验收**。本机只有 SDK 26.2。不要把关闭编译开关后的成功构建写成此后端编译成功。

两个 Swift 文件的全部内容由 `#if CAPTUREKIT_IOS27 && os(iOS)` 包围，类型标记为 `@available(iOS 27.0, *)`。默认 UI 与 ReplayKit 扩展没有替换。本目录不修改工程签名、Info.plist、生产默认值或购买功能。

## 官方接口核对

已读取 Apple 的 [iOS 27 示例](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios) 及其官方 [下载 ZIP](https://docs-assets.developer.apple.com/published/91f0562d72a9/CapturingScreenContentInIOS.zip)。下载参考仅存放于 `.work/apple-screencapturekit/`，不纳入应用资源，也没有复制示例的视频编码实现。

| 使用内容 | 依据与处理 |
| --- | --- |
| 整屏系统选择器 | `SCContentSharingPicker.shared`、`isAvailable`、`present()`；不调用仅捕捉自身应用的 `presentForCurrentApplication()` |
| 选择器观察 | `SCContentSharingPickerObserver` 的选择、取消、失败回调；独立弱引用桥接到 MainActor，并给每次请求编号，忽略旧回调 |
| 无音频 | 关闭 `showsMicrophoneControl`、`showsCameraControl`，配置 `capturesAudio=false`，只添加 `.screen` output；不调用实际 iOS SDK 禁止的 `captureMicrophone` setter |
| 像素尺寸 | `filter.contentRect × filter.pointPixelScale` 配置输出宽高；不使用 UIKit 猜测另一应用尺寸 |
| 应用侧有界处理 | 应用最多每 0.15 秒处理一帧，不额外排队保留样本。iOS 不公开 `queueDepth` 或 `minimumFrameInterval` setter；系统队列由框架管理，不承诺可设为三帧 |
| 状态与方向 | 使用 `SCStreamFrameInfo.status` / `SCFrameStatus` 和 `.videoOrientation` 的 `CGImagePropertyOrientation` 值；不沿用 ReplayKit 的附件键 |
| 手动及系统停止 | `SCStream.stopCapture()` 与 `SCStreamDelegate`；`SCStreamError.Code.userStopped` 按用户正常停止处理，其他暂停/空白/失效状态保守保留部分 |

没有使用 macOS 专属的 `allowedPickerModes`、`allowsChangingSelectedContent` 或枚举全部可共享应用来绕过用户选择。官网某些成员页的 iOS 可用性元数据也与 beta 6 实际头文件冲突；以所选 SDK 编译器的可用性诊断为准。参见 [选择器](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker)、[队列深度](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/queuedepth)、[帧方向](https://developer.apple.com/documentation/screencapturekit/scstreamframeinfo/videoorientation)。

## 工程配置（仅实验变体）

1. 使用真正提供 iOS 27 SDK 的 Xcode，把本目录 Swift 源加入宿主 target；设置 `SWIFT_ACTIVE_COMPILATION_CONDITIONS` 包含 `CAPTUREKIT_IOS27`。扩展不需要编译此目录。
2. 宿主 Info.plist 的 `UIBackgroundModes` 添加 `screen-capture`，否则不能假定整屏流在宿主退到后台后继续。此纯图像实现不添加 `audio` 后台模式，也不启动 `AVAudioSession`。
3. Apple 下载示例的 entitlement 含 `com.apple.developer.screen-recording=true`。在实验 target 中按 Xcode 27 能力配置及实际 provisioning profile 验证，不能把编辑 entitlement 文件等同获得权限。继续保留现有 App Group，以复用作品库与跨进程租约。
4. ScreenCaptureKit 框架总文档要求 `NSScreenCaptureUsageDescription`；建议中文“在你授权后读取屏幕画面，在本机生成长截图。”、英文“Read screen frames after your consent to create long screenshots on your iPhone.”。官方 iOS 下载示例自己的 Info.plist 没有这个键，因此需要在目标 SDK 和真机上明确核对差异，不能将其缺失解读为无需授权。[框架权限说明](https://developer.apple.com/documentation/screencapturekit)
5. 现有照片添加权限说明仍由保存流程使用。此后端不需要相机或麦克风用途说明；不得为了让示例功能全部运行而额外请求这些权限。
6. `ScreenCaptureKit` 应仅在支持的运行时调用，保持运行时 `#available` 检查。实验变体需弱链接新框架，并检查最终 Mach-O 的载入命令，避免在没有此框架的 iOS 18 上启动失败。不要把不存在于 SDK 26.2 的框架无条件添加至基线；关闭开关的基线构建仍必须通过。

目前没有向现有 target 自动添加这些配置，也没有将实验按钮展示给用户。工程与 CI 维护者取得新 SDK 后需先单独构建，再决定是否接入测试入口。

## 宿主接口

```swift
#if CAPTUREKIT_IOS27
if #available(iOS 27.0, *) {
    // 在 MainActor 保存强引用，不能只用局部变量临时构造。
    let coordinator = ScreenCaptureKit27Coordinator(repository: repository)
    // 仅在用户明确点击“开始”后调用：
    try coordinator.presentEntireDisplayPicker(configuration: configuration)
    // 观察 phase / sessionID / message，并从现有 repository 读取结果。
    // 用户点击停止：await coordinator.stop()
    // 场景销毁或切换后端之前：await coordinator.invalidate()
}
#endif
```

`phase` 为 `idle / choosing / starting / capturing / stopping / finished / failed`。`finished` 表示捕捉生命周期已结束；图片可能是带说明的部分结果，应继续读取会话状态，不能只凭 phase 显示“完整成功”。取消选择不会创建有效截图。已有 ReplayKit 活跃会话时拒绝开始；最终 UI 也须保证一次仅管理一个捕捉后端。

来源更改不会在已拼接内容后直接接上另一画面；系统更新已有流的选择会结束当前部分。起点候选、固定区域识别、不可靠接缝拒绝、20 个有效视口与 120 秒上限、5/10 秒静止结束均复用当前共享管线与配置。

## 数据与重复实现边界

`ScreenCaptureKit27FrameSink` 使用同一 `CaptureFramePipeline`、`CaptureSessionRepository`、租约与 PNG 分块写入，不添加 `SCRecordingOutput`、`SCClipBufferingOutput`、视频编码器或网络发送。原始行分辨率的灰度对齐方式保持一致。保存失败会保留此前原子清单，报告持久化错误，交由已有恢复机制处理。

生命周期、心跳和图像转换暂与 `SampleHandler` 有有意的局部重复。为避免未验证新 SDK 改动影响已测试的 ReplayKit，此次没有重构生产回调。完成两后端相同样本回归后，应抽出共用的会话处理器，防止后续规则漂移。

## 编译与真机证据表

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| SDK 26.2，开关关闭，共享代码与 ReplayKit 完整代码生成 | 2026-09-14 本机通过 | `swiftc -emit-object -whole-module-optimization -swift-version 6 -strict-concurrency=complete -application-extension`，包含本目录且未设置开关 |
| 仅语法解析，开关开启 | 2026-09-14 本机通过；不是类型检查 | `swiftc -frontend -parse -D CAPTUREKIT_IOS27 ... iOS/Experimental/*.swift` |
| Xcode / SDK 27，开关开启真实编译 | **已进入设备 SDK 类型检查；五处可用性调用已本地修复，等待重跑** | 下方第二次 CI 记录 |
| iOS 27 真机选择器、授权、整屏与后台 | **未执行** | — |
| 与 ReplayKit 相同内容的像素/丢帧/内存比较 | **未执行** | — |
| 停止期间启动、取消后的旧回调、来源更改 | **未执行** | — |
| 固定栏、快滑、旋转、锁屏及权限撤回 | **未执行** | — |
| 20 屏与超限导出 | **未执行** | — |

CI 必须同时记录 `xcodebuild -version`、所选 SDK、开关值及退出码。仅找到名字像 Xcode 27 的 runner 或把此文件排除出编译都不能证明通过。上表未完成前，不替换默认后端、不变更商店兼容性承诺，也不把本实现计入 G1/G3 的实机结果。

如果后续决定向用户开放此后端，须同步更新引导、审核步骤及隐私政策中“由扩展接收画面”的说明，使其覆盖宿主直接接收帧的实际行为。当前实验协调器另有两条英文配置错误提示，正式双语入口接入前还需纳入本地化回归。

## 2026-09-14 首次新 SDK CI 记录

- 代码提交：`83aa61acefd531f7f13f5d093ac03799215db1e6`，分支 `feat/scroll-capture-mvp`。
- [CI run 34790689726 的 ios27-compile job](https://github.com/lzbaclz/long_screenshot_ios/actions/runs/34790689726/job/103814212994) 已实际运行，状态为 `failure`，不是排队或 runner 不可用。
- runner：`xcode-27-arm64`，镜像 `20260907.0173.1`；Xcode `27.0`、build `27A5252f`，路径为 `Xcode_27_beta_6.app`。
- 实际编译 SDK：`iPhoneSimulator27.0.sdk`，构建目标 `generic/platform=iOS Simulator`；开关值为 `DEBUG CAPTUREKIT_IOS27`，`CODE_SIGNING_ALLOWED=NO`。
- 唯一编译失败诊断来自 `BroadcastExtension` 的链接：`ld: framework 'ScreenCaptureKit' not found`。全局 `OTHER_LDFLAGS` 把 `-weak_framework ScreenCaptureKit` 也传给了不需要该框架的广播扩展。
- 日志没有实验 Swift 文件的编译记录或类型错误；不能据此修改适配器 API，也不能宣称新接口已经编译通过。原始 job 日志仅保存在本机 `.work/ios27-ci-audit/job-103814212994.log`。

下一次由 CI/工程维护者先确认 `iphoneos` SDK 内实际存在的框架，再以 `generic/platform=iOS`、关闭签名的宿主实验构建验证；弱链接配置应限于需要框架的实验宿主。此处仅记录建议，没有修改工作流或工程。若设备 SDK 也不提供框架，应保存其目录与工具链证据，不通过 `canImport` 静默跳过适配器来制造成功结果。

本可选任务不阻塞已上传的 TestFlight `0.1.0 (1)`：该分发 IPA 使用默认 ReplayKit，未载入 ScreenCaptureKit。本次没有改动生产二进制、提交、推送或取消 CI。

## 2026-09-14 第二次新 SDK CI 与修复

[run 34791151569 / job 103815554095](https://github.com/lzbaclz/long_screenshot_ios/actions/runs/34791151569/job/103815554095) 使用 `SDK27` 配置、`generic/platform=iOS`、关闭签名，成功找到并读取实际设备 SDK 的框架头文件：

```text
/Applications/Xcode_27_beta_6.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk/System/Library/Frameworks/ScreenCaptureKit.framework/Headers/SCStream.h
```

工具链仍为 Xcode `27.0` / `27A5252f`。这次不是框架缺失：编译器已处理两份实验 Swift 源，报告下列属性明确 `API_UNAVAILABLE(ios)`：

| 属性 | 实际头文件位置 | 本地修复 |
| --- | --- | --- |
| `pixelFormat` | SCStream.h:254 | 不设像素格式；由 Core Image 处理系统提供的 CVPixelBuffer |
| `minimumFrameInterval` | SCStream.h:240 | 不配置系统帧率；保留帧处理器的 0.15 秒工作节流 |
| `queueDepth` | SCStream.h:299 | 不设置系统队列深度；仅保证应用不增加样本排队 |
| `captureMicrophone` | SCStream.h:380 | 通过 picker 关闭麦克风控制，且不添加麦克风输出 |
| `preservesAspectRatio` | SCStream.h:264 | 使用系统默认比例策略，按实际输出尺寸处理 |

该 SDK 的队列深度注释描述默认八帧，而先前在线文档描述三帧；这进一步说明不能将线上跨平台说明当成 iOS 实测内存上限。具体缓冲、输入格式和输出比例需要目标设备测量。

修复仅修改实验协调器及本文，未修改默认 ReplayKit、生产 Beta、工程或工作流。开关开启的本地语法解析与 `git diff --check` 可验证语法/格式，但本机没有 SDK 27，不能将它们视为修复后类型检查通过；下一次由维护者推送后读取 CI 的真实结果。原始日志保存在 `.work/ios27-ci-audit/job-103815554095.log`。
