#!/bin/zsh
# Crea build/AssistenteMac.app a partire dal pacchetto Swift.
# Uso: ./scripts/crea-app.sh            (release)
#      CONFIG=debug ./scripts/crea-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${CONFIG:-release}
BUNDLE_ID=${BUNDLE_ID:-com.alexcastellano.AssistenteMac}
VERSION=${VERSION:-0.1.0}
APP="build/Mac Assistant.app"

swift build -c "$CONFIG" --product AssistenteMac
BIN=$(swift build -c "$CONFIG" --show-bin-path)/AssistenteMac

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AssistenteMac"
# Icona (rigenerabile con: swift scripts/crea-icona.swift).
cp Risorse/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Risorse del nucleo (pacchetti lingua).
cp -R "$(dirname "$BIN")/AssistenteMac_AssistenteCore.bundle" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Mac Assistant</string>
    <key>CFBundleDisplayName</key><string>Mac Assistant</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>AssistenteMac</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleDevelopmentRegion</key><string>it</string>
    <key>CFBundleLocalizations</key><array><string>it</string><string>en</string></array>
    <key>LSMinimumSystemVersion</key><string>27.0</string>
    <key>LSArchitecturePriority</key><array><string>arm64</string></array>
    <!-- Permessi (macOS li chiede la prima volta) -->
    <key>NSMicrophoneUsageDescription</key>
    <string>Mac Assistant usa il microfono solo quando premi il pulsante per fare una domanda a voce. L'audio resta sul tuo Mac.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Mac Assistant trasforma la tua voce in testo direttamente sul Mac, senza inviarla a nessuno.</string>
    <!-- Solo barra dei menu: niente icona nel Dock -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Descrizioni dei permessi nelle lingue disponibili (macOS sceglie quella del Mac).
mkdir -p "$APP/Contents/Resources/it.lproj" "$APP/Contents/Resources/en.lproj"
cat > "$APP/Contents/Resources/it.lproj/InfoPlist.strings" <<STRINGS
"NSMicrophoneUsageDescription" = "Mac Assistant usa il microfono solo quando premi il pulsante per fare una domanda a voce. L'audio resta sul tuo Mac.";
"NSSpeechRecognitionUsageDescription" = "Mac Assistant trasforma la tua voce in testo direttamente sul Mac, senza inviarla a nessuno.";
STRINGS
cat > "$APP/Contents/Resources/en.lproj/InfoPlist.strings" <<STRINGS
"NSMicrophoneUsageDescription" = "Mac Assistant uses the microphone only when you press the button to ask a question by voice. The audio stays on your Mac.";
"NSSpeechRecognitionUsageDescription" = "Mac Assistant turns your voice into text right on your Mac, without sending it to anyone.";
STRINGS

# Firma ad-hoc (locale). Per la distribuzione servirà una firma Developer ID.
codesign --force --sign - "$APP"
echo "Creato: $APP"
