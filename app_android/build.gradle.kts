// =====================================================================
// build.gradle.kts (raiz) — declara as versões dos plugins com `apply false`.
// Os módulos (ex.: :app) aplicam os plugins que precisam.
// AGP 8.6.x + Kotlin 2.0.x + Compose Compiler Plugin (obrigatório no Kotlin 2.0)
// =====================================================================

plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}
