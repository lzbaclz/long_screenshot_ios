# 续页 / Longlet 商店与测试分发资料

状态：可编辑草案，未创建商店记录、上传构建或发送邀请。发布主体使用项目负责人已有的付费 Apple Developer 团队；本文不保存团队凭据。支持邮箱：**chestnutlee23@163.com**。目标为全球发行，实际地区以最终可用性及资料完成情况为准。

## 商店字段

| 字段 | 简体中文 | English |
| --- | --- | --- |
| 名称 | 续页 - 滚动长截图 | Longlet - Long Screenshots |
| 副标题 | 手动滚动，连成一张长图 | Scroll, stitch, keep |
| 建议分类 | 工具 | Utilities |
| 宣传文本 | 从想保留的起点开始滚动，把连续内容留成一张长图。支持裁剪、遮挡、PNG 和 JPEG 导出，图片在本机处理。 | Turn scrolling content into a long image. Crop, redact, and export as PNG or JPEG, with image processing on your iPhone. |
| 关键词草案 | 滚动截图,长图,拼接,截屏,聊天记录,网页,图片编辑,隐私遮挡 | scrolling,capture,stitch,chat,webpage,redact,crop,vertical,screen |
| 支持邮箱 | chestnutlee23@163.com | chestnutlee23@163.com |
| 支持 URL | 待部署的公开 HTTPS 支持页面，不能填邮箱或本地路径 | Public HTTPS support page: pending |
| 隐私政策 URL | 见本目录政策草案，公开 URL 待部署 | Public policy URL: pending |
| 版权 | 待填写实际权利人及年份 | Actual rights holder and year: pending |

名称与副标题均按 30 字符上限编写，最终由 App Store Connect 校验；名称研究不等于名称已保留或商标已核准。规则依据：[App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)。

## 中文介绍草案

续页把连续滚动的内容整理成一张长图。通过 iOS 系统开始屏幕广播后，切到目标内容，在起点稍作停留，再缓慢向下滑动。结束后返回续页，检查、编辑并保存结果。

- 直接处理屏幕画面，无需先从相册选择完整录屏视频。
- 手动停止，或选择停止滑动 5 秒、10 秒后结束。
- 调整顶部、底部忽略区域，适应固定导航栏。
- 裁剪起止内容，修正重复接缝，用不透明遮挡保护隐私。
- PNG 与 JPEG 导出，保存至照片或通过系统分享。
- 图片在 iPhone 上处理，无需注册开发者账号，没有广告。

捕捉需要系统授权并保留系统指示。请从需要保留的起点开始，平稳滚动；快速跳动、动态页面或受保护内容可能无法完整衔接。应用会保留已确认部分，并说明无法继续的情况。起点重新定位时，请检查开头是否完整。

单次最长 2 分钟，可设置最多 5、10 或 20 个有效可视区域。20 屏不等于所有设备都能导出同尺寸原图；超过单图安全尺寸时，你可以裁剪，或明确选择缩小后导出。Pro 与免费版遵守相同资源上限。

免费版本每周可成功导出 3 个新捕捉，同一作品重复导出只计一次。Pro 是一次性购买，解除次数限制，价格以 App Store 购买界面显示为准。正式收费仅在商品配置及购买回归完成后启用。

## English description draft

Longlet turns scrolling content into one long image. Start a screen broadcast using iOS, switch to your content, pause at the point you want to keep, then scroll down slowly. Return to Longlet to review, edit and save the result.

- Process screen frames directly, without selecting a complete recording from your photo library.
- Stop manually, or after 5 or 10 seconds without scrolling.
- Exclude fixed areas at the top and bottom of the screen.
- Crop content, trim repeated seams and apply solid privacy redactions.
- Export PNG or JPEG, save to Photos, or use the system share sheet.
- Process images on your iPhone, without a developer account or advertising.

Capture requires iOS consent and keeps system indicators visible. Scroll steadily from your intended starting point. Fast jumps, changing pages and protected content may prevent complete stitching. Accepted content is retained when capture cannot continue. If the starting point was reset, check that the beginning is complete.

Each capture is limited to two minutes and a selected maximum of 5, 10 or 20 effective screen areas. Very large images may require cropping or your explicit choice to export a smaller image. Pro uses the same device safety limits.

The free version allows three successfully exported new captures per week; exporting the same capture again does not consume another allowance. Pro is a one-time purchase that removes the count limit. Its price is shown in Apple’s purchase interface. Sales begin only after the product and purchase flows are configured and tested.

## 审核说明 / App Review notes

提交前把构建号、已验证系统及公共测试内容 URL 填入以下说明；不把独立 FixtureReader 开发工具作为审核员必须安装的前提。应用不需要登录账号。

```text
Longlet creates long screenshots by processing ReplayKit video frames on-device.
It uses the public system broadcast picker and a Broadcast Upload Extension.
It does not record audio, upload captured content, hide the system indicator,
or require users to import a complete recording.

Build: [fill in]
Verified physical devices and iOS versions: [fill in actual evidence]
Public, non-private test article URL: [fill in and verify before submission]

1. Open Longlet and review the capture guide. In Settings, select manual stop.
2. Open a long public article in Safari and return to its intended starting point.
3. From Control Center, press and hold Screen Recording, choose Longlet,
   and start the broadcast. Dismiss Control Center and pause on the starting view.
   Alternatively, start from Longlet's system picker, then switch to Safari.
4. Scroll down slowly for several overlapping screens.
5. Stop using the iOS capture indicator or Control Center. Return to Longlet.
6. Open the result, check the first and last paragraphs, and test crop/redaction.
7. Export PNG to Photos (add-only permission) or use the system share sheet.

The extension holds a provisional starting frame until downward scrolling
is confidently matched. A changed provisional start is disclosed in the result.
Stopping without confirmed scrolling produces an explanatory empty draft.
Automatic stopping may show an iOS broadcast-ended notice even when a result exists.
If protected or dynamically changing content cannot be matched, the app preserves
the accepted section and explains the interruption.

Purchases: Pro is a StoreKit non-consumable. Restore Purchases is on the upgrade page.
Debug and TestFlight sandbox builds enable unlimited test exports, visibly labelled;
this is testing behavior, not a hidden paid unlock. Production free allowance is
three new successfully exported captures per week. In-app purchase sandbox paths
are tested separately; see the attached verified purchase test evidence.

Support: chestnutlee23@163.com
```

不要向审核员声称“任意 App 保证成功”“系统原生长截图替代”“完全不使用屏幕捕捉”“20 屏均可无损导出”或已通过尚未完成的真机门槛。系统捕捉需要明确同意与指示，商店截图应展示真实使用界面。[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

## TestFlight：What to Test

**中文：** 请使用无私人信息的测试内容，分别从控制中心和应用内开始捕捉。停留在起点后慢速滚动，检查首尾、接缝和短距离回滑是否完整。再测试固定栏、手动/静止结束、照片权限拒绝、裁剪与遮挡、PNG/JPEG、分享取消及中断恢复。测试版不限导出次数；大图安全上限仍生效。反馈请注明版本、机型、系统、启动入口、重现步骤与结果，不发送私人聊天原图。本轮不把演示图、合成样本或一次成功当作全部场景验收。

**English:** Use test content without private information. Try starting from both Control Center and the in-app picker. Pause at the starting point, scroll slowly, and check the beginning, ending, seams and short backtracking. Test fixed headers, manual/idle stopping, denied Photos permission, cropping, redactions, PNG/JPEG, cancelled sharing and interruption recovery. Test builds have unlimited export counts; image safety limits remain. Include the build, device, iOS version, entry point, steps and result in feedback. Do not send unredacted private chats. Demo images and synthetic tests do not validate capture in other apps.

## 截图素材单与未完成项

需要同一候选构建的真实中文及英文屏幕：起始引导、真实捕捉结果、清晰放大查看、裁剪与遮挡、导出选择。示例内容必须标明演示，不能伪装成微信等真实跨应用捕捉。原始图标位于 `docs/design/`；正式 1024 图标及本地化资源由工程集成记录确认。

未完成项：公开政策/支持 URL、销售商与版权信息、最终价格和非消耗型商品配置、年龄分级问卷、审核测试内容 URL、各尺寸截图、全球地区配置及地区资料。所有字段必须由实际账户与候选版本填入，不使用占位内容提交。
