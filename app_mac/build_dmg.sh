#!/usr/bin/env bash
#
# build_dmg.sh — Compila o Dante Cast (macOS) SEM Xcode e empacota em DanteCast.dmg
#
# Requisitos: Swift command-line toolchain (swiftc), hdiutil, codesign, sips, iconutil.
# Alvo: arm64 (Apple Silicon), macOS 13+.
#
# Etapas:
#   1) compila todas as fontes Swift em um executável otimizado;
#   2) monta DanteCast.app/Contents/{MacOS,Info.plist,Resources};
#   3) gera ícone programaticamente (best-effort; não quebra o build se falhar);
#   4) ad-hoc codesign;
#   5) cria DanteCast.dmg (read-only) com a app + symlink p/ /Applications.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="DanteCast"
APP_DISPLAY="Dante Cast"
BUNDLE_ID="com.dantetesta.dantecast.mac"
MIN_MACOS="13.0"
TARGET="arm64-apple-macosx${MIN_MACOS}"

# Constrói em um diretório temporário FORA do Desktop. A pasta Desktop pode estar
# sincronizada (iCloud/fileprovider) e injetar xattrs com.apple.FinderInfo que
# fazem o codesign --strict reclamar de "detritus". O DMG final é copiado de volta.
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dantecast_build.XXXXXX")"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RES_DIR="${CONTENTS}/Resources"
DMG_PATH="${ROOT}/${APP_NAME}.dmg"
DMG_STAGING="${BUILD_DIR}/dmg_staging"

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

echo "==> Dante Cast — build (no Xcode)"
echo "    SDK:    ${SDK_PATH}"
echo "    Target: ${TARGET}"

# ---------------------------------------------------------------------------
# 0) Limpa diretórios de build
# ---------------------------------------------------------------------------
# Garante limpeza do diretório temporário ao sair.
trap 'rm -rf "${BUILD_DIR}"' EXIT
mkdir -p "${MACOS_DIR}" "${RES_DIR}" "${DMG_STAGING}"

# ---------------------------------------------------------------------------
# 1) Compila as fontes Swift
# ---------------------------------------------------------------------------
echo "==> Compilando fontes Swift…"
SOURCES=$(find "${ROOT}/Sources/DanteCast" -name '*.swift' | sort)
if [ -z "${SOURCES}" ]; then
  echo "ERRO: nenhuma fonte Swift encontrada em Sources/DanteCast" >&2
  exit 1
fi

xcrun --sdk macosx swiftc \
  -O \
  -target "${TARGET}" \
  -sdk "${SDK_PATH}" \
  -framework SwiftUI \
  -framework AppKit \
  -framework AVFoundation \
  -framework VideoToolbox \
  -framework CoreMedia \
  -framework CoreVideo \
  -framework CoreImage \
  -framework Network \
  ${SOURCES} \
  -o "${MACOS_DIR}/${APP_NAME}"

echo "    Executável: ${MACOS_DIR}/${APP_NAME}"

# ---------------------------------------------------------------------------
# 2) Ícone (best-effort) — desenha um PNG simples e gera .icns
# ---------------------------------------------------------------------------
echo "==> Gerando ícone (best-effort)…"
generate_icon() {
  local tmp_png="${BUILD_DIR}/icon_1024.png"
  local iconset="${BUILD_DIR}/AppIcon.iconset"

  # Desenha um PNG 1024x1024 com Swift+CoreGraphics (gradiente + glifo).
  cat > "${BUILD_DIR}/makeicon.swift" <<'SWIFT'
import AppKit
let size = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
// Fundo com gradiente roxo->azul (identidade "cast").
let grad = NSGradient(colors: [
    NSColor(calibratedRed: 0.36, green: 0.20, blue: 0.86, alpha: 1),
    NSColor(calibratedRed: 0.16, green: 0.52, blue: 0.96, alpha: 1)
])!
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let path = NSBezierPath(roundedRect: rect, xRadius: 220, yRadius: 220)
path.addClip()
grad.draw(in: rect, angle: -45)
// Símbolo de "cast" (arcos + ponto), em branco.
NSColor.white.setStroke()
let cx: CGFloat = 320, cy: CGFloat = 300
for (i, r) in [180.0, 320.0, 460.0].enumerated() {
    let p = NSBezierPath()
    p.lineWidth = 46 - CGFloat(i) * 4
    p.lineCapStyle = .round
    p.appendArc(withCenter: NSPoint(x: cx, y: cy),
                radius: r, startAngle: 0, endAngle: 90)
    p.stroke()
}
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: cx - 46, y: cy - 46, width: 92, height: 92)).fill()
img.unlockFocus()
guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

  if xcrun --sdk macosx swiftc -O -target "${TARGET}" -sdk "${SDK_PATH}" \
        "${BUILD_DIR}/makeicon.swift" -o "${BUILD_DIR}/makeicon" 2>/dev/null \
     && "${BUILD_DIR}/makeicon" "${tmp_png}" 2>/dev/null \
     && [ -f "${tmp_png}" ]; then
    mkdir -p "${iconset}"
    for s in 16 32 64 128 256 512 1024; do
      sips -z $s $s "${tmp_png}" --out "${iconset}/icon_${s}x${s}.png" >/dev/null 2>&1 || true
    done
    # Versões @2x.
    sips -z 32 32     "${tmp_png}" --out "${iconset}/icon_16x16@2x.png"   >/dev/null 2>&1 || true
    sips -z 64 64     "${tmp_png}" --out "${iconset}/icon_32x32@2x.png"   >/dev/null 2>&1 || true
    sips -z 256 256   "${tmp_png}" --out "${iconset}/icon_128x128@2x.png" >/dev/null 2>&1 || true
    sips -z 512 512   "${tmp_png}" --out "${iconset}/icon_256x256@2x.png" >/dev/null 2>&1 || true
    sips -z 1024 1024 "${tmp_png}" --out "${iconset}/icon_512x512@2x.png" >/dev/null 2>&1 || true
    cp "${iconset}/icon_512x512@2x.png" "${iconset}/icon_512x512.png" 2>/dev/null || true
    cp "${iconset}/icon_256x256.png"    "${iconset}/icon_256x256.png" 2>/dev/null || true
    if iconutil -c icns "${iconset}" -o "${RES_DIR}/AppIcon.icns" 2>/dev/null; then
      echo "    Ícone gerado: AppIcon.icns"
      return 0
    fi
  fi
  echo "    (aviso) Falha ao gerar ícone — seguindo sem ícone."
  return 0
}
generate_icon || true

HAS_ICON="false"
[ -f "${RES_DIR}/AppIcon.icns" ] && HAS_ICON="true"

# ---------------------------------------------------------------------------
# 3) Info.plist
# ---------------------------------------------------------------------------
echo "==> Escrevendo Info.plist…"
ICON_ENTRY=""
if [ "${HAS_ICON}" = "true" ]; then
  ICON_ENTRY="	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>"
fi

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>${APP_DISPLAY}</string>
	<key>CFBundleDisplayName</key>
	<string>${APP_DISPLAY}</string>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleVersion</key>
	<string>1.0</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>LSMinimumSystemVersion</key>
	<string>${MIN_MACOS}</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>NSLocalNetworkUsageDescription</key>
	<string>O Dante Cast recebe o vídeo do seu Android pela rede local.</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>O Dante Cast usa o microfone para gravar narração junto com o espelhamento (opcional).</string>
${ICON_ENTRY}
</dict>
</plist>
PLIST

# Valida o plist.
plutil -lint "${CONTENTS}/Info.plist" >/dev/null

# PkgInfo (opcional, mas tradicional).
printf 'APPL????' > "${CONTENTS}/PkgInfo"

# ---------------------------------------------------------------------------
# 4) Ad-hoc codesign
# ---------------------------------------------------------------------------
echo "==> Assinando (ad-hoc)…"
# Remove resource forks / atributos estendidos (sips/Finder podem deixar detritos
# que impedem o codesign --strict).
xattr -cr "${APP_BUNDLE}" 2>/dev/null || true
find "${APP_BUNDLE}" -name '.DS_Store' -delete 2>/dev/null || true
codesign -s - --force --deep "${APP_BUNDLE}"
if codesign --verify --deep --strict "${APP_BUNDLE}" 2>/dev/null; then
  echo "    Assinatura ad-hoc OK (strict)"
else
  echo "    (aviso) verificação strict retornou aviso (esperado fora de Xcode)"
fi

# ---------------------------------------------------------------------------
# 5) DMG
# ---------------------------------------------------------------------------
echo "==> Criando DMG…"
rm -f "${DMG_PATH}"
cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

hdiutil create \
  -volname "${APP_DISPLAY}" \
  -srcfolder "${DMG_STAGING}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" >/dev/null

echo ""
echo "==> Concluído!"
echo "    DMG: ${DMG_PATH}"
echo "    (o .app foi montado dentro do DMG; build temporário será limpo)"
ls -la "${DMG_PATH}"
