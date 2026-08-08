# OpenType

OpenType 是一个本地优先的跨平台 AI 语音输入工具，把自然口语变成可以直接使用的文字。macOS、iOS 与 Android 共享同一套模式、Prompt 安全规则、Provider 语义和审计协议，并针对各系统采用真实可用的输入机制。

macOS 的完整使用情景、操作方式和功能边界见 [OpenType 使用说明书](USER_GUIDE.md)。

## 三端工程

| 平台 | 主要交付方式 | 当前验证 | 工程与说明 |
| --- | --- | --- | --- |
| macOS | 全局快捷键录音，Accessibility 写入当前输入框，剪贴板兜底 | 91 项常规测试通过；真实 DashScope 中转英集成测试通过；production app 已构建并通过签名校验 | `Sources/OpenType`、[macOS 使用说明](USER_GUIDE.md) |
| iOS | 宿主 App 录音处理，通过 App Group 同步；Keyboard Extension 一键插入最近结果 | 中转英专用请求源码已编译与链接；当前 Simulator 包验证受本机 runtime 限制 | `Platforms/iOS`、[iOS README](Platforms/iOS/README.md) |
| Android | `InputMethodService` 内按住说话，`SpeechRecognizer` 转写，`InputConnection.commitText` 写入 | 中转英专用请求与回归用例已写入；本轮机器缺少 Java Runtime，未执行 JVM 测试 | `Platforms/Android`、[Android README](Platforms/Android/README.md) |

机器可读的模式和 Provider 规范位于 [共享产品契约](Shared/OpenTypeContract.json)，跨端验收向量位于 [Acceptance Cases](Shared/AcceptanceCases.json)，平台边界见 [多端架构](docs/MULTIPLATFORM_ARCHITECTURE.md)。

iOS 的自定义键盘受 Apple 系统限制，不能直接访问麦克风，因此录音必须在宿主 App 内完成；Android IME 可以直接录音与写入。两个移动端都不会自动发送或发布内容。

## 当前交付状态（2026-08-08）

- macOS：本机运行版本为 `dist/OpenType.app` v0.14.4 build 35；上一份便携归档为 `dist/OpenType-macOS-arm64-v0.14.3-build34.zip`。当前是 ad-hoc 本地签名版本，不是 Developer ID 公证发行包。
- iOS：宿主 App、Keyboard Extension 和测试 target 均已完成无签名编译，源码包为 `dist/OpenType-iOS-source-v0.1.0.zip`。安装到真机前仍需选择用户自己的 Apple Development Team，并注册两个 target 共用的 App Group；当前没有可分发 IPA。
- Android：完整源码包为 `dist/OpenType-Android-source-v0.1.0.zip`，可安装的本地验收包为 `dist/OpenType-Android-debug-v0.1.0.apk`。22 项 JVM 单元测试、Debug 构建、Android Lint、APK v2 Debug 签名和压缩完整性均已通过；它仍不是 Play Store 正式签名包，也尚未完成目标手机上的 IME、麦克风、Keystore 与 Provider 联调。

## macOS 当前功能

- 默认快捷键：左 `Option` 长按说话、松开完成；双击开始连续录音，再按任意普通键结束。右 `Option` 保持空闲
- 原生菜单栏入口：始终显示状态图标；再次打开 OpenType 会直接展开窗口，不再出现进程已运行但入口不可见的情况
- 模式切换：`左 Option + Shift` 循环切换五种模式，并在屏幕底部显示当前模式
- 可定制全局快捷键：左 `Option`、双击 `Ctrl` / `Option` / `Shift`，或选择 `⌃⇧ Space`、`⌥ Space`、`⌃ Space`、`⌃⌥ Space`
- 双击键和组合键在辅助功能授权后均可按任意普通键结束；结束键会被拦截，不会输入到文本框
- 没有辅助功能权限时自动回退到不占用单独 Option 的 `⌃⇧ Space` 按住说话
- 五种模式：智能编辑、中转英、Agent 模式、X Reply、文字转写
- 中转英：用中文或中英混合口述，直接生成地道英文；在 DashScope 下固定走 Qwen-MT 专用翻译协议，原话是待翻译数据，不作为聊天指令，不读取 System Prompt
- 中转英结果校验：默认使用 `qwen-mt-flash`；若校验发现问句语气、请求动作或英文输出不完整，仅用 `qwen-mt-plus` 专用翻译再试一次；全程不回退到聊天 Prompt，仍不符合则拒绝写入错误结果
- 智能编辑自动判断：没有选中文字时整理口述；有选中文字时把口述当作修改指令
- 智能编辑非对话保护：没有选中文字时，问句保持为问句、请求保持为请求，不再把你的口述当场回答或执行
- 选中文字后必须说出明确指令才会处理；沉默、语气词或普通补充内容会显示“未执行”，不修改原文、不生成新历史
- Agent 模式：把“帮我写一条推文 / 一封邮件 / 三个标题”等语音任务直接变成可用成品，并延续最近任务的上下文
- SQLite 本地长期记忆：为所有正式文字任务追加保存原始转写、实际指令、选中上下文、结果、模式、应用与时间；不保存原始音频
- “关于我”确认资料：手动填写职业与工作、默认语言、表达偏好、重要术语和正确拼写；系统永远不会自动改写这些字段
- “已学到的偏好”：每 100 条任务在本机固化一次常用术语、工作领域、语言组合与表达偏好；与“关于我”分层保存，只作低权重参考
- 个性化优先级：当前明确指令 > 当前模式 > 当前应用与来源 > “关于我” > “已学到的偏好” > 默认规则
- Agent 模式仍会按上下文预算注入最多 12 条最近任务；其他文字模式只读取当前任务需要的术语和非语言风格偏好
- 长期记忆可在设置中关闭、查看数据库位置和最近 Agent 任务；“重新学习偏好”收起在“隐私与数据”的二级入口中，并要求二次确认
- Agent 模式只生成草稿，永远不会自动回车、发布或对外执行；结果自动写入并保留在剪贴板
- 独立 Prompt Studio：为四种可见 AI 模式修改行为 Prompt；智能编辑内部分为“口述整理”和“选中修改”两个 Prompt
- 完整 Prompt 预览：同时查看固定安全规则、模式 Prompt、当前应用、个人词典与动态上下文如何组合
- 文字转写做最低限度整理：去掉无意义口癖、明显重复和确定的改口，补基础标点，同时保留原句、顺序、语气和细节
- 文字转写支持中英文夹杂：不把整段统一翻译成一种语言，保留英文产品名、技术词、缩写、大小写和自然空格
- 转写语言设置：默认自动识别混合语言，也可指定中文、粤语、英语、日语、韩语及二十多种主流语言；设置会转换为当前语音服务对应的语言参数
- 文字转写拥有独立可编辑 Prompt，可自行调整轻度清理的边界
- 自动清除口头禅、重复和中途改口
- 自动标点、分段、列表格式
- 中文口述、地道英文输出
- 读取选中文字作为 X Reply 或语音编辑的上下文
- 根据当前应用调整语气
- 个人词典
- 本地历史、复制与重新使用；重置入口仅在设置的二级数据管理中提供
- “发送/按回车”语音命令（默认关闭）
- Provider Vault：在设置中添加、更新或移除阿里云百炼、豆包/火山方舟、OpenAI、Claude 与 ElevenLabs Token
- 语音识别与文字生成独立选择供应商和模型：阿里支持两者，OpenAI 支持两者，ElevenLabs 用于语音，Claude 与豆包用于文字
- API Key 保存在本机 AES-GCM 加密的 Provider Vault，不写入项目、偏好设置、日志或历史，也不会在保存后回显
- 首次使用清单：云端、麦克风、辅助功能逐项确认
- 应用内语音试用：无需切到其他输入框即可验证完整链路
- X Reply 录音前检查选中文字；智能编辑会在录音开始时自动锁定有无选区
- X Reply 生成后始终复制到剪贴板，由用户在回复框中按 `⌘V` 粘贴
- 智能编辑的选中修改分支完成后仍会把结果保留在剪贴板，自动替换与手动粘贴可以同时使用
- 所有模式的最终结果都会保留在剪贴板；自动写入成功后仍可随时按 `⌘V` 再次粘贴
- X Reply 支持无口述自动回复：选中推文后保持安静结束录音，自动寻找值得加入讨论的新角度
- 每次录音锁定开始时的模式，处理中切换不会改变本次结果
- 自动写入失败时保住结果并复制到剪贴板
- 原创 OpenType Air 音效系统：麦克风就绪、结束录音、完成写入和出现问题分别使用短促、低响度的独立提示音，可在设置中试听或完全关闭
- 录音浮层实时字幕：说话时持续显示临时识别文字，配合真实音量驱动的动态声波和呼吸光
- 实时字幕仅用于预览，松开后仍由所选语音服务重新完成最终高质量识别；可在设置中关闭
- 面向用户的错误提示，不再直接展示云端技术报错
- 一键多意图：以“英文：…”“Agent 模式：…”或“X 回复：…”开头，本次自动切换模式；旧的“命令输入：…”口令继续兼容

## macOS 运行

```bash
./scripts/build-app.sh
open dist/OpenType.app
```

首次运行需要授权：

1. 麦克风：录制你的语音
2. 辅助功能：读取选中文字并把结果写回当前输入框

在 `设置 → AI 服务 → Provider Vault` 添加需要的 Token，并分别选择语音识别和文字生成服务。旧版环境变量或 `~/.openclaw/.env` 中的 `DASHSCOPE_API_KEY` 会在首次启动时静默迁移到本机加密 Vault，之后可以直接在设置中管理。

## 隐私

- 最终音频只发送到用户选择的语音识别服务；识别文字会发送到用户选择的文字生成服务做对应模式的处理。处理结束后删除本地临时音频。
- 实时字幕使用 Apple 语音识别，仅作为录音预览。
- 所有 Provider Token 只保存在 `Application Support/OpenType` 下的本机 AES-GCM 加密 Vault；密钥文件与 Vault 文件权限均设为仅当前用户可读写。它避免每次启动弹出钥匙串授权，但不等同于硬件隔离的 Keychain。
- 输入历史仅保存在本机 `Application Support/OpenType`，可以关闭，或在设置的二级数据管理中重置。
- 长期记忆只保存在本机 `Application Support/OpenType/memory.sqlite3`；旧版 `agent-memory.json` 和现有历史会在首次启动时去重迁移。
- 原始输入审计事件追加写入 `Application Support/OpenType/audit-events.v1.jsonl`，记录识别、完成、取消或失败状态；该审计文件不被普通历史重置或语言习惯重学覆盖。
- 常用术语、任务领域和表达偏好均在设备上离线归纳，每 100 条固化一次。执行文字任务时，只把与当前生成有关的少量确认资料和已学偏好随 Prompt 发给用户选择的文字模型。
- “重新学习偏好”会移除任务事件和可重建推断，但保留用户亲自填写的“关于我”。
- X Reply 只复制到剪贴板，不会自动写入或发布。
