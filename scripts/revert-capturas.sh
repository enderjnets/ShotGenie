#!/bin/bash
# Deshace scripts/setup-capturas.sh: vuelve a la configuración de capturas anterior
# o, si no hay copia, a la de fábrica de macOS (Escritorio, con miniatura flotante).
set -euo pipefail
BACKUP="$HOME/Library/Application Support/ShotGenie/screencapture-antes.plist"
if [ -f "$BACKUP" ]; then
  defaults delete com.apple.screencapture 2>/dev/null || true
  defaults import com.apple.screencapture "$BACKUP"
  rm "$BACKUP"
else
  defaults delete com.apple.screencapture location 2>/dev/null || true
  defaults delete com.apple.screencapture show-thumbnail 2>/dev/null || true
fi
killall SystemUIServer 2>/dev/null || true
echo "location:       $(defaults read com.apple.screencapture location 2>/dev/null || echo '(Escritorio)')"
echo "show-thumbnail: $(defaults read com.apple.screencapture show-thumbnail 2>/dev/null || echo '(activada)')"
