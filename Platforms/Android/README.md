# OpenType for Android

OpenType Android 是一个原生 Kotlin + Jetpack Compose 客户端，同时包含真正的系统输入法 `InputMethodService`。启用 OpenType 键盘后，可以在任意允许第三方输入法的文本框中按住说话、查看实时转写、松开处理，并通过 `InputConnection.commitText` 写入当前输入框。

当前版本是已通过真实编译的原生 MVP，不是静态 UI 壳。Debug APK、单元测试和 Android Lint 均已在本机工具链上验证：

- Android `SpeechRecognizer` 实时和最终转写，带音量动态反馈
- 五种统一模式：`smartEdit`、`english`、`agent`、`xReply`、`transcribe`
- Compose 宿主 App：权限、App 内试用、历史、模型设置、中英界面、六套配色
- 系统 IME：按住说话、松开处理、直接写入、剪贴板兜底、切换下一输入法
- 每个输入框使用独立 session；切换输入框、隐藏键盘或结束输入时会取消旧请求，旧结果不会写进新输入框或密码框
- DashScope、Volcengine/Doubao、OpenAI（可修改为兼容接口）与 Anthropic Claude
- Android Keystore AES-GCM Token 加密；界面不回显已保存 Token
- append-only JSONL 本地审计；每次非密码输入分别追加 `recognized` 与最终状态事件，保存原始转写、模式、结果、时间、Provider 和 Model
- 轻转写混合管线：短句本地处理；复杂口述可调用模型；保真校验失败时回退原文

## 首次运行

1. 安装 Android Studio，选择 JDK 17，并安装 Android SDK Platform 35 与 Build Tools。
2. 用 Android Studio 打开本目录 `Platforms/Android`，等待 Gradle Sync 完成。
3. 运行 `app`，允许麦克风权限。
4. 在「设置」选择文字 Provider、模型和 API URL，输入一次 Token 并保存。
5. 首页点击「启用键盘」，在 Android 系统设置中启用 OpenType。
6. 点击「切换到 OpenType」，或在任意输入框的输入法切换器里选择 OpenType。
7. 在 OpenType 键盘按住「按住说话」，松开后结果会写入当前输入框，同时保留在剪贴板。

命令行构建（已安装 JDK 17 和 Android SDK 后）：

```bash
zsh ./gradlew :app:testDebugUnitTest :app:assembleDebug
```

这里的 `gradlew` 是纯文本 bootstrap，会下载固定的 Gradle 8.9。若机器已有 Gradle 8.9，也可以直接运行：

```bash
gradle :app:testDebugUnitTest :app:assembleDebug
```

Debug APK 生成在 `app/build/outputs/apk/debug/app-debug.apk`；本次交付副本位于项目根目录的 `dist/OpenType-Android-debug-v0.1.0.apk`。它使用 Android Debug 证书签名，适合本地安装验收，不是 Play Store 正式发布包。

## 五种模式

| 模式 | Android IME 行为 |
| --- | --- |
| 智能编辑 | 没有选区时整理口述；当前输入框有选区时，只有说出明确修改指令才替换选区，否则取消且不改文字 |
| 中转英 | 把中文或中英混合口述改写成自然英文；DashScope 使用 `qwen-mt-flash` 专用翻译请求，不把原话放进 System Prompt 当指令 |
| Agent | 根据命令生成几百字以内的文字草稿，可参考近期已完成的 Agent 任务；不会自动发送或发布 |
| X Reply | 优先使用当前选区，否则使用剪贴板中的原帖；可说出观点，也可点击「自动回复」直接生成一条草稿 |
| 文字转写 | 只清理口癖、重复和基础标点；短问题在本地处理，永远不能被当成问题回答 |

所有成功结果先写入系统剪贴板，再尝试 `commitText`。因此即使目标 App 拒绝 IME 写入，结果仍可以手动粘贴。代码没有调用 `performEditorAction`、模拟 Enter、发帖或消息发送 API。

## 隐私与数据

- 原始音频不落盘。系统 `SpeechRecognizer` 的具体联网行为取决于设备安装的语音识别服务。
- Provider Token 使用 Android Keystore 中不可导出的 AES-GCM 密钥加密；普通 SharedPreferences 只包含 IV 和密文。
- 审计日志位于 App 私有目录 `files/opentype-audit/events.jsonl`，按事件只追加，不按条数覆盖旧记录。
- App 与 IME 的追加写入使用进程锁、文件锁和强制落盘；读写在后台 I/O 线程完成，普通历史界面和 Agent 只按块读取日志尾部的有限记录。
- 历史 UI 会把同一个 `requestId` 的 `recognized` 与最终状态聚合成一条；底层 JSONL 仍保留全部事件。文件是产品代码路径上的 append-only 日志，不宣称能抵抗 root 用户或取证工具篡改。
- 密码输入框中完全停用 OpenType 语音，不读取选区或剪贴板，不调用云端文字模型，也不写历史。
- App 同时通过 `allowBackup=false`、旧版 `fullBackupContent` 和 Android 12+ `dataExtractionRules` 禁止云备份与设备迁移，避免 Token 密文和本地历史离开设备。

不要把 API Token 写入 `local.properties`、Gradle 文件、源码或日志。本工程没有附带任何真实 Token。

## Provider

| Provider | 默认模型 | 协议 |
| --- | --- | --- |
| DashScope | 普通模式 `qwen-plus`；中转英 `qwen-mt-flash` | OpenAI-compatible chat completions / Qwen-MT translation options |
| Volcengine / Doubao | `doubao-seed-2-0-lite-260215` | OpenAI-compatible chat completions |
| OpenAI | `gpt-5-mini` | OpenAI chat completions；URL 可改为 HTTPS 兼容端点 |
| Anthropic | `claude-sonnet-5` | Anthropic `/v1/messages` |

语音首版只使用系统 `SpeechRecognizer`。DashScope 云 ASR、OpenAI Transcription 和 ElevenLabs Scribe 尚未接入 Android 移动端；这不会影响系统 IME 的语音输入流程。

## X Reply 的上下文

IME 只能读取当前可编辑输入框向它公开的选区，无法跨 App 任意读取网页内容。因此推荐流程是：

1. 在 X 中复制原帖；
2. 点击回复框并切换到 OpenType；
3. 选择 X Reply，按住说出观点，或点击「自动回复」；
4. OpenType 从剪贴板读取原帖，生成草稿并写入回复框。发布仍由用户自己点击。

宿主 App 的 X Reply 页面也提供「原帖内容」输入框，方便显式核对上下文。

## 关键验收

单元测试覆盖共享 `AcceptanceCases.json` 中可离线验证的关键行为：

- `为啥微信不行` → `为啥微信不行？`，不调用文字模型
- 长口述如果模型返回解释性答案，会被保真校验拒绝
- 选中文字后说「我还想补充一点」不构成修改指令
- 选中文字后说「改得更口语一点」使用选区作为唯一编辑源
- 五个 mode id 与共享协议一致

真机发布前还应手工验证：

1. 首次麦克风授权和拒绝后的恢复路径。
2. Chrome、微信、X、Notes 等输入框的 `commitText` 与剪贴板兜底。
3. 密码框不读上下文、不写日志、不发云端请求。
4. 网络失败时原始转写仍显示且已复制。
5. Agent / X Reply 只写草稿，不自动发送。
6. Token 在 App 重启后仍可用，且界面不回显明文。
7. 中文 / English UI 与六套配色。

## 本机工具链状态（2026-08-01）

本机使用 Temurin JDK 17.0.20、Gradle 8.9、AGP 8.7.3、Kotlin 2.0.21、Platform 35 与 Build Tools 34.0.0 完成验证：22 项 JVM 单元测试通过（含中转英英文输出、无标点直接问句、问句保持、异常扩写检测与单次纠偏），`:app:assembleDebug` 成功，Android Lint 为 0 errors。APK 的包名为 `ai.opentype.android`，min SDK 26、target SDK 35，v2 Debug 签名和压缩完整性均已校验。尚未冒充完成的是 Android 真机验收：麦克风、系统 `SpeechRecognizer`、跨 App IME 写入、Keystore 重启持久性和四个云 Provider 的真实请求仍需在目标手机上测试。

2026-08-08 新增了第 23 项“中转英请求不得变成成品”回归用例及对应 speech-act/action guard；当前机器缺少可用 Java Runtime，因此本轮没有把旧的 22 项基线状态冒充为 23/23 通过。
