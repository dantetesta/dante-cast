package com.dantetesta.dantecast.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cast
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.dantetesta.dantecast.ui.theme.BrandCyan
import com.dantetesta.dantecast.ui.theme.BrandPurple
import com.dantetesta.dantecast.ui.theme.BrandPurpleDark

/**
 * Componentes visuais compartilhados entre as telas.
 */

/** Atalho conciso para ler strings de recursos dentro de Composables. */
@Composable
@ReadOnlyComposable
fun stringResOr(@StringRes id: Int): String = stringResource(id)

/** Fundo com leve gradiente da marca (usa surface quando se quer neutro). */
@Composable
fun BrandBackground(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        MaterialTheme.colorScheme.background,
                        MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f),
                        MaterialTheme.colorScheme.background
                    )
                )
            )
    ) {
        content()
    }
}

/** Logotipo circular com o ícone de cast (usado nos cabeçalhos). */
@Composable
fun BrandLogo(size: Int = 96, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.size(size.dp),
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surfaceVariant
    ) {
        Box(contentAlignment = Alignment.Center) {
            Box(
                modifier = Modifier
                    .size((size * 0.7f).dp)
                    .background(
                        Brush.linearGradient(listOf(BrandPurpleDark, BrandPurple, BrandCyan)),
                        shape = CircleShape
                    )
            )
            Icon(
                imageVector = Icons.Filled.Cast,
                contentDescription = null,
                tint = androidx.compose.ui.graphics.Color.White,
                modifier = Modifier.size((size * 0.42f).dp)
            )
        }
    }
}
