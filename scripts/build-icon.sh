#!/bin/zsh
# Package the approved raster artwork into the full native macOS icon set.
set -euo pipefail
project_dir=${0:A:h:h}
icon_source="$project_dir/Resources/AppIconSource.png"
icon_build=$(mktemp -d /tmp/opentype-icon.XXXXXX)
icon_set="$icon_build/OpenType.iconset"
mkdir -p "$icon_set"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$icon_source" --out "$icon_set/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$icon_source" --out "$icon_set/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_set" -o "$project_dir/Resources/AppIcon.icns"
echo "$project_dir/Resources/AppIcon.icns"
