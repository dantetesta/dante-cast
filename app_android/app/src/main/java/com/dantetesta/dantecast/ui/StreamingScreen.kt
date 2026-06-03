package com.dantetesta.dantecast.ui

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.dantetesta.dantecast.R
import com.dantetesta.dantecast.model.SessionState
import com.dantetesta.dantecast.model.SessionStatus
import com.dantetesta.dantecast.ui.theme.ErrorRed
import com.dantetesta.dantecast.ui.theme.SuccessGreen

/**
 * Tela de transmissão: mostra Mac conectado, resolução, fps, bitrate, tempo, latência,
 * e um grande botão STOP. Também cobre estados de conexão/erro/desconexão.
 */
@Composable
fun StreamingScreen(
    status: SessionStatus,
    onStop: () -> Unit,
    onDone: () -> Unit
) {
    BrandBackground {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            when (status.state) {
                SessionState.CONNECTING, SessionState.HANDSHAKING -> ConnectingContent(status)
                SessionState.STREAMING -> StreamingContent(status, onStop)
                SessionState.ERROR -> EndStateContent(
                    title = stringResOr(R.string.state_error),
                    message = status.errorMessage ?: "",
                    isError = true,
                    onDone = onDone
                )
                SessionState.DISCONNECTED -> EndStateContent(
                    title = stringResOr(R.string.state_disconnected),
                    message = "",
                    isError = false,
                    onDone = onDone
                )
                SessionState.IDLE -> EndStateContent(
                    title = stringResOr(R.string.state_disconnected),
                    message = "",
                    isError = false,
                    onDone = onDone
                )
            }
        }
    }
}

@Composable
private fun ColumnScope.ConnectingContent(status: SessionStatus) {
    Spacer(Modifier.height(80.dp))
    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
    Spacer(Modifier.height(24.dp))
    Text(
        if (status.state == SessionState.HANDSHAKING) stringResOr(R.string.state_handshake)
        else stringResOr(R.string.state_connecting),
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.onBackground
    )
    if (status.macName.isNotBlank()) {
        Spacer(Modifier.height(8.dp))
        Text(status.macName, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ColumnScope.StreamingContent(status: SessionStatus, onStop: () -> Unit) {
    // Indicador "ao vivo" pulsando.
    val transition = rememberInfiniteTransition(label = "live")
    val pulse by transition.animateFloat(
        initialValue = 1f,
        targetValue = 0.35f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
        label = "pulse"
    )

    Spacer(Modifier.height(12.dp))
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .size(12.dp)
                .alpha(pulse)
                .background(SuccessGreen, CircleShape)
        )
        Spacer(Modifier.width(8.dp))
        Text(
            stringResOr(R.string.stream_title),
            style = MaterialTheme.typography.headlineSmall,
            color = MaterialTheme.colorScheme.onBackground
        )
    }

    Spacer(Modifier.height(6.dp))
    Text(
        "${stringResOr(R.string.stream_connected_to)} ${status.macName}",
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.primary
    )

    Spacer(Modifier.height(28.dp))

    // Grade de métricas.
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)
    ) {
        Column(Modifier.padding(20.dp)) {
            MetricRow(stringResOr(R.string.stream_resolution), "${status.width} × ${status.height}")
            MetricRow(stringResOr(R.string.stream_fps), "${status.fps}")
            MetricRow(stringResOr(R.string.stream_bitrate), "%.1f Mbps".format(status.bitrate / 1_000_000.0))
            MetricRow(stringResOr(R.string.stream_elapsed), formatElapsed(status.elapsedMs))
            MetricRow(
                stringResOr(R.string.stream_latency),
                if (status.latencyMs >= 0) "${status.latencyMs} ms" else "—"
            )
        }
    }

    Spacer(Modifier.weight(1f))

    // Grande botão STOP.
    Button(
        onClick = onStop,
        colors = ButtonDefaults.buttonColors(containerColor = ErrorRed),
        modifier = Modifier
            .fillMaxWidth()
            .height(64.dp),
        shape = RoundedCornerShape(18.dp)
    ) {
        Icon(Icons.Filled.Stop, contentDescription = null)
        Spacer(Modifier.width(10.dp))
        Text(stringResOr(R.string.stream_stop), style = MaterialTheme.typography.titleLarge)
    }
    Spacer(Modifier.height(8.dp))
}

@Composable
private fun MetricRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface)
    }
}

@Composable
private fun ColumnScope.EndStateContent(title: String, message: String, isError: Boolean, onDone: () -> Unit) {
    Spacer(Modifier.height(80.dp))
    Text(
        title,
        style = MaterialTheme.typography.headlineSmall,
        color = if (isError) ErrorRed else MaterialTheme.colorScheme.onBackground,
        textAlign = TextAlign.Center
    )
    if (message.isNotBlank()) {
        Spacer(Modifier.height(12.dp))
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
    }
    Spacer(Modifier.weight(1f))
    Button(
        onClick = onDone,
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp)
    ) {
        Text(stringResOr(R.string.action_back), style = MaterialTheme.typography.titleMedium)
    }
}

/** Formata ms -> HH:MM:SS (ou MM:SS quando < 1h). */
private fun formatElapsed(ms: Long): String {
    val totalSec = ms / 1000
    val h = totalSec / 3600
    val m = (totalSec % 3600) / 60
    val s = totalSec % 60
    return if (h > 0) "%02d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
}
