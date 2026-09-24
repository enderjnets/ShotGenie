#!/bin/bash
# Regenera las imágenes del README (docs/) con capturas de ejemplo; no usa tus capturas.
# Necesita Google Chrome (para fotografiar las páginas de ejemplo) y ffmpeg (para el GIF).
set -euo pipefail
cd "$(dirname "$0")/../.."
TMP=$(mktemp -d)
NO_INSTALL=1 scripts/build.sh >/dev/null
scripts/docs/make-demo-captures.sh "$TMP/captures" >/dev/null
# En inglés y con la lupa por defecto, sin tocar las preferencias guardadas (argumentos = dominio volátil)
.build/app/ShotGenie.app/Contents/MacOS/ShotGenie --render-docs "$TMP/captures" "$TMP/out" -AppleLanguages "(en)" -magnification 4.2
cp "$TMP/out/icon-states.png" "$TMP/out/fan.png" "$TMP/out/settings.png" docs/
# GIF a 20 fps con paleta propia (sin bandas en el fondo); el último fotograma se queda 2 s
ffmpeg -v error -y -framerate 20 -i "$TMP/out/genie-frames/%03d.png" \
  -vf "tpad=stop_mode=clone:stop_duration=2,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  -loop 0 docs/genie.gif
rm -rf "$TMP"
ls -la docs
