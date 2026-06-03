package com.dantetesta.dantecast

import android.Manifest
import android.app.Activity
import android.content.Context
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.dantetesta.dantecast.ui.MirrorViewModel
import com.dantetesta.dantecast.ui.navigation.AppNav
import com.dantetesta.dantecast.ui.theme.DanteCastTheme

/**
 * Activity única do app. Responsável por:
 *  - Hospedar a navegação Compose.
 *  - DONO do fluxo de permissão de captura (MediaProjection) via ActivityResult.
 *  - Solicitar permissões de runtime: CAMERA (QR) e POST_NOTIFICATIONS (API 33+).
 *
 * IMPORTANTE (Android 14+): o token retornado pelo createScreenCaptureIntent é de uso
 * ÚNICO e deve ser re-solicitado a cada sessão. Por isso pedimos sob demanda, não no onCreate.
 */
class MainActivity : ComponentActivity() {

    private val viewModel: MirrorViewModel by viewModels()

    // Launcher do diálogo de captura de tela (retorna resultCode + data Intent).
    private val captureLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            // Token obtido -> inicia o service de espelhamento.
            viewModel.startMirroring(result.resultCode, result.data!!)
        }
        // Se negado, não fazemos nada: o usuário permanece na PermissionScreen.
    }

    // Launcher para POST_NOTIFICATIONS (não bloqueante; só melhora a UX).
    private val notifPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { /* resultado ignorado: o foreground service funciona mesmo sem, mas a notificação não aparece */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Pede POST_NOTIFICATIONS cedo (API 33+) para a notificação do service aparecer.
        maybeRequestNotificationPermission()

        setContent {
            DanteCastTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    AppNav(
                        onRequestCapture = { requestScreenCapture() },
                        viewModel = viewModel
                    )
                }
            }
        }
    }

    /** Dispara o diálogo do sistema de captura de tela. */
    private fun requestScreenCapture() {
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        // createScreenCaptureIntent: o usuário verá o aviso de gravação de tela.
        captureLauncher.launch(mpm.createScreenCaptureIntent())
    }

    private fun maybeRequestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
            if (!granted) {
                notifPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }
}
