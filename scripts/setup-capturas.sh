#!/bin/bash
# Opcional. Guarda las capturas de macOS en ~/Pictures/ScreenCaptures y apaga la miniatura flotante
# (con ella, macOS no escribe el archivo hasta que la miniatura desaparece, unos 5 s, y ShotGenie
# llega tarde). Guarda la configuración anterior para poder deshacerlo: scripts/revert-capturas.sh
set -euo pipefail
BACKUP="$HOME/Library/Application Support/ShotGenie/screencapture-antes.plist"
mkdir -p "$(dirname "$BACKUP")"
[ -f "$BACKUP" ] || defaults export com.apple.screencapture "$BACKUP"
mkdir -p "$HOME/Pictures/ScreenCaptures"
defaults write com.apple.screencapture location "$HOME/Pictures/ScreenCaptures"
defaults write com.apple.screencapture show-thumbnail -bool false
killall SystemUIServer 2>/dev/null || true
echo "location:       $(defaults read com.apple.screencapture location)"
echo "show-thumbnail: $(defaults read com.apple.screencapture show-thumbnail)"
