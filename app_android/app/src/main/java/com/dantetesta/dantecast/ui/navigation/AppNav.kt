package com.dantetesta.dantecast.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.dantetesta.dantecast.model.SessionState
import com.dantetesta.dantecast.ui.MirrorViewModel
import com.dantetesta.dantecast.ui.PermissionScreen
import com.dantetesta.dantecast.ui.ScanQrScreen
import com.dantetesta.dantecast.ui.SettingsScreen
import com.dantetesta.dantecast.ui.StreamingScreen
import com.dantetesta.dantecast.ui.WelcomeScreen

/** Rotas da navegação Compose. */
object Routes {
    const val WELCOME = "welcome"
    const val SCAN_QR = "scan_qr"
    const val PERMISSION = "permission"
    const val STREAMING = "streaming"
    const val SETTINGS = "settings"
}

/**
 * Grafo de navegação principal.
 *
 * @param onRequestCapture solicita a permissão de captura (vive na Activity); ao conceder,
 *        a Activity chama viewModel.startMirroring(...) e navega para STREAMING.
 */
@Composable
fun AppNav(
    onRequestCapture: () -> Unit,
    navController: NavHostController = rememberNavController(),
    viewModel: MirrorViewModel = viewModel()
) {
    val status by viewModel.sessionStatus.collectAsStateWithLifecycle()

    // Reage a mudanças de estado da sessão para navegar automaticamente.
    LaunchedEffect(status.state) {
        when (status.state) {
            SessionState.STREAMING,
            SessionState.CONNECTING,
            SessionState.HANDSHAKING -> {
                if (navController.currentDestination?.route != Routes.STREAMING) {
                    navController.navigate(Routes.STREAMING) {
                        launchSingleTop = true
                        // Limpa as telas de scan/permissão da pilha; WELCOME permanece como raiz.
                        popUpTo(Routes.WELCOME) { inclusive = false }
                    }
                }
            }
            else -> Unit
        }
    }

    NavHost(navController = navController, startDestination = Routes.WELCOME) {

        composable(Routes.WELCOME) {
            WelcomeScreen(
                onConnect = { navController.navigate(Routes.SCAN_QR) },
                onSettings = { navController.navigate(Routes.SETTINGS) }
            )
        }

        composable(Routes.SCAN_QR) {
            ScanQrScreen(
                onPaired = { qr ->
                    viewModel.setPairingTarget(qr)
                    navController.navigate(Routes.PERMISSION)
                },
                onBack = { navController.popBackStack() }
            )
        }

        composable(Routes.PERMISSION) {
            PermissionScreen(
                macName = viewModel.pairingTarget?.name ?: "",
                onAuthorize = onRequestCapture, // dispara o fluxo de captura na Activity
                onBack = { navController.popBackStack() }
            )
        }

        composable(Routes.STREAMING) {
            StreamingScreen(
                status = status,
                onStop = {
                    viewModel.stopMirroring()
                },
                onDone = {
                    viewModel.resetSession()
                    navController.navigate(Routes.WELCOME) {
                        popUpTo(Routes.WELCOME) { inclusive = true }
                    }
                }
            )
        }

        composable(Routes.SETTINGS) {
            val settings by viewModel.settings.collectAsStateWithLifecycle()
            SettingsScreen(
                settings = settings,
                onResolutionChange = viewModel::updateResolution,
                onFpsChange = viewModel::updateFps,
                onBitrateChange = viewModel::updateBitrate,
                onDeviceAudioChange = viewModel::updateDeviceAudio,
                onBack = { navController.popBackStack() }
            )
        }
    }
}
