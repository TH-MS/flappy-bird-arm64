# Flappy64 – 64-bit (arm64-v8a) Godot 4 port of Flappy Bird 1.3

1. `tools/extract_assets.sh Flappy_Bird_1.3.apk`   (copies atlas + sounds, regenerates `scripts/Atlas.gd`)
2. Open in Godot 4.4+ and press Play. Without the extracted art it runs with flat-colour placeholders.
3. Tests: `godot --headless --path . -s tests/test_all.gd`

The original art/sound are the property of their owner; swap in your own before distributing.
