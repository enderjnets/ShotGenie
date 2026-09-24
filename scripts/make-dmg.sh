#!/bin/bash
# Instalador descargable: dist/ShotGenie-<versión>.dmg
#
# Al abrir el DMG se ve una ventana con un solo icono, «Install ShotGenie». Es una app pequeña
# que lleva ShotGenie.app dentro: con doble clic la copia a Aplicaciones y la abre.
# Necesita dmgbuild; si no está, lo instala en .build/dmgbuild-venv (Python 3).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist)
ARCHS="--arch arm64 --arch x86_64"

RELEASE=1 scripts/build.sh    # .build/app/ShotGenie.app, universal y con firma ad hoc

OUT=.build/dmg
INST="$OUT/Install ShotGenie.app"
rm -rf "$OUT" && mkdir -p "$INST/Contents/MacOS" "$INST/Contents/Resources"
swift build -c release $ARCHS --product ShotGenieInstaller
cp "$(swift build -c release $ARCHS --show-bin-path)/ShotGenieInstaller" "$INST/Contents/MacOS/"
cp Resources/Installer/Info.plist "$INST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD_NUMBER" "$INST/Contents/Info.plist"
cp -R Resources/Installer/*.lproj "$INST/Contents/Resources/"
cp .build/app/ShotGenie.app/Contents/Resources/AppIcon.icns "$INST/Contents/Resources/"
cp -R .build/app/ShotGenie.app "$INST/Contents/Resources/"
codesign --force --sign - "$INST"      # ShotGenie.app ya va firmada por dentro
codesign --verify --deep --strict "$INST"

DMGBUILD=.build/dmgbuild-venv/bin/dmgbuild
if [ ! -x "$DMGBUILD" ]; then
  python3 -m venv .build/dmgbuild-venv
  .build/dmgbuild-venv/bin/pip install --quiet dmgbuild==1.6.7
fi
mkdir -p dist
DMG="dist/ShotGenie-$VERSION.dmg"
rm -f "$DMG"
"$DMGBUILD" -s scripts/dmg/settings.py \
  -D app="$INST" -D icon="$INST/Contents/Resources/AppIcon.icns" -D background=Resources/Installer/background.tiff \
  "Install ShotGenie" "$DMG"
echo "DMG: $DMG ($(du -h "$DMG" | cut -f1))"
