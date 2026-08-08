# OpenType for iOS

这是 OpenType 的原生 iOS MVP，最低支持 iOS 17。工程包含两个产品 target 和一个测试 target：

- `OpenTypeiOS`：SwiftUI 宿主 App，负责录音、Apple Speech 实时识别、五种模式、云端文字处理、Keychain、历史、复制和设置。
- `OpenTypeKeyboard`：自定义键盘扩展，从 App Group 读取最近一次成功结果，并通过 `textDocumentProxy.insertText` 插入当前输入框。
- `OpenTypeiOSTests`：覆盖共享验收向量与本地安全不变量的 XCTest target。

## 正确的 iOS 使用流程

iOS 不允许第三方键盘扩展访问麦克风，即使用户开启“允许完全访问”也不例外。因此 OpenType 没有在键盘里伪装录音能力：

1. 在 OpenType App 中选择模式并说话。
2. Apple Speech 显示实时字幕；停止后，本地转写或云端模型生成结果。
3. 每个成功结果都会写入系统剪贴板，并同步到本机 App Group。
4. 回到微信、X、备忘录等目标 App，切换到 OpenType 键盘。
5. 点击“插入最近结果”。

密码框、电话号码字段，以及主动禁用第三方键盘的 App 可能拒绝 OpenType 键盘。这些场景直接使用系统粘贴。

App Group 共享需要为键盘开启“允许完全访问”。扩展本身不持有 Token；共享容器只保存最近结果、结果时间与 UI 语言。

## 功能

- Apple Speech 实时字幕，优先请求设备端识别；设备或语言不支持时由系统回退。
- 识别语言：中文/中英混合、English、日本語。
- 五个与共享规范一致的 mode id：
  - `smartEdit`：无上下文时整理口述；有原文时必须明确说出修改指令，否则取消且不调用模型。
  - `english`：中文或混合口述改写成自然英文；DashScope 使用 Qwen-MT 专用翻译请求，原话不会被当作指令。
  - `agent`：只生成轻量文字任务的成品草稿，绝不自动发送或发布。
  - `xReply`：结合原帖和可选观点，生成一条自然回复草稿。
  - `transcribe`：完全本地的轻转写路径，不调用文字模型，短问题不会被回答。
- 阿里云百炼、豆包/火山方舟、OpenAI、Claude，以及自定义 OpenAI-compatible endpoint。
- Token 按供应商保存到 iOS Keychain，界面不回显已存值。
- 所有成功结果自动复制，并写入 App Group 供键盘插入。
- 原始转写、模式、上下文、结果、时间、状态、Provider 和模型以共享 schema 的 append-only JSONL 事件保存在本机 `Application Support/OpenType/audit-events.jsonl`；每次任务分别追加 `recognized` 与最终状态，历史 UI 按 `requestId` 聚合并只加载最近 500 条，但日志不裁剪、不覆写。原始音频不落盘。
- 中文/英文 UI。

## 打开与运行

```bash
open Platforms/iOS/OpenTypeiOS.xcodeproj
```

在 Xcode 中：

1. 为 `OpenTypeiOS` 和 `OpenTypeKeyboard` 两个 target 选择同一个 Development Team。
2. 在两个 target 的 Signing & Capabilities 中确认 App Groups 包含 `group.ai.opentype.shared`。
3. 如果该 App Group 标识在你的开发者账号中不可用，创建自己的唯一标识，并同时替换：
   - 两个 `.entitlements` 文件；
   - `OpenTypeiOS/SharedResultStore.swift`；
   - `OpenTypeKeyboard/KeyboardViewController.swift`。
4. 选择真机运行 `OpenTypeiOS`。真机才能完整验证麦克风、Speech、Keychain、App Group 与键盘扩展。
5. iPhone 中打开“设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → OpenType”，然后开启“允许完全访问”。

在 App 的“设置”页保存云端文字模型 Token。`transcribe` 模式无需 Token。

## 无签名编译验证

```bash
xcodebuild \
  -project Platforms/iOS/OpenTypeiOS.xcodeproj \
  -scheme OpenTypeiOS \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/OpenTypeiOSDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

编译测试 target：

```bash
xcodebuild \
  -project Platforms/iOS/OpenTypeiOS.xcodeproj \
  -scheme OpenTypeiOS \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/OpenTypeiOSTestDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
```

`OpenTypeiOSTests` 新增了 DashScope 中转英专用请求合同检查：只发送一条原文 user message，并显式设置 `source_lang=auto` 与 `target_lang=English`，不附带 system message。测试代码与宿主 App 已完成编译与链接检查；当前机器的 Simulator 包验证受 runtime 环境限制，因此本轮不把完整 XCTest 套件表述为已运行或真机通过。

## 云端接口

- DashScope：`https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions`；普通文字模式默认 `qwen-plus`，中转英固定使用 `qwen-mt-flash`
- Volcengine：`https://ark.cn-beijing.volces.com/api/v3/chat/completions`，默认 `doubao-seed-2-0-lite-260215`
- OpenAI：`https://api.openai.com/v1/chat/completions`，默认 `gpt-5-mini`
- Anthropic：`https://api.anthropic.com/v1/messages`，默认 `claude-sonnet-5`，使用原生 Messages 协议
- OpenAI Compatible：填写完整的 `/chat/completions` URL 与模型名

只有文字整理会请求所选服务。Apple Speech 负责当前 iOS MVP 的语音识别；音频不会发送给上述文字接口。ElevenLabs、DashScope 和 OpenAI 云端 ASR 尚未接入移动端首版。

## 当前边界

- iOS 无法像 macOS Accessibility 那样读取其他 App 的选中文字；原帖或待修改原文需要复制到宿主 App 的上下文框。
- 键盘扩展只能插入最近结果，不能录音、调用模型或读取 Token。
- 当前版本没有跨设备同步，也不会自动发送消息、发布 X 或执行外部动作。
