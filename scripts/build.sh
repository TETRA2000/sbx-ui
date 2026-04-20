#!/usr/bin/env bash
set -euo pipefail

# Build sbx-ui for a specific release channel.
#
# Usage:
#   ./scripts/build.sh <channel>          # Build .app
#   ./scripts/build.sh <channel> --dmg    # Build .app + wrap in .dmg
#   ./scripts/build.sh all                # Build all channels
#   ./scripts/build.sh all --dmg          # Build all channels with .dmg
#
# Channels: canary, beta, stable
#
# Output goes to build/release/<channel>/

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$PROJECT_DIR/sbx-ui.xcodeproj"
BUILD_DIR="$PROJECT_DIR/build/release"

# Channel → scheme / configuration mapping
declare -A SCHEMES=(
  [canary]="sbx-ui Canary"
  [beta]="sbx-ui Beta"
  [stable]="sbx-ui"
)
declare -A CONFIGS=(
  [canary]="Release (Canary)"
  [beta]="Release (Beta)"
  [stable]="Release (Stable)"
)
declare -A APP_NAMES=(
  [canary]="SBX UI Canary"
  [beta]="SBX UI Beta"
  [stable]="SBX UI"
)

ALL_CHANNELS=(canary beta stable)

usage() {
  echo "Usage: $0 <canary|beta|stable|all> [--dmg]"
  exit 1
}

build_channel() {
  local channel="$1"
  local make_dmg="${2:-false}"

  local scheme="${SCHEMES[$channel]}"
  local config="${CONFIGS[$channel]}"
  local app_name="${APP_NAMES[$channel]}"
  local out_dir="$BUILD_DIR/$channel"
  local archive_path="$out_dir/$app_name.xcarchive"
  local export_path="$out_dir"

  echo "==> Building $channel channel ($app_name)"
  echo "    Scheme: $scheme"
  echo "    Configuration: $config"
  echo ""

  rm -rf "$out_dir"
  mkdir -p "$out_dir"

  # Archive
  echo "--- Archiving..."
  xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$scheme" \
    -configuration "$config" \
    -archivePath "$archive_path" \
    -destination 'generic/platform=macOS' \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=NO \
    | tail -1

  # Export .app from archive
  echo "--- Exporting .app..."
  local app_src="$archive_path/Products/Applications/$app_name.app"
  if [[ ! -d "$app_src" ]]; then
    echo "ERROR: $app_src not found in archive" >&2
    exit 1
  fi
  cp -R "$app_src" "$export_path/"

  # Optional: create .dmg
  if [[ "$make_dmg" == "true" ]]; then
    echo "--- Creating .dmg..."
    local dmg_path="$export_path/$app_name.dmg"
    hdiutil create -volname "$app_name" \
      -srcfolder "$export_path/$app_name.app" \
      -ov -format UDZO \
      "$dmg_path" \
      > /dev/null
    echo "    DMG: $dmg_path"
  fi

  # Summary
  local app_path="$export_path/$app_name.app"
  local bundle_id
  bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Contents/Info.plist")
  local version
  version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app_path/Contents/Info.plist")

  echo ""
  echo "    App:       $app_path"
  echo "    Bundle ID: $bundle_id"
  echo "    Version:   $version"
  echo ""
}

# --- Main ---

[[ $# -lt 1 ]] && usage

channel="$1"
make_dmg="false"
[[ "${2:-}" == "--dmg" ]] && make_dmg="true"

if [[ "$channel" == "all" ]]; then
  for ch in "${ALL_CHANNELS[@]}"; do
    build_channel "$ch" "$make_dmg"
  done
  echo "==> All channels built in $BUILD_DIR/"
elif [[ -n "${SCHEMES[$channel]+x}" ]]; then
  build_channel "$channel" "$make_dmg"
else
  echo "Unknown channel: $channel"
  usage
fi
