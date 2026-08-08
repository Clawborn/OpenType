package ai.opentype.android.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ai.opentype.android.model.AppSettings
import ai.opentype.android.model.AppTheme
import ai.opentype.android.model.HistoryEntry
import ai.opentype.android.model.InputMode
import ai.opentype.android.model.InterfaceLanguage
import ai.opentype.android.model.L10n
import ai.opentype.android.model.ProcessingState
import ai.opentype.android.model.TextProvider
import ai.opentype.android.ui.theme.OpenTypeTheme
import java.text.DateFormat
import java.util.Date

private enum class AppTab { INPUT, HISTORY, SETTINGS }

@Composable
fun OpenTypeApp(
    viewModel: OpenTypeViewModel,
    microphoneGranted: Boolean
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var tab by remember { mutableStateOf(AppTab.INPUT) }
    var hasMicrophone by remember { mutableStateOf(microphoneGranted) }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasMicrophone = granted
        if (granted) viewModel.startListening()
    }

    OpenTypeTheme(theme = state.settings.theme) {
        Scaffold(
            modifier = Modifier.fillMaxSize(),
            bottomBar = {
                OpenTypeNavigation(
                    selected = tab,
                    language = state.settings.interfaceLanguage,
                    onSelected = { tab = it }
                )
            }
        ) { padding ->
            when (tab) {
                AppTab.INPUT -> InputScreen(
                    state = state,
                    modifier = Modifier.padding(padding),
                    microphoneGranted = hasMicrophone,
                    onRequestMicrophone = { permissionLauncher.launch(Manifest.permission.RECORD_AUDIO) },
                    onStartListening = viewModel::startListening,
                    onStopListening = viewModel::stopListening,
                    onModeSelected = viewModel::selectMode,
                    onTranscriptChanged = viewModel::setTranscript,
                    onContextChanged = viewModel::setContext,
                    onProcess = { viewModel.processCurrent() },
                    onAutomaticXReply = { viewModel.processCurrent(allowEmptyXViewpoint = true) },
                    onCopy = viewModel::copyResult
                )
                AppTab.HISTORY -> HistoryScreen(
                    entries = state.history,
                    language = state.settings.interfaceLanguage,
                    modifier = Modifier.padding(padding)
                )
                AppTab.SETTINGS -> SettingsScreen(
                    current = state.settings,
                    tokenConfigured = state.tokenConfigured,
                    language = state.settings.interfaceLanguage,
                    modifier = Modifier.padding(padding),
                    onSave = viewModel::saveSettings,
                    onRemoveToken = viewModel::removeCurrentToken
                )
            }
        }
    }
}

@Composable
private fun OpenTypeNavigation(
    selected: AppTab,
    language: InterfaceLanguage,
    onSelected: (AppTab) -> Unit
) {
    NavigationBar {
        val items = listOf(
            AppTab.INPUT to L10n.text(language, "输入", "Input"),
            AppTab.HISTORY to L10n.text(language, "历史", "History"),
            AppTab.SETTINGS to L10n.text(language, "设置", "Settings")
        )
        items.forEach { (tab, label) ->
            NavigationBarItem(
                selected = selected == tab,
                onClick = { onSelected(tab) },
                icon = {
                    Box(
                        Modifier
                            .size(if (selected == tab) 8.dp else 6.dp)
                            .background(
                                if (selected == tab) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurfaceVariant,
                                CircleShape
                            )
                    )
                },
                label = { Text(label) }
            )
        }
    }
}

@Composable
private fun InputScreen(
    state: OpenTypeUiState,
    modifier: Modifier,
    microphoneGranted: Boolean,
    onRequestMicrophone: () -> Unit,
    onStartListening: () -> Unit,
    onStopListening: () -> Unit,
    onModeSelected: (InputMode) -> Unit,
    onTranscriptChanged: (String) -> Unit,
    onContextChanged: (String) -> Unit,
    onProcess: () -> Unit,
    onAutomaticXReply: () -> Unit,
    onCopy: () -> Unit
) {
    val language = state.settings.interfaceLanguage
    val listening = state.processingState == ProcessingState.LISTENING
    val busy = state.processingState in listOf(
        ProcessingState.TRANSCRIBING,
        ProcessingState.TRANSFORMING,
        ProcessingState.INSERTING
    )
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Text("OpenType", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
            Text(
                L10n.modeDescription(state.settings.mode, language),
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        item { KeyboardSetupCard(language) }
        item {
            Row(
                modifier = Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                InputMode.entries.forEach { mode ->
                    FilterChip(
                        selected = state.settings.mode == mode,
                        onClick = { onModeSelected(mode) },
                        label = { Text(L10n.modeTitle(mode, language)) }
                    )
                }
            }
        }
        if (state.settings.mode == InputMode.X_REPLY || state.settings.mode == InputMode.SMART_EDIT) {
            item {
                OutlinedTextField(
                    value = state.contextText,
                    onValueChange = onContextChanged,
                    modifier = Modifier.fillMaxWidth(),
                    label = {
                        Text(
                            if (state.settings.mode == InputMode.X_REPLY) {
                                L10n.text(language, "原帖内容", "Original post")
                            } else L10n.text(language, "可选：要修改的文字", "Optional: text to edit")
                        )
                    },
                    minLines = 2,
                    maxLines = 5
                )
            }
        }
        item {
            LiveTranscriptCard(
                transcript = state.transcript,
                language = language,
                audioLevel = state.audioLevel,
                listening = listening,
                onChanged = onTranscriptChanged
            )
        }
        item {
            Button(
                onClick = {
                    when {
                        listening -> onStopListening()
                        !microphoneGranted -> onRequestMicrophone()
                        else -> onStartListening()
                    }
                },
                enabled = !busy,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(58.dp),
                shape = RoundedCornerShape(20.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (listening) Color(0xFFFF4D5E) else MaterialTheme.colorScheme.primary
                )
            ) {
                Text(
                    when {
                        busy -> L10n.text(language, "处理中…", "Processing…")
                        listening -> L10n.text(language, "点击结束", "Tap to finish")
                        else -> L10n.text(language, "点击开始说话", "Tap to speak")
                    },
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
        if (state.transcript.isNotBlank() && !listening) {
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedButton(onClick = onProcess, enabled = !busy, modifier = Modifier.weight(1f)) {
                        Text(L10n.text(language, "重新处理", "Process text"))
                    }
                    if (state.settings.mode == InputMode.X_REPLY) {
                        OutlinedButton(onClick = onAutomaticXReply, enabled = !busy, modifier = Modifier.weight(1f)) {
                            Text(L10n.text(language, "自动回复", "Draft for me"))
                        }
                    }
                }
            }
        } else if (state.settings.mode == InputMode.X_REPLY && state.contextText.isNotBlank()) {
            item {
                OutlinedButton(onClick = onAutomaticXReply, enabled = !busy, modifier = Modifier.fillMaxWidth()) {
                    Text(L10n.text(language, "不说观点，直接生成回复", "Draft a reply without a viewpoint"))
                }
            }
        }
        if (state.statusMessage.isNotBlank()) {
            item {
                Text(
                    localizeStatus(state.statusMessage, language),
                    color = if (state.processingState == ProcessingState.FAILED) MaterialTheme.colorScheme.error
                    else MaterialTheme.colorScheme.primary
                )
            }
        }
        if (state.result.isNotBlank()) {
            item { ResultCard(state.result, language, onCopy) }
        }
    }
}

@Composable
private fun KeyboardSetupCard(language: InterfaceLanguage) {
    val context = LocalContext.current
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        shape = RoundedCornerShape(20.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                L10n.text(language, "在任何输入框里使用", "Use OpenType in any text field"),
                fontWeight = FontWeight.SemiBold
            )
            Text(
                L10n.text(
                    language,
                    "启用 OpenType 键盘后，按住说话、松开处理并直接写入。",
                    "Enable the OpenType keyboard, then hold to speak and release to insert."
                ),
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = {
                        context.startActivity(
                            Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                    },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(L10n.text(language, "启用键盘", "Enable keyboard"))
                }
                OutlinedButton(
                    onClick = {
                        context.getSystemService(InputMethodManager::class.java)?.showInputMethodPicker()
                    },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(L10n.text(language, "切换到 OpenType", "Choose OpenType"))
                }
            }
        }
    }
}

@Composable
private fun LiveTranscriptCard(
    transcript: String,
    language: InterfaceLanguage,
    audioLevel: Float,
    listening: Boolean,
    onChanged: (String) -> Unit
) {
    Card(shape = RoundedCornerShape(20.dp)) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    if (listening) L10n.text(language, "正在听", "Listening")
                    else L10n.text(language, "你说的内容", "Your dictation"),
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f)
                )
                Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
                    repeat(5) { index ->
                        val height = if (listening) 5f + (audioLevel * (10 + index * 4)) else 5f
                        Box(
                            Modifier
                                .size(width = 3.dp, height = height.dp)
                                .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(2.dp))
                        )
                    }
                }
            }
            OutlinedTextField(
                value = transcript,
                onValueChange = onChanged,
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text(L10n.text(language, "实时字幕会显示在这里", "Live transcript appears here")) },
                minLines = 3,
                maxLines = 7
            )
        }
    }
}

@Composable
private fun ResultCard(result: String, language: InterfaceLanguage, onCopy: () -> Unit) {
    Card(
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(L10n.text(language, "结果 · 已自动复制", "Result · Copied automatically"), fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                OutlinedButton(onClick = onCopy) { Text(L10n.text(language, "复制", "Copy")) }
            }
            Text(result)
        }
    }
}

@Composable
private fun HistoryScreen(
    entries: List<HistoryEntry>,
    language: InterfaceLanguage,
    modifier: Modifier
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Text(L10n.text(language, "本地历史", "Local history"), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
            Text(
                L10n.text(language, "保存原始转写和最终结果；密码输入不会保存。", "Original transcripts and results stay local; password input is never saved."),
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (entries.isEmpty()) {
            item { Text(L10n.text(language, "完成一次输入后会显示在这里。", "Completed inputs appear here.")) }
        } else {
            items(entries, key = { it.id }) { entry ->
                HistoryCard(entry, language)
            }
        }
    }
}

@Composable
private fun HistoryCard(entry: HistoryEntry, language: InterfaceLanguage) {
    val context = LocalContext.current
    val cardModifier = if (entry.output.isNotBlank()) {
        Modifier
            .fillMaxWidth()
            .clickable {
                context.getSystemService(android.content.ClipboardManager::class.java)
                    ?.setPrimaryClip(android.content.ClipData.newPlainText("OpenType", entry.output))
            }
    } else Modifier.fillMaxWidth()
    Card(
        modifier = cardModifier,
        shape = RoundedCornerShape(18.dp)
    ) {
        Column(modifier = Modifier.padding(15.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row {
                Text(L10n.modeTitle(entry.mode, language), fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                Text(
                    DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(entry.timestampMillis)),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Text(
                entry.originalTranscript,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            HorizontalDivider()
            if (entry.output.isNotBlank()) {
                Text(entry.output, maxLines = 4, overflow = TextOverflow.Ellipsis)
                Text(L10n.text(language, "点击卡片复制结果", "Tap the card to copy"), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
            } else {
                Text(
                    entry.error ?: L10n.text(language, "未生成结果", "No result was generated"),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsScreen(
    current: AppSettings,
    tokenConfigured: Boolean,
    language: InterfaceLanguage,
    modifier: Modifier,
    onSave: (AppSettings, String) -> Unit,
    onRemoveToken: () -> Unit
) {
    var draft by remember(current) { mutableStateOf(current) }
    var token by remember(current.provider) { mutableStateOf("") }
    var saved by remember { mutableStateOf(false) }
    LaunchedEffect(current) {
        draft = current
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(18.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        item {
            Text(L10n.text(language, "设置", "Settings"), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        }
        item {
            SettingsSection(title = L10n.text(language, "界面语言", "Interface language")) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    InterfaceLanguage.entries.forEach { item ->
                        FilterChip(
                            selected = draft.interfaceLanguage == item,
                            onClick = { draft = draft.copy(interfaceLanguage = item); saved = false },
                            label = { Text(if (item == InterfaceLanguage.CHINESE) "中文" else "English") }
                        )
                    }
                }
            }
        }
        item {
            SettingsSection(title = L10n.text(language, "配色", "Color theme")) {
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    AppTheme.entries.forEach { theme ->
                        FilterChip(
                            selected = draft.theme == theme,
                            onClick = { draft = draft.copy(theme = theme); saved = false },
                            label = { Text(theme.id.replaceFirstChar { it.uppercase() }) }
                        )
                    }
                }
            }
        }
        item {
            SettingsSection(title = L10n.text(language, "文字模型", "Text model")) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextProvider.entries.forEach { provider ->
                        FilterChip(
                            selected = draft.provider == provider,
                            onClick = {
                                draft = draft.copy(
                                    provider = provider,
                                    endpoint = provider.defaultEndpoint,
                                    model = provider.defaultModel
                                )
                                token = ""
                                saved = false
                            },
                            label = {
                                Text(
                                    when (provider) {
                                        TextProvider.DASH_SCOPE -> "DashScope"
                                        TextProvider.VOLCENGINE -> "Doubao"
                                        TextProvider.OPENAI -> "OpenAI"
                                        TextProvider.ANTHROPIC -> "Claude"
                                    }
                                )
                            }
                        )
                    }
                }
                OutlinedTextField(
                    value = draft.endpoint,
                    onValueChange = { draft = draft.copy(endpoint = it); saved = false },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Chat completions URL") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next)
                )
                OutlinedTextField(
                    value = draft.model,
                    onValueChange = { draft = draft.copy(model = it); saved = false },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(L10n.text(language, "模型", "Model")) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next)
                )
                OutlinedTextField(
                    value = token,
                    onValueChange = { token = it; saved = false },
                    modifier = Modifier.fillMaxWidth(),
                    label = {
                        Text(
                            if (tokenConfigured) {
                                L10n.text(language, "Token（已安全保存；留空不修改）", "Token (saved securely; leave blank to keep)")
                            } else "API Token"
                        )
                    },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done)
                )
                Text(
                    L10n.text(
                        language,
                        "Token 使用 Android Keystore 的 AES-GCM 密钥加密，不会写入普通偏好或日志。",
                        "The token is encrypted with an Android Keystore AES-GCM key and is never written to ordinary preferences or logs."
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        item {
            SettingsSection(title = L10n.text(language, "语音识别", "Speech recognition")) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("auto", "zh", "en").forEach { value ->
                        FilterChip(
                            selected = draft.recognitionLanguage == value,
                            onClick = { draft = draft.copy(recognitionLanguage = value); saved = false },
                            label = { Text(when (value) { "zh" -> "中文"; "en" -> "English"; else -> L10n.text(language, "自动", "Auto") }) }
                        )
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(
                        checked = draft.includeRecentTasks,
                        onCheckedChange = { draft = draft.copy(includeRecentTasks = it); saved = false }
                    )
                    Text(L10n.text(language, "Agent 参考近期已完成任务", "Let Agent use recent completed tasks"))
                }
                Text(
                    L10n.text(
                        language,
                        "语音由 Android 系统 SpeechRecognizer 处理；具体是否联网取决于设备当前的语音服务。",
                        "Speech uses Android's system SpeechRecognizer; whether it goes online depends on the recognition service installed on the device."
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        item {
            Button(
                onClick = { onSave(draft, token); token = ""; saved = true },
                modifier = Modifier.fillMaxWidth(),
                enabled = draft.endpoint.isNotBlank() && draft.model.isNotBlank()
            ) {
                Text(if (saved) L10n.text(language, "已保存", "Saved") else L10n.text(language, "保存设置", "Save settings"))
            }
        }
        if (tokenConfigured) {
            item {
                OutlinedButton(onClick = { onRemoveToken(); token = "" }, modifier = Modifier.fillMaxWidth()) {
                    Text(L10n.text(language, "移除当前模型 Token", "Remove current provider token"))
                }
            }
        }
    }
}

@Composable
private fun SettingsSection(title: String, content: @Composable () -> Unit) {
    Card(shape = RoundedCornerShape(20.dp)) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(title, fontWeight = FontWeight.SemiBold)
            content()
        }
    }
}

private fun localizeStatus(message: String, language: InterfaceLanguage): String = when {
    message == "Copied" -> L10n.text(language, "已复制", "Copied")
    message.contains("explicit editing", true) -> L10n.text(language, "选中文字后，必须明确说出修改指令", "Selected text needs an explicit edit instruction")
    message.contains("original X", true) -> L10n.text(language, "请先粘贴原帖内容", "Paste the original X post first")
    message.contains("Configure a provider", true) -> L10n.text(language, "请先在设置里保存模型 Token", "Save a provider token in Settings first")
    message.contains("No speech", true) -> L10n.text(language, "没有识别到语音", "No speech was recognized")
    else -> message
}
