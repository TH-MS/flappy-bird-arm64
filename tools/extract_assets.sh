#!/usr/bin/env bash
# Usage: tools/extract_assets.sh /path/to/Flappy_Bird_1.3.apk
# Unpacks the APK you own into _apk/ and copies the atlas + sounds into the Godot project.
set -euo pipefail
APK="${1:?usage: $0 path/to/Flappy_Bird_1.3.apk}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
rm -rf "$HERE/_apk" && mkdir -p "$HERE/_apk" "$HERE/assets/gfx" "$HERE/assets/audio"

unzip -q -o "$APK" -d "$HERE/_apk"           # an APK is a zip; assets/ and res/raw are stored as-is
cp "$HERE/_apk/assets/gfx/atlas.png"        "$HERE/assets/gfx/atlas.png"      # 1024x1024 RGBA sprite sheet
cp "$HERE/_apk/assets/sounds/"*.ogg         "$HERE/assets/audio/"             # Ogg Vorbis, 44.1 kHz
cp "$HERE/_apk/res/drawable/splash.png"     "$HERE/assets/gfx/splash.png"     # 640x1136 ".GEARS" splash
# sprite rectangles (UV format) live in res/raw/atlas.txt -> regenerate the Godot table:
python3 "$HERE/tools/gen_atlas.py" "$HERE/_apk/res/raw/atlas.txt" "$HERE/scripts/Atlas.gd"

# Optional extras (not needed to build the port):
#   apktool d "$APK" -o "$HERE/_apktool"      # decoded manifest/resources
#   jadx -d "$HERE/_src" "$APK"               # decompiled Java: com/dotgears/flappy/{a,c}.java hold the game logic
echo "Done. Open the project in Godot 4.4+ (first open imports the assets)."
