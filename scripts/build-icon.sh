#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

icon_source="$PWD/Resources/AppIcon.png"
iconset_path="$PWD/.build/icons/AppIcon.iconset"
icon_path="$PWD/.build/icons/AppIcon.icns"
mkdir -p "$iconset_path"

# Keep the source artwork intact; macOS produces the standard 1x/2x variants.
for size in 16 32 128 256 512; do
    /usr/bin/sips --resampleHeightWidth "$size" "$size" "$icon_source" \
        --out "$iconset_path/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    /usr/bin/sips --resampleHeightWidth "$retina_size" "$retina_size" "$icon_source" \
        --out "$iconset_path/icon_${size}x${size}@2x.png" >/dev/null
done

/usr/bin/iconutil --convert icns --output "$icon_path" "$iconset_path"
printf 'Generated app icon: %s\n' "$icon_path"
