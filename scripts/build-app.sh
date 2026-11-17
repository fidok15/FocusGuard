#!/bin/sh
# Builds dist/FocusGuard.app (ad-hoc signed). Usage: scripts/build-app.sh
set -eu
cd "$(dirname "$0")/.."

# One binary for Apple silicon and Intel Macs.
arch="--arch arm64 --arch x86_64"
swift build -c release --product FocusGuard $arch
app=dist/FocusGuard.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$(swift build -c release $arch --show-bin-path)/FocusGuard" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
cp Resources/AppIcon.icns Resources/rain.m4a "$app/Contents/Resources/"
cp -R Resources/en.lproj Resources/pl.lproj "$app/Contents/Resources/"
# The scenes are already 2000 px wide RGBA PNGs (transparent cut-out), so they ship as they are.
for scene in morning day sunset night rain; do
    cp "art/scene_$scene.png" "$app/Contents/Resources/"
done

# Hardened runtime, still ad-hoc signed: only the camera and Apple events (Spotify) are allowed, nothing else.
codesign --force --options runtime --entitlements Resources/FocusGuard.entitlements --sign - "$app"
echo "Built $app"
