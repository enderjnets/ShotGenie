#!/bin/bash
# Genera 5 capturas de ejemplo (páginas HTML de demo/ fotografiadas con Chrome sin ventana),
# con fechas de hace pocos minutos, para las imágenes del README. Uso: make-demo-captures.sh <carpeta>
set -euo pipefail
cd "$(dirname "$0")"
OUT="$1"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
rm -rf "$OUT" && mkdir -p "$OUT"
# de la más vieja a la más nueva: página, minutos atrás
pages=(3-dashboard:38 2-terminal:21 1-editor:9 5-notes:3 4-landing:0)
for entry in "${pages[@]}"; do
  page=${entry%%:*}; ago=${entry##*:}
  stamp=$(date -v-"${ago}"M +%Y%m%d%H%M.%S)
  name="Screenshot $(date -v-"${ago}"M "+%Y-%m-%d at %-I.%M.%S %p").png"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size=1440,900 --screenshot="$OUT/$name" "file://$PWD/demo/$page.html" >/dev/null 2>&1
  touch -t "$stamp" "$OUT/$name"
done
ls "$OUT"
