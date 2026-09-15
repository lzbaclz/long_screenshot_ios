# 续页官网公开 TestFlight 内测

日期：2026-09-15。用户明确要求参考极拼官网，创建面向大众的 TestFlight 邀请并提供官网入口和二维码。

## Apple 后台配置

- App：续页 / Longlet，App ID `6811703874`。
- 外部测试组：`续页官网公开内测`。
- 组 ID：`75b5d45c-55f2-4eb5-9291-c7833848fd2c`。
- 测试构建：最新 `0.1.5（6）`，Apple 构建 ID `d0ac0cd5-a60b-4357-a884-e34b2276f16a`。
- 该构建已提交首次外部 Beta 审核，组内状态为“正在等待审核”。已保留中英文测试说明并勾选“自动通知测试员”。
- 审核联系人沿用用户此前提供的信息，不在公开仓库记录私人电话号码。
- 公共链接选择“向所有人开放”，不增加额外设备筛选或自定义人数上限；仍受 Apple TestFlight 的平台限制。
- 原内部测试组与 App Store 正式审核未改动。

## 邀请与官网

- [Apple 生成的公开邀请链接](https://testflight.apple.com/join/Qb5CcCep)
- [官网安装与内测入口](https://lzbaclz.github.io/long_screenshot_iphone/#get)
- [邀请二维码 PNG](https://lzbaclz.github.io/long_screenshot_iphone/assets/testflight-qr.png)

官网使用 App Store 与 TestFlight 双栏，分别说明正式版未上架和外测等待 Beta 审核。提供二维码、前往 TestFlight、复制链接、保存二维码及安装步骤。未把尚未开放的测试说成已可下载，也未为正式版生成误导性下载二维码。

## 实际验证与边界

Apple 后台明确提示：在此群组有获得批准的构建版本前，测试员无法加入公共链接。公开邀请页面实测显示“此 Beta 版本目前不接受任何新测试员”。所以本轮完成的是公开组、审核提交和邀请配置，尚不能证明大众已能接受邀请并安装；需等待 Apple Beta 审核。

二维码在本机使用 Core Image 按真实邀请地址生成，468×468 PNG，含留白；使用 Vision 独立解码确认内容完全等于公开邀请地址。没有外部二维码服务、额外个人标识或自建短网址。网页复制按钮验证成功，桌面与手机布局、图片加载和链接检查通过。

网站继续依附原 GitHub 仓库，由 `codex/app-store-pages` 分支发布。每次提供新外测构建时仍需按 Apple 要求关联或审核；“自动通知”不等于自动上传新版本。参与者可自行在 TestFlight 中开启自动更新。
