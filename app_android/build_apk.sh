#!/usr/bin/env bash
# =====================================================================
# build_apk.sh — Compila o APK do Dante Cast (Android) e copia o
# resultado para app_android/DanteCast.apk
#
# Requisitos (NÃO presentes nesta máquina por padrão):
#   - Android SDK (compileSdk 34/35) com ANDROID_HOME/ANDROID_SDK_ROOT
#   - JDK 17+ (Java 21 OK)
#   - gradle-wrapper.jar (regenerado pelo Android Studio ou `gradle wrapper`)
#
# Uso:
#   ./build_apk.sh            # release (assinado com a chave debug por padrão)
#   ./build_apk.sh debug      # gera o APK de debug
# =====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VARIANT="${1:-release}"

if [ "$VARIANT" = "debug" ]; then
  GRADLE_TASK=":app:assembleDebug"
  APK_PATH="app/build/outputs/apk/debug/app-debug.apk"
else
  GRADLE_TASK=":app:assembleRelease"
  APK_PATH="app/build/outputs/apk/release/app-release.apk"
fi

# Verifica o wrapper jar (necessário para ./gradlew funcionar).
if [ ! -f "gradle/wrapper/gradle-wrapper.jar" ]; then
  echo "AVISO: gradle/wrapper/gradle-wrapper.jar nao encontrado."
  echo "Gere-o com 'gradle wrapper --gradle-version 8.9' ou abra o projeto no Android Studio uma vez."
  echo "Tentando usar o 'gradle' do PATH..."
  if command -v gradle >/dev/null 2>&1; then
    gradle "$GRADLE_TASK"
  else
    echo "ERRO: nem o wrapper jar nem o 'gradle' do PATH estao disponiveis."
    exit 1
  fi
else
  ./gradlew "$GRADLE_TASK"
fi

if [ -f "$APK_PATH" ]; then
  cp "$APK_PATH" "DanteCast.apk"
  echo "OK: APK gerado em $(pwd)/DanteCast.apk"
else
  echo "ERRO: APK nao encontrado em $APK_PATH"
  exit 1
fi
