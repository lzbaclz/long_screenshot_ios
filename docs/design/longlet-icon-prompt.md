# 续页 / Longlet 图标生成记录

- 方式：内置 `image_gen`，原创新建图像，无参考图，无 CLI 回退。
- 原图：`longlet-icon-original-v1.png`。
- 实际输出尺寸：1254 × 1254 像素，RGB，不含透明通道。提示词要求 1024 × 1024，但生成工具返回了较大的正方形原图；集成资源时需作确定性尺寸规范化，并保留本原图。
- 视觉概念：深青色连续纸页，由一个柔和折面连接为向下延续的整体。浅雾白背景、海玻璃色翻面，没有文字、外框、系统图标或 Apple 标志。
- 检查：单一中心符号，画布不带外侧圆角蒙版，背景铺满四边。原图独立存放；已等比规范化为 1024 × 1024，并集成至 iOS/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png。分发 IPA 的 Assets.car 已核验 RGB/sRGB/Opaque=true。

## 完整提示词

```text
Use case: logo-brand.
Asset type: final production iOS app icon raster for an original long-screenshot app named Longlet / 续页; the name must NOT appear in the image.
Canvas: exactly 1024 x 1024 pixels, fully opaque square, edge-to-edge very light warm mist/ivory background. This is the flat icon artwork itself, not a mockup.
Primary request: create one original, beautiful, highly legible central symbol expressing continuous screen content becoming a single long page. Design a compact upright continuous paper ribbon, with one elegant connected fold joining two vertically offset page surfaces into one unmistakably continuous form. The silhouette should be simple and distinctive, with broad confident shapes that remain recognizable at a tiny app-icon size. The fold provides the only visual complexity; there are no text lines or UI details.
Style: exceptionally refined native iOS restraint, quiet premium utility, precise harmonious geometry, softly softened edges, subtle material depth and delicate occlusion just at the connection, near-orthographic frontal composition. Avoid a bulky toy-like 3D look. Keep the symbol visually centered with generous balanced negative space, occupying approximately 58% of the canvas width and 64% of its height.
Palette: deep petrol teal for the main continuous page and a closely related pale sea-glass teal for the small turned surface; airy warm ivory/mist background; subtle soft shadow, no bright neon and no loud glossy glare.
Constraints: one original connected-page symbol only; no letters, no words, no Apple logo, no phone, no screenshot, no UI mockup, no arrows, no badges, no camera glyph, no plus sign, no watermark, no external rounded-square tile, no surrounding frame/border, and do not round or mask the corners of the 1024-square canvas. Background must extend all the way to every edge. Deliver a single finished icon, never an icon sheet or presentation board.
```
