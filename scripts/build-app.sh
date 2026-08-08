#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
cd "$project_dir"

mkdir -p \
  "$project_dir/.build/clang-module-cache" \
  "$project_dir/.build/swiftpm-module-cache"

CLANG_MODULE_CACHE_PATH="$project_dir/.build/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/swiftpm-module-cache" \
swift build -c release --disable-sandbox

app_dir="$project_dir/dist/OpenType.app"
contents_dir="$app_dir/Contents"
binary_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"

mkdir -p "$binary_dir" "$resources_dir"
cp "$project_dir/.build/release/OpenType" "$binary_dir/OpenType"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
rm -rf "$resources_dir/Sounds"
ditto "$project_dir/Resources/Sounds" "$resources_dir/Sounds"
rm -rf "$resources_dir/en.lproj"
ditto \
  "$project_dir/Resources/Localization/en.lproj" \
  "$resources_dir/en.lproj"
chmod +x "$binary_dir/OpenType"

# Files received through WeChat can leave a quarantine attribute on the
# workspace. A locally rebuilt app must not inherit that download quarantine,
# otherwise Finder may refuse to launch an otherwise valid ad-hoc build.
xattr -dr com.apple.quarantine "$app_dir" 2>/dev/null || true

# Keep a stable designated requirement across local ad-hoc builds. Without an
# explicit requirement, macOS may bind TCC permissions to a changing code hash
# and ask for Microphone / Accessibility access again after every rebuild.
codesign \
  --force \
  --deep \
  --sign - \
  --requirements '=designated => identifier "ai.rain.opentype"' \
  "$app_dir"
echo "$app_dir"
