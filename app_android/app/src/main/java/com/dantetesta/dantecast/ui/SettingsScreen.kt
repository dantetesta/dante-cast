package com.dantetesta.dantecast.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.dantetesta.dantecast.R
import com.dantetesta.dantecast.model.BitratePresets
import com.dantetesta.dantecast.model.Fps
import com.dantetesta.dantecast.model.Resolution
import com.dantetesta.dantecast.model.StreamSettings

/**
 * Tela de configurações: resolução (720p/1080p/nativa), fps (30/60) e bitrate (Mbps).
 * Persistido via DataStore (callbacks chamam o ViewModel).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    settings: StreamSettings,
    onResolutionChange: (Resolution) -> Unit,
    onFpsChange: (Fps) -> Unit,
    onBitrateChange: (Int) -> Unit,
    onBack: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResOr(R.string.settings_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResOr(R.string.action_back))
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 20.dp)
                .verticalScroll(rememberScrollState())
        ) {
            Spacer(Modifier.height(8.dp))

            // ---- Resolução ----
            SectionTitle(stringResOr(R.string.settings_resolution))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ChoiceChip(stringResOr(R.string.settings_res_720), settings.resolution == Resolution.HD720) {
                    onResolutionChange(Resolution.HD720)
                }
                ChoiceChip(stringResOr(R.string.settings_res_1080), settings.resolution == Resolution.HD1080) {
                    onResolutionChange(Resolution.HD1080)
                }
                ChoiceChip(stringResOr(R.string.settings_res_native), settings.resolution == Resolution.NATIVE) {
                    onResolutionChange(Resolution.NATIVE)
                }
            }

            Spacer(Modifier.height(24.dp))

            // ---- FPS ----
            SectionTitle(stringResOr(R.string.settings_fps))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ChoiceChip("30 fps", settings.fps == Fps.FPS30) { onFpsChange(Fps.FPS30) }
                ChoiceChip("60 fps", settings.fps == Fps.FPS60) { onFpsChange(Fps.FPS60) }
            }

            Spacer(Modifier.height(24.dp))

            // ---- Bitrate ----
            // Valor inicial do slider: bitrate atual (Mbps) ou um padrão coerente.
            val currentMbps = if (settings.bitrate > 0) settings.bitrate / 1_000_000f else 6f
            var sliderValue by remember(settings.bitrate) { mutableFloatStateOf(currentMbps) }

            SectionTitle("${stringResOr(R.string.settings_bitrate)}: ${"%.1f".format(sliderValue)} Mbps")
            Slider(
                value = sliderValue,
                onValueChange = { sliderValue = it },
                onValueChangeFinished = {
                    onBitrateChange((sliderValue * 1_000_000).toInt())
                },
                valueRange = (BitratePresets.MIN_BITRATE / 1_000_000f)..(BitratePresets.MAX_BITRATE / 1_000_000f),
                modifier = Modifier.fillMaxWidth()
            )
            Text(
                "Maior bitrate = mais qualidade e mais uso de rede.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(Modifier.height(32.dp))
        }
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.onBackground,
        modifier = Modifier.padding(bottom = 12.dp)
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ChoiceChip(label: String, selected: Boolean, onClick: () -> Unit) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(label) },
        colors = FilterChipDefaults.filterChipColors(
            selectedContainerColor = MaterialTheme.colorScheme.primary,
            selectedLabelColor = MaterialTheme.colorScheme.onPrimary
        ),
        modifier = Modifier.height(40.dp)
    )
}
