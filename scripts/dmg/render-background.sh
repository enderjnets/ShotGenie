#!/bin/bash
# Fondo del DMG (texto «Install ShotGenie / Double click the icon below») a 1x y 2x → TIFF.
# Necesita Google Chrome. El resultado se versiona en Resources/Installer/background.tiff,
# así que solo hace falta volver a ejecutarlo si cambia background.html.
set -euo pipefail
cd "$(dirname "$0")/../.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP=$(mktemp -d)
sed 's/__TITLE__/Install ShotGenie/' scripts/dmg/background.html > "$TMP/bg.html"
for s in 1 2; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=$s \
    --window-size=560,360 --screenshot="$TMP/bg@${s}x.png" "file://$TMP/bg.html" 2>/dev/null
done
tiffutil -cathidpicheck "$TMP/bg@1x.png" "$TMP/bg@2x.png" -out Resources/Installer/background.tiff
rm -rf "$TMP"
echo "Fondo: Resources/Installer/background.tiff"
