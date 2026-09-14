# 续页 Longlet

iPhone 实时滚动长截图应用。用户主动开始系统屏幕捕捉，手动滚动，结束后预览、裁剪、遮盖隐私并保存 PNG/JPEG。正常路径直接处理屏幕帧，不要求导入完整录屏视频。

## 当前范围

- Swift 6 原生应用，最低 iOS 18；ReplayKit 广播上传扩展。
- 本地分片、原子会话清单、跨进程捕捉锁和中断恢复。
- 上下双向拼接、回滑去重、固定区域处理；不确定画面等待可信重叠，不跨未知缺口拼接。
- 可缩放分块预览、裁剪、拼缝微调、不透明遮挡、照片保存和系统分享。
- 中文及英文界面，支持邮箱 `chestnutlee23@163.com`。
- 测试版每周免费导出 50 个新作品，失败、取消与同一作品重复导出不扣次数；升级保留成功记录，正式商业政策后续再定。

模拟器演示使用明确标注的合成图片，不代表已完成跨应用录屏。真实设备、用户访谈、内测与发布状态见 [实施记录](docs/implementation-status.md)。

2026-09-14：**0.1.1（2）已开放 TestFlight 内部测试**，增加双向扩展、每周 50 次额度和采集恢复改进。测试组构建状态为“正在测试”，现有测试员可直接更新；本次没有公开加入链接。模拟器验证、构建标识与真机待测事项见 [本次发布记录](docs/release/0.1.1-testflight.md)。

## 开发

需要完整 Xcode 26 或更高版本以及 XcodeGen。脚本优先使用已选择的 Xcode，也会发现 `/Applications/Xcode.app`；不会修改全局 `xcode-select`。

```sh
./scripts/generate-project.sh
open ScrollCapture.xcodeproj
./scripts/check.sh
```

如仅运行纯 Swift 核心：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run -c release ScrollCaptureBenchmark --output .work/core-benchmark
```

合成基准逐像素校验独立生成的真值画布；结果是算法测试，不计作 G1 真机验收。

日常采用本地编译与关键测试 → 手动上传 TestFlight → 真机反馈修复的流程。云端 CI 仅保留 `workflow_dispatch` 手动触发，不随 push 或 PR 自动执行，也不作为日常测试版分发的前置条件；工作流进入默认分支后可按需从 GitHub Actions 手动运行。

## 模拟器

在 Xcode 选择 iPhone 模拟器运行 `ScrollCapture` scheme。启动参数 `--demo` 创建明确标注的示例作品；`--uitesting` 仅重置专用演示目录。

```sh
xcrun simctl list devices available
SIMULATOR_UDID=<专用模拟器ID> ./scripts/test-ios.sh -parallel-testing-enabled NO
```

## 真机与签名

复制 `Config/Signing.example.xcconfig` 为被 Git 忽略的 `Config/Signing.local.xcconfig`，填写自己的付费开发者团队。宿主与扩展必须共用 `APP_GROUP_IDENTIFIER`，默认 `group.dev.lzbaclz.longscreenshot`。不要复用其他产品的数据组，也不要提交证书、描述文件或私钥。

用 `ScrollCaptureDevice` scheme 构建主应用和 `FixtureReader` 测试页。测试页全部内容由项目生成，用于跨 App 验证；不用私人聊天或个人照片充当测试样本。

```sh
./scripts/archive.sh
```

归档不等于已上传、获批或发布。该脚本不会上传或发布应用。

## 文档

- [项目计划书 Markdown](docs/project-plan.md)
- [实施状态与证据](docs/implementation-status.md)
- [0.1.0（1）TestFlight 发布记录](docs/release/0.1.0-testflight.md)
- [0.1.1（2）修复与验收记录](docs/release/0.1.1-testflight.md)
- [算法说明](docs/algorithm.md)
- [品牌命名](docs/brand-naming.md)
- [图标原图与提示词](docs/design/longlet-icon-prompt.md)
- [隐私政策](docs/release/privacy-policy.md)
- [商店资料与审核说明](docs/release/app-store-package.md)
- [真机验证规程](docs/validation/physical-device-protocol.md)

目前的地区资料、真实参与者记录与 iOS 27 后端验收仍按各自门槛记录，不能由模拟器或合成基准替代。
