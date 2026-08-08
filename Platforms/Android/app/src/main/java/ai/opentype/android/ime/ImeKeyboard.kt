package ai.opentype.android.ime

import android.view.MotionEvent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInteropFilter
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.opentype.android.model.InputMode
import ai.opentype.android.model.InterfaceLanguage
import ai.opentype.android.model.L10n

@OptIn(ExperimentalComposeUiApi::class)
@Composable
internal fun ImeKeyboard(
    language: InterfaceLanguage,
    mode: InputMode,
    transcript: String,
    status: String,
    listening: Boolean,
    processing: Boolean,
    audioLevel: Float,
    passwordField: Boolean,
    onModeSelected: (InputMode) -> Unit,
    onPressStart: () -> Unit,
    onPressEnd: () -> Unit,
    onAutomaticXReply: () -> Unit,
    onSwitchInputMethod: () -> Unit
) {
    val micScale by animateFloatAsState(
        targetValue = if (listening) 1.02f + audioLevel * 0.12f else 1f,
        label = "micScale"
    )
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.background)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text("OpenType", fontWeight = FontWeight.Bold, fontSize = 17.sp)
                Text(
                    L10n.modeTitle(mode, language),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            OutlinedButton(onClick = onSwitchInputMethod) {
                Text(L10n.text(language, "切换键盘", "Next keyboard"), fontSize = 12.sp)
            }
        }

        Row(
            modifier = Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            InputMode.entries.forEach { item ->
                val selected = item == mode
                Button(
                    onClick = { onModeSelected(item) },
                    enabled = !listening && !processing,
                    contentPadding = ButtonDefaults.ContentPadding,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (selected) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.surfaceVariant,
                        contentColor = if (selected) MaterialTheme.colorScheme.onPrimary
                        else MaterialTheme.colorScheme.onSurfaceVariant
                    )
                ) {
                    Text(L10n.modeTitle(item, language), fontSize = 12.sp)
                }
            }
        }

        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            color = MaterialTheme.colorScheme.surface
        ) {
            Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
                Text(
                    if (transcript.isBlank()) {
                        if (passwordField) {
                            L10n.text(language, "密码输入：不读取上下文，不保存历史", "Password field: no context or history")
                        } else {
                            L10n.text(language, "按住下方按钮说话，松开后写入", "Hold the button, speak, then release to insert")
                        }
                    } else transcript,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    color = if (transcript.isBlank()) MaterialTheme.colorScheme.onSurfaceVariant
                    else MaterialTheme.colorScheme.onSurface
                )
                Spacer(Modifier.height(2.dp))
                Text(status, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (mode == InputMode.X_REPLY) {
                OutlinedButton(
                    onClick = onAutomaticXReply,
                    enabled = !listening && !processing && !passwordField
                ) {
                    Text(L10n.text(language, "自动回复", "Draft for me"), fontSize = 12.sp)
                }
            } else {
                Spacer(Modifier.weight(0.35f))
            }

            Surface(
                modifier = Modifier
                    .weight(1f)
                    .height(58.dp)
                    .scale(micScale)
                    .pointerInteropFilter { event ->
                        if (passwordField) return@pointerInteropFilter true
                        when (event.actionMasked) {
                            MotionEvent.ACTION_DOWN -> {
                                if (!processing) onPressStart()
                                true
                            }
                            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                                if (!processing) onPressEnd()
                                true
                            }
                            else -> true
                        }
                    },
                shape = RoundedCornerShape(22.dp),
                color = when {
                    processing || passwordField -> MaterialTheme.colorScheme.surfaceVariant
                    listening -> Color(0xFFFF4D5E)
                    else -> MaterialTheme.colorScheme.primary
                }
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            Modifier
                                .size(10.dp)
                                .background(Color.White, CircleShape)
                        )
                        Spacer(Modifier.size(8.dp))
                        Text(
                            when {
                                passwordField -> L10n.text(language, "密码框不可使用", "Unavailable in password fields")
                                processing -> L10n.text(language, "处理中…", "Processing…")
                                listening -> L10n.text(language, "正在听 · 松开完成", "Listening · Release to finish")
                                else -> L10n.text(language, "按住说话", "Hold to speak")
                            },
                            color = if (processing || passwordField) MaterialTheme.colorScheme.onSurfaceVariant else Color.White,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }

            Spacer(Modifier.weight(0.35f))
        }
    }
}
