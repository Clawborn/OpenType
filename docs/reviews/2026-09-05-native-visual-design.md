# OpenType 原生视觉方向

用户确认：克制原生，接近 macOS 系统工具，黑白灰为主，少量蓝色。

## 实施

- 设置改为五个分类：通用、语音输入、智能服务、隐私与数据、关于。宽窗口显示分类导航和内容，窄窗口使用分类菜单，保留现有服务详情路由。
- 分类选择持久保存；从服务详情返回、切换页面和重启后都不会丢失位置。缺少模型的菜单提醒直接进入模型配置详情。
- 开关、分段选择恢复原生控件语义。没有修改设置值、权限或提供商配置。
- 页面 / 侧栏改为中性灰；侧栏选中使用浅蓝底和蓝图标，不再整行高饱和蓝。会话用户气泡按内容收缩，使用浅灰底深色字。
- Dock、侧栏、菜单和关于页面共用同一 AppIcon。
- 版本保持 2.1.2，构建号 43 区分本次视觉迭代与构建 42 的交互修复。

## 图标

内置 image_gen 工具生成，原始图保存在 `Resources/AppIconSource.png`，打包脚本为 `scripts/build-icon.sh`，输出为 `Resources/AppIcon.icns`。外部留存原图未删除。

生成 Prompt：

```text
Use case: logo-brand. Asset type: production macOS app icon for OpenType, a premium voice-to-text and personal assistant app. Create ONE square 1024x1024 image, not a presentation, no mockup, no labels. An exquisitely restrained native Mac icon: softly rounded square tile with an off-white porcelain surface, subtle realistic edge depth and faint cool silver shading, viewed perfectly straight-on. Large perfectly centered custom graphite black symbol combining an open O shape with a crisp vertical text caret: a thick continuous smooth open circular stroke, with its right opening resolved into a simple upright rounded bar. The negative space should feel open and immediately legible at 32px. One tiny understated cobalt blue accent at the caret lower terminal, otherwise monochrome. Sculptural but nearly flat, meticulous optical balance, generous padding, fine tactile material, no extravagant reflections. Tile occupies about 86 percent of canvas with actual transparent alpha outside rounded tile, extremely subtle natural shadow. No waveform, no microphone, no sparkle, no star, no letters spelling the app name, no Apple logo, no gradients of bright purple/blue, no metallic chrome, no complex 3D perspective. Deliver a single finished icon centered on transparent background.
```

实际输出为 1254 × 1254 透明 PNG；打包时只做 macOS 所需各分辨率采样，不改图形。
本轮不宣称完成全套深色外观；旧的固定浅色仍保留，后续须连同全部文字 / 状态颜色整体适配。

## 验证记录

- 最终完整 Swift 回归：1104 XCTest + 13 Swift Testing 均通过；sidecar 1378 项通过，release 构建成功。
- 安装为 `/Applications/OpenType.app`，2.1.2 (43)，最终主程序 UUID 与 release 产物一致，签名严格验证通过。
- 实际界面已观察到五个设置分类、原生开关 / 单选控件、完整语音输入设置和 Agent 工具详情入口；新图标在菜单 / 侧栏可见。发现详情返回丢失分类后改为 AppStorage 持久化。
- 用户同时操作界面，多次自动化操作被中断；最后一次分类往返、窄窗口拖动缩放与完整麦克风跨会话流程未完成端到端复测，不将代码 / 单元测试当作这些交互的实测。
- 停止旧版残留后台后，确认只剩一组新版 App / sidecar，`/health` 返回 `ok`。未清除任何历史、模型环境或提供商配置。
