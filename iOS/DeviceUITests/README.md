# 真机跨应用捕捉验证

测试只打开续页和项目内的 `FixtureReader`，不访问微信、照片图库或其他私人应用。模拟器会跳过本套测试；模拟器示例和安装成功均不能替代真机捕捉验收。

## 运行

1. 在 `Config/Signing.local.xcconfig` 配置已授权的开发团队。
2. 连接并解锁 iPhone，测试期间保持亮屏。遇到 XCTest 网络连接失败时，优先通过 USB 连接再排查。
3. 执行 `scripts/test-device.sh`。脚本从本机 `.work/implementation/device-info.json` 读取设备标识；也可显式设置 `DEVICE_UDID`。不会将标识或签名资料写入源码。

脚本复用 `.work/DeviceUITestDerivedData`，结果保存在 `.work/device-test-results/`。

## 通过依据

- 真实点击系统广播按钮，再切换到合成测试页。
- 进行 7 次保留重叠区域的缓慢向下拖动。
- 停留在合成页面，等待配置的 5 秒静止停止。
- 返回续页后，出现此前不存在的会话 UUID。
- 打开的是实际捕捉结果，而不是示例；预览可见，编辑器能识别至少两段图像分块。
- 测试保存系统选择器、源页面、结果图及会话标识附件，便于进一步核对编号连续性。

如果测试失败，清理流程仅尝试停止本次请求的广播，不删除旧会话。已在进行中的捕捉会使测试跳过，避免干扰原有工作。

## 2026-09-14 执行记录

已完成真机测试目标的编译、签名和 Runner 启动尝试。最初的锁屏阻点由用户解锁后解除；随后两次尝试均在测试方法开始前失败：

```text
Connection peer refused channel request for
dtxproxy:XCTestDriverInterface:XCTestManager_IDEInterface
Exiting due to IDE disconnection.
The test runner exited with code 74 before establishing connection.
```

延后 `XCUIApplication` 初始化至 `setUp` 后仍可复现。此时没有启动广播，也没有生成本轮真实长图，**真机捕捉验收尚未通过**。

当时环境为 Xcode 26.3、iOS 27 测试版，设备通过局域网连接。测试通道或版本配对问题仍是待验证因素，不能仅据上述错误断言产品崩溃或必须升级系统。Apple 的 [Xcode 系统要求表](https://developer.apple.com/xcode/system-requirements) 列出了对应 SDK 与系统要求。

本机诊断保存在 `.work/implementation/device-ui-smoke-unlocked.log`、`.work/implementation/device-ui-smoke-lazy-driver.log` 和 `.work/device-test-results/diagnostics-001213/`，不应提交到版本库。
