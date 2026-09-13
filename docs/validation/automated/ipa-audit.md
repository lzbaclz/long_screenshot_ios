# Longlet 0.1.0（1）IPA 静态审计

审计日期：2026-09-14。方式：只读检查待上传 IPA、对应 xcarchive 及安全解包副本，没有修改二进制、签名或凭据，没有执行上传。

**结论：本次列出的分发物静态检查均通过。** IPA 是 Apple Distribution 重签后的设备构建；归档保留开发签名，两者不能混为同一个分发文件。本结果不表示 TestFlight 已处理完成，也不表示真机捕捉或 G1/G2/G3 已通过。用户已明确选择先分发 TestFlight，再自行执行真机验证。

## 锁定的文件

| 项目 | 实际值 |
| --- | --- |
| IPA | `.work/archives/Longlet-0.1.0-1/Export/ScrollCapture.ipa` |
| 大小 | 3,162,628 字节 |
| IPA SHA-256 | `5a373cf9d03ecab14bbc24f64f752c1432b2bd913ebdf12186a1b8bf745a9a44` |
| 对应归档 | `.work/archives/Longlet-0.1.0-1/Longlet.xcarchive` |
| 归档创建时间 | 2026-09-13 23:27:03 UTC |
| 导出方法 | `app-store-connect` |
| 核验工具 | Xcode 26.3 工具链中的 `otool`、`lipo`、`dwarfdump`、`assetutil`；系统 `codesign`、`file`；Python `zipfile`、`plistlib`、SHA-256 |

## 检查结果

| 检查项 | IPA 实际结果 | 判定 |
| --- | --- | --- |
| 主应用标识 | `dev.lzbaclz.longscreenshot` | 通过 |
| 扩展标识 | `dev.lzbaclz.longscreenshot.BroadcastExtension` | 通过 |
| 两个 bundle 的版本/构建 | 均为 `0.1.0` / `1`，与归档一致 | 通过 |
| 最低系统与平台 | 均为 `18.0`，`CFBundleSupportedPlatforms = [iPhoneOS]` | 通过 |
| App Group | 主应用、扩展的 Info.plist 与签名 entitlement 均为 `group.dev.lzbaclz.longscreenshot` | 通过 |
| 签名主体一致性 | 两个 bundle 的已签名团队标识相同，application-identifier 后缀分别对应正确 bundle ID | 通过 |
| 分发签名 | 主应用与扩展均含 Apple Distribution 签名链，`get-task-allow = false` | 通过 |
| 签名完整性 | 两个 bundle 分别 `codesign --verify --strict`，以及宿主 `--deep --strict`，退出码均为 0 | 通过 |
| 麦克风/相机用途说明 | 两个 Info.plist 及各自中英文 InfoPlist.strings 均无相应 UsageDescription 键 | 通过 |
| 音频后台模式 | 两个 bundle 均未声明 `UIBackgroundModes`，无 `audio` 模式 | 通过 |
| 隐私清单 | 主应用与扩展均包含有效 `PrivacyInfo.xcprivacy`；具体用途见下表 | 通过 |
| 图标 | IPA 实际 `Assets.car` 中 AppIcon 的 phone/pad rendition 均为 1024 × 1024、RGB、sRGB、`Opaque = true` | 通过 |
| 新框架载入 | 两个二进制载入命令均无 ScreenCaptureKit，连弱载入也未出现；均正常引用 ReplayKit | 通过 |
| 架构与目标平台 | Payload 仅有主应用和广播扩展两个 Mach-O，均仅 `arm64`；`LC_BUILD_VERSION platform = 2`（iOS）、minos 18.0、SDK 26.2 | 通过 |
| 模拟器/测试产物 | 无 x86/i386 切片，无 iOS Simulator 目标 Mach-O，无 `.xctest` 测试包 | 通过 |
| 归档匹配 | 主应用与扩展 Mach-O UUID 分别与归档一致；IPA/归档 Assets.car SHA-256 相同 | 通过 |
| 原文件未改动 | 审计结束重新计算 IPA SHA-256，与开始时一致 | 通过 |

“无模拟器产物”指二进制架构、Mach-O 平台及打包内容检查；不据此宣称所有可用于演示的业务代码都被移除。

## 实际打包的隐私用途

主应用与扩展两份清单一致：

| Required Reason API 类别 | 理由 |
| --- | --- |
| `NSPrivacyAccessedAPICategorySystemBootTime` | `35F9.1` |
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1` |

两份清单都声明 `NSPrivacyTracking = false`，tracking domains 与 collected data types 为空。本审计证明声明随包存在；**清单及权限键本身不能证明实际数据处理行为、理由适用性或所有隐私要求已经满足**。这些仍需结合代码、运行行为与最终商店申报复核。

## 二进制关联与签名区别

| 对象 | Mach-O UUID | IPA 二进制 SHA-256 |
| --- | --- | --- |
| 主应用 | `28E3608F-3EE7-3E51-8F3B-9E58585F3193` | `0e84188ec1902793f22b8dd7cf22bdd2e2906af667452e2ea8b6f03d415b9b7c` |
| 广播扩展 | `E0E57671-02DD-328C-AB97-57F42B03E150` | `5ebda34671d11342707e1d7d9046dcc0157998aa462cd980cd1c9a752c224011` |

归档中的主应用和扩展均为 `get-task-allow = true` 的开发签名；导出过程将它们重签为分发版本，因此归档与 IPA 二进制 SHA-256 不相同，UUID 一致。应上传本报告锁定的分发 IPA，不应把开发归档中的 `.app` 直接视为同一分发物。

两份 Assets.car 的共同 SHA-256 为 `c7855c4ba7e6f9b0cfebe8146f90e0628e0fc746e33f397833afbb65e3a10544`。本机原始结构化结果和载入命令保留在 `.work/ipa-audit/`；该目录是临时核验材料，不含本次新增或导出的签名凭据。

## 尚未由此次检查证明的事项

- Apple 服务端的签名接受、上传、构建处理、Beta Review、邀请分发或实际安装成功。
- 屏幕授权、目标 App 兼容性、连续完整捕捉、照片权限、静止结束、资源峰值和恢复的真机表现。
- Pro 商品的真实商店配置与购买沙盒结果。
- iOS 27 ScreenCaptureKit 实验实现：本 IPA 没有链接该后端，不能用此构建证明其实机能力。
- 真实参与者人数、反馈结果，以及 G1/G2/G3 门槛。以上继续按 [真机规程](../physical-device-protocol.md) 记录。
