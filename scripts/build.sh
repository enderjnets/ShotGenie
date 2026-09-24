#!/bin/bash
# Compila ShotGenie y la instala en ~/Applications/ShotGenie.app.
#
# Firma: con SIGN_IDENTITY (nombre de un certificado de firma de código del llavero) la firma es
# estable y macOS conserva el permiso de Accesibilidad entre compilaciones. Sin él, firma ad hoc
# y el permiso hay que volver a darlo tras cada compilación. Se puede fijar en scripts/local.env.
set -euo pipefail
cd "$(dirname "$0")/.."
# RELEASE=1: versión para publicar (universal, firma ad hoc, sin instalar); no usa local.env.
if [ -n "${RELEASE:-}" ]; then NO_INSTALL=1; SIGN_IDENTITY=""; ARCHS="--arch arm64 --arch x86_64"
elif [ -f scripts/local.env ]; then source scripts/local.env; fi
ARCHS=${ARCHS:-}

BUILD=.build/app
APP="$BUILD/ShotGenie.app"
DEST="$HOME/Applications/ShotGenie.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist)

swift build -c release $ARCHS
rm -rf "$BUILD" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Icono de la app desde el SVG
swiftc -O scripts/make-icon/main.swift -o "$BUILD/make-icon"
"$BUILD/make-icon" Resources/AppIcon.svg "$BUILD/AppIcon.iconset"
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

cp "$(swift build -c release $ARCHS --show-bin-path)/ShotGenie" "$APP/Contents/MacOS/ShotGenie"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"   # traducciones: macOS elige según el idioma del sistema

IDENTITY=""
if [ -n "${SIGN_IDENTITY:-}" ]; then
  IDENTITY=$(security find-identity -p codesigning 2>/dev/null | awk -v n="\"$SIGN_IDENTITY\"" 'index($0, n) {print $2; exit}')
  [ -z "$IDENTITY" ] && echo "Aviso: no encuentro el certificado «$SIGN_IDENTITY»; firma ad hoc"
fi
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi

# NO_INSTALL=1: solo deja la app en .build/app (lo usa scripts/docs/render.sh)
if [ -n "${NO_INSTALL:-}" ]; then echo "Compilada: $APP"; exit 0; fi

# Cierra la copia en marcha antes de reemplazarla
osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
sleep 1
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "Instalada: $DEST"
