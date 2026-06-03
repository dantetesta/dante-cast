// =====================================================================
// settings.gradle.kts — Configuração raiz do projeto Dante Cast (Android)
// pluginManagement: de onde baixar os plugins Gradle/AGP/Kotlin
// dependencyResolutionManagement: repositórios para as dependências
// =====================================================================

pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    // Falha se algum módulo declarar repositórios próprios (mantém tudo centralizado aqui)
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "DanteCast"
include(":app")
