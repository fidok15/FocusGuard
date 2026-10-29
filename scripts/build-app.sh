#!/bin/sh
# Builds dist/FocusGuard.app (ad-hoc signed). Usage: scripts/build-app.sh
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product FocusGuard
app=dist/FocusGuard.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$(swift build -c release --show-bin-path)/FocusGuard" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
cp -R Resources/en.lproj Resources/pl.lproj "$app/Contents/Resources/"
for scene in morning day sunset night; do
    # 1600 px wide is plenty for a 720 pt window on Retina.
    sips -Z 1600 -s format jpeg -s formatOptions 85 "art/scene_$scene.jpeg" --out "$app/Contents/Resources/scene_$scene.jpg" >/dev/null
done

codesign --force --sign - "$app"
echo "Built $app"
