# OpenType 多端架构

本文档定义 macOS、iOS 与 Android 三端必须保持一致的产品行为，以及必须尊重的平台边界。机器可读的规范位于 `Shared/OpenTypeContract.json`，请求、响应与追加式审计事件定义在 `Shared/Schemas`。

## 共同产品内核

三端共享同一条处理链：获取上下文 → 语音识别 → 模式路由 → 文字处理 → 输出校验 → 本地留痕 → 交付结果。

五个用户模式保持一致：

1. 智能编辑：无选区时整理口述；有选区时必须听到明确修改指令才处理。
2. 中转英：理解中文或中英混合表达，生成自然英文，而不是逐字翻译。
3. Agent：完成几百字以内的轻量文字任务，并可参考近期任务。
4. X Reply：结合原帖与可选观点，生成一条像真人参与讨论的回复。
5. 文字转写：只做保真轻整理，永远不能把口述中的问题当成要回答的问题。

每次成功结果必须保留在剪贴板。Agent 与 X Reply 只生成草稿，任何平台都不得自动发布或自动发送。原始音频仅作本次识别，处理完成后删除；原始转写与最终结果留在本机，便于追溯。

## macOS

macOS 继续采用原生 SwiftUI 菜单栏应用：全局快捷键负责开始和结束录音，辅助功能负责读取选区及向当前输入框写入，剪贴板始终作为兜底。

这是能力最完整的桌面版本，也是 Prompt、模式行为与输出安全规则的基准实现。

## iOS

iOS 必须由两个 target 组成：

- 宿主 App：请求麦克风和语音识别权限，完成录音、实时字幕、模式处理、历史、Token 与设置。
- 自定义键盘扩展：读取 App Group 中最近一次生成结果，通过 `textDocumentProxy.insertText` 写入当前输入框。

Apple 明确规定自定义键盘扩展不能访问麦克风，即使用户开启“允许完全访问”也不例外。因此 iOS 的可信流程是：在 OpenType App 内说话并生成 → 回到目标 App → 在 OpenType 键盘中一键插入。不能在键盘 UI 中假装提供实际不可用的直接录音。

第三方键盘也可能被密码框、电话键盘或主动禁用第三方键盘的 App 拒绝；这些场景使用系统剪贴板回退。

参考：

- <https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard>
- <https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard>

## Android

Android 由宿主设置 App 与 `InputMethodService` 组成。IME 可以通过 `SpeechRecognizer` 获取实时与最终转写，并用 `InputConnection.commitText` 把处理结果直接写入当前输入框。

用户在系统设置中启用 OpenType 输入法后，可以在任意允许第三方 IME 的文本框内按住说话、松开处理。IME 必须提供切换到下一个输入法的入口；密码字段完全禁用 OpenType 语音、上下文读取和历史保存。每个输入目标使用独立 session，切换输入框或结束输入必须取消旧请求，并在 `commitText` 前再次校验 session，防止异步结果串到新的输入框。

参考：

- <https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method>
- <https://developer.android.com/reference/android/speech/SpeechRecognizer>

## 安全存储

- macOS：本地 AES-GCM Provider Vault，密钥与密文均不进入项目或日志。
- iOS：Keychain；宿主 App 与键盘共享的只应是生成结果和非敏感偏好，Token 不写入 App Group 明文。
- Android：Android Keystore 支持的加密存储；不得把 Token 写进普通 SharedPreferences、构建配置或日志。

## 版本验收

每个版本发布前都需要验证：权限首次流程、短问题不会被转写模式回答、所有结果可复制、网络失败不丢结果、Agent/X Reply 不自动发送、Token 重启后可用且不回显、中文与英文 UI、五种模式的最小端到端路径。
