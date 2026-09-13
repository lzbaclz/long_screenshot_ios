# 续页 / Longlet 隐私政策

生效日期：2026年9月14日。适用：续页 / Longlet 0.1.0。服务提供者：Ziqing Li（子卿 李），与当前 App Store Connect 开发者账号一致。支持邮箱：**chestnutlee23@163.com**。

## 中文

### 谁提供这款应用

续页（Longlet）是一款在 iPhone 上制作长截图的应用。服务提供者为 Ziqing Li（子卿 李），即 App Store 销售商信息所列开发者。隐私与支持请求可发送至 chestnutlee23@163.com。

### 屏幕内容如何处理

只有你通过 iOS 系统界面开始屏幕广播后，应用扩展才会接收系统提供的屏幕画面。你控制滚动与结束，iOS 的捕捉授权和指示保持可见。系统可能把画面中的通知及其他可见内容一并提供给扩展，请在分享前检查结果。

当前版本在设备上分析画面、匹配重叠区域，并把已确认的画面分块和会话记录保存在应用及其扩展共用的本机存储空间。应用不把截图内容上传到开发者服务器，不创建供用户导入的完整录屏视频，也不使用云端图像识别服务。收到的音频和麦克风样本会被忽略；功能不依赖麦克风权限。

### 保存在设备上的信息

- 原始图片分块、生成的导出文件，以及图片尺寸、创建时间、捕捉状态和失败说明。
- 裁剪、接缝调整和遮挡矩形等编辑记录，以及停止方式、长度和固定栏设置。
- 本机导出记录的随机会话标识与日期，用于免费额度计算和避免同一作品重复计数。
- 通过 Apple StoreKit 核验的购买权限状态，用于解锁及恢复 Pro 功能。

当前版本不要求建立开发者账号，没有广告或第三方行为分析 SDK，也不进行跨应用广告跟踪。应用不需要读取照片图库、通讯录、位置或摄像头。

### 导出、遮挡与删除

只有你主动保存时，应用才请求向照片图库**添加图片**的权限。拒绝权限不会授权读取你的图库；你仍可使用系统分享界面。分享给哪个应用、联系人或存储位置由你选择，接收方会按照自身规则处理副本。

**导出的遮挡会写入图片像素；应用内原始画面仍被保留，以便重新编辑。** 如果你希望移除本应用保留的未遮挡原图，请在检查导出结果后删除对应作品。删除作品会删除本应用存储的该作品及其内部导出文件，但不会删除已保存至“照片”、文件位置或其他应用的副本。

当前版本没有定时自动清理、所有缓存一键清理或远程删除功能。捕捉中断时会尽力保留已写入部分。尚未完成的临时文件或损坏记录可能留在本机；不会因为一次读取失败就自动删除原始内容。仅移除主屏幕图标或卸载但保留文稿的数据操作，不等于删除内容；系统管理的应用数据清理由 iOS 设置控制。

截图存储目录被设置为不参加系统备份，文件使用 iOS 数据保护。应用不提供自己的云同步；你导出的副本仍可能由照片、文件服务或备份设置同步。请按相应服务的设置管理这些副本。

### Apple 购买、系统服务与支持邮件

Pro 购买和恢复由 Apple StoreKit 与 App Store 处理。开发者不接收你的完整付款卡信息，也没有自行运营的支付服务器。Apple 会按其服务规则处理购买、下载、诊断以及你选择发送的 TestFlight 反馈；参见 [Apple 隐私政策](https://www.apple.com/legal/privacy/)。

如果你主动发邮件求助，我们会收到你的邮箱地址、邮件正文和你自行附加的内容，并用它们处理该请求。邮件通过邮箱服务处理，不是应用自动上传。请只提供排查所需信息，避免附带未经遮挡的私人聊天。支持邮件的保留以解决请求及履行适用义务所需为限；可通过上述邮箱提出查阅或删除请求。我们无法替你删除已经发送给其他接收方的副本。

### 你的选择与政策变更

你可以不启动捕捉、随时通过系统停止广播、拒绝照片添加权限、删除应用内作品，并通过 iOS 设置管理权限。我们无法远程读取或恢复只在你设备上的截图。如果后续版本加入云同步或分析服务，将更新本政策及相应选择，不以本政策为尚未实现功能预先取得授权。

## English

### Who provides Longlet

Longlet, named 续页 in Simplified Chinese, is an iPhone app for creating long screenshots. The provider is Ziqing Li, identified as the seller on its App Store page. Effective date: September 14, 2026. Contact: **chestnutlee23@163.com**.

### Screen processing

The app extension receives screen images only after you start a broadcast through the iOS system interface. You control scrolling and stopping. System consent and capture indicators remain visible. Notifications and other visible information may appear in the frames supplied by iOS, so review your result before sharing.

The current version matches overlapping content on your device and saves accepted image strips and session records in local storage shared by the app and its extension. It does not upload screenshot content to a developer server, create a complete recording for you to import, or use a cloud image-recognition service. Audio and microphone samples are ignored; the feature does not require microphone access.

### Information stored locally

Local information includes original image strips, exported files, dimensions, timestamps, capture status and error descriptions; crop, seam and redaction edits; capture preferences; and random session identifiers and export dates used to apply the free allowance without counting the same capture twice. The app also checks Apple StoreKit purchase entitlements to unlock or restore Pro.

The current app has no developer account sign-in, advertising or third-party behavioral analytics SDK, and does not perform cross-app advertising tracking. It does not need to read your photo library, contacts, location or camera.

### Exporting, redacting and deleting

The app requests permission to **add images** to Photos only when you choose to save. Denying that permission does not give the app permission to read your library. You can use the system share sheet and choose the recipient or destination; recipients handle exported copies under their own rules.

**Redactions are baked into exported image pixels. Original unredacted strips remain inside the app so you can edit again.** To remove those originals, review your export and then delete the capture. Deleting a capture removes its local source and internal export files, but does not delete copies already saved to Photos, Files or another app.

The current version has no timed automatic cleanup, clear-all-cache command or remote deletion service. Completed strips are retained when capture is interrupted. Temporary files or damaged records may remain on the device; a read failure does not automatically delete source content. Removing a Home Screen icon or offloading an app while retaining its documents does not remove its data. iOS Settings controls system-managed application data removal.

Capture storage is marked as excluded from system backups and uses iOS data protection. The app does not provide its own cloud synchronization. Exported copies may still be synchronized by Photos, a file service or your backup settings; manage those copies through the relevant service.

### Apple services and support

Apple StoreKit and the App Store process Pro purchases and restoration. The developer does not receive complete payment-card details or operate a separate payment server. Apple handles purchases, downloads, diagnostics and feedback you choose to send through TestFlight under its own policies. See [Apple’s Privacy Policy](https://www.apple.com/legal/privacy/).

If you email support, we receive your email address, message and attachments and use them to address your request. This is handled through the email service, not automatically uploaded by the app. Send only information needed to investigate, and avoid attaching unredacted private conversations. Support correspondence is retained as needed to resolve the request and meet applicable obligations; you may request access or deletion using the contact above. We cannot delete copies you have sent to other recipients.

### Your choices and changes

You may choose not to start capture, stop broadcasting through iOS, deny Photos permission, delete captures and manage permissions in iOS Settings. We cannot remotely access or recover screenshots stored only on your device. If a future version adds cloud services or analytics, its policy and choices will be updated; this policy does not authorize features that do not exist today.

## 发布前内部核对

本文依据 `iOS/BroadcastExtension/SampleHandler.swift`、`iOS/Shared/`、`PurchaseStore.swift`、`PlatformViews.swift` 和 `Config/PrivacyInfo.xcprivacy`。最终提交时重新检查依赖与网络行为，不能仅凭当前隐私清单的空收集列表判定申报正确。

App Store 隐私标签的候选答案是“不收集数据”：当前截图与额度在设备上处理，没有开发者后台。仍须逐项评估最终应用、第三方组件和实际反馈流程。Apple 对设备外收集的定义见 [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)；所有应用都需要公开隐私政策 URL，见 [App Store Connect 隐私资料](https://developer.apple.com/help/app-store-connect/reference/app-privacy/)。本 Markdown 尚不能代替公开 URL。
