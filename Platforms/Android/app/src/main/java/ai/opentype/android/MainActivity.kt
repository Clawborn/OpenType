package ai.opentype.android

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.core.content.ContextCompat
import ai.opentype.android.ui.OpenTypeApp
import ai.opentype.android.ui.OpenTypeViewModel

class MainActivity : ComponentActivity() {
    private val viewModel by viewModels<OpenTypeViewModel>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            OpenTypeApp(
                viewModel = viewModel,
                microphoneGranted = ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.RECORD_AUDIO
                ) == PackageManager.PERMISSION_GRANTED
            )
        }
    }

    override fun onResume() {
        super.onResume()
        viewModel.refreshFromStorage()
    }
}
