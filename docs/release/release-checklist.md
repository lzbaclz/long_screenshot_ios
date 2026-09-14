# 续页 / Longlet 发布检查单

本文件是待执行检查单，不是发布通过声明。证据总入口为 [实施状态](../implementation-status.md)，门槛口径为 [G1/G2/G3 证据表](../validation/gates-and-evidence.md)。所有勾选附具体构建、执行日期与证据位置；文件存在或代码可编译不等于真机通过。

## 2026-09-14 内部 Beta 状态

用户已明确调整顺序，要求先模拟器调试、再通过 TestFlight 自行真机测试；本次分发不再由尚未完成的 G1 阻塞。Longlet 0.1.0（1）已上传处理完成，内部组 `Longlet Internal` 已分配 1 个构建并邀请用户本人，最终状态“正在测试 / 90 天后过期”；实际接受与安装尚未确认。[本次记录](0.1.0-testflight.md) 包含 IPA 指纹及本地 23 / 23、合成 120 / 120、iOS 模拟器 24 / 24、Photos 拒绝补充 1 / 1 的证据。

这次有限内部测试分发不等于下列正式发布条件已全部满足。G1/G2/G3、用户研究、正式商店资料和真实设备资源测试继续待完成。[最终 CI](https://github.com/lzbaclz/long_screenshot_ios/actions/runs/34792767736) 的 core、ios27-compile、ios 三项均已成功，下载的 xcresult 确认云端 iOS 模拟器 24 / 24 通过、0 失败、0 跳过。

## 一、代码与可复现构建

- [ ] 冻结候选 Git 提交、版本、构建号；记录 Xcode/SDK 与依赖解析版本。
- [ ] 在干净工作目录执行实际项目脚本，保存命令、退出码和完整日志；不以旧构建替代。
- [ ] 算法测试及批量合成样本通过；把合成结果放在独立类别，不计入真实成功率。
- [ ] 原生存储、渲染、购买额度及界面自动化通过；保存 `.xcresult` 和可复核截图。
- [ ] 广播扩展只处理视频帧；没有完整视频导入依赖、私有 API、隐藏系统指示或内容上传路径。
- [ ] 分块/清单原子写入、跨进程租约、失效恢复、起点变化提示、大图明确缩小选择均保留。
- [ ] 遮挡在缩放导出后仍覆盖目标像素；删除源图不会被错误描述为删除外部副本。
- [ ] 中文与英文界面、权限说明、错误提示和空状态检查完成；系统切换语言后不混入关键未翻译文字。
- [ ] 图标、商标使用与原创来源记录齐备；名称检索不宣称权利核准。

## 二、真实设备与用户证据

- [ ] G1 两组真实设备系统的 30 × 2 次用例完成，达到计划阈值，并完成后台/内存/恢复记录。
- [ ] G2 核心样本分母已冻结，P0 具备且完整成功率至少 90%，无可复现崩溃。
- [ ] G3 的 360 次核心与 120 次压力测试达到全部目标；旧系统和低内存机型未被模拟器替代。
- [ ] 至少 8 份真实访谈记录，其中至少 5 人提供近一月实际场景；没有把空白表当访谈完成。
- [ ] 20 名非项目成员完成同条件配对比较，保存全部失败及原始耗时；达到优势和继续使用门槛。
- [ ] 真实外部 App、独立测试页、模拟器演示分别记录；没有以合成 fixture 命名真实微信测试。
- [ ] 真机相册拒绝/恢复权限、系统中断、锁屏、App Group 签名、资源上限与大图耗时验证完成。
- [ ] StoreKit 沙盒的取消、待确认、验证失败、恢复、撤销和离线状态完成；测试不限次数不能代替正式额度验证。

## 三、现有开发者团队与商店配置

- [ ] 使用负责人已有付费团队，核验权限、会员状态、签名与 App Group；不另行购买账户或把证书写入仓库。
- [ ] App Store Connect 中的 bundle ID、版本和非消耗型 Pro 商品与工程一致。
- [ ] 付费协议、税务、收款资料及地区价格由实际账户状态确认；所有密码和密钥留在安全配置中。
- [ ] 测试/生产环境正确识别，测试版“无限导出”标签可见；正式版额度不因误判 sandbox 而永久开放。
- [ ] 保存 archive、导出记录与符号文件；上传、审核状态及下载链接只有实际成功后才填写。
- [ ] TestFlight 测试说明、支持邮箱与审核联系人已配置；没有未经授权发送邀请。

## 四、隐私及全球地区

- [ ] [隐私政策](privacy-policy.md) 已补全运营主体和生效日期，公开 HTTPS URL 可访问，应用内可找到。
- [ ] 支持页面公开可访问，包含 chestnutlee23@163.com；没有把 `mailto:` 当作支持网页地址。
- [ ] App Privacy 申报逐项对照最终二进制、依赖和实际网络行为；隐私清单的用途理由与实际调用一致。
- [ ] App Store 权限文案准确；只在保存时请求照片添加权限，不承诺从未收到系统音频样本。
- [ ] 最终全球可用地区保存为实际清单；“拟全球发行”与“已在所有地区上架”分开。
- [ ] EU DSA trader 状态依据实际业务填写；需要时提交真实联系方式和验证文件，不使用支持邮箱代替所有身份信息。[Apple DSA 要求](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements)
- [ ] 对中国大陆及其他存在额外要求的地区逐项核对资料；依 App Store Connect 提示处理适用的 ICP 等信息，不以“本地处理”直接判断免除。[Apple 应用资料说明](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- [ ] 年龄分级、内容权利、加密/出口合规问卷按当前应用实际能力填写，没有凭空填证书或备案号。

本次内部 Beta 已保存[公开隐私政策 URL](https://github.com/lzbaclz/long_screenshot_ios/blob/feat/scroll-capture-mvp/docs/release/privacy-policy.md)。这项配置不代表正式 App Privacy、主体、地区和所有商店资料均已完成。Apple 要求 iOS 应用提供公开隐私政策并准确更新数据处理说明。[App Store Connect 隐私管理](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)

## 五、发布决定与上线后记录

| 字段 | 待填写 |
| --- | --- |
| 候选版本 / Git 提交 / archive 指纹 | — |
| G1、G2、G3 审核记录链接 | — |
| 未关闭问题及影响范围 | — |
| 实际可用地区与排除原因 | — |
| 发布时间方式与回退构建 | — |
| 审核人 / 发布负责人 / 决定日期 | — |
| 结论：继续验证 / 限定范围 / 准予提交 | **已按用户授权完成 0.1.0（1）内部 TestFlight 分发；正式商店提交仍待决定** |

上线后按计划记录有效使用、14 日复用、购买、退款与支持工时。当前代码没有自动上传这些使用事件；可使用自愿反馈及 Apple 实际提供的报表，说明各数据来源与覆盖范围。若以后增加分析 SDK，必须作为新变更单独设计告知、选择、申报与验证。

## 隐私声明依据

本文依据 `iOS/BroadcastExtension/SampleHandler.swift`、`iOS/Shared/`、`PurchaseStore.swift`、`PlatformViews.swift` 和 `Config/PrivacyInfo.xcprivacy`。最终提交时重新检查依赖与网络行为，不能仅凭当前隐私清单的空收集列表判定申报正确。

App Store 隐私标签的候选答案是“不收集数据”：当前截图与额度在设备上处理，没有开发者后台。仍须逐项评估最终应用、第三方组件和实际反馈流程。Apple 对设备外收集的定义见 [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)；所有应用都需要公开隐私政策 URL，见 [App Store Connect 隐私资料](https://developer.apple.com/help/app-store-connect/reference/app-privacy/)。本次已配置公开 URL，正式隐私申报仍需按最终候选核对。
