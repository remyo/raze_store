#!/bin/sh

set -eu

RAZE_PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$RAZE_PROJECT_DIR"

print_usage() {
  cat <<'EOF'
Run Raze Store in release mode on a connected device.

Usage:
  sh build.sh android [device-id]
  sh build.sh ios [device-id]

When exactly one matching device is connected, its ID is selected automatically.
Pass the device ID when more than one matching device is available.

Use release.sh instead when you need an APK or IPA file.
EOF
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

resolve_flutter() {
  if command -v fvm >/dev/null 2>&1; then
    RAZE_FLUTTER_KIND=fvm
    RAZE_FLUTTER_BIN=fvm
    return
  fi

  if [ -x "$RAZE_PROJECT_DIR/.fvm/flutter_sdk/bin/flutter" ]; then
    RAZE_FLUTTER_KIND=direct
    RAZE_FLUTTER_BIN="$RAZE_PROJECT_DIR/.fvm/flutter_sdk/bin/flutter"
    return
  fi

  RAZE_FVM_VERSION=$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$RAZE_PROJECT_DIR/.fvmrc" 2>/dev/null | head -n 1)
  if [ -n "$RAZE_FVM_VERSION" ]; then
    for RAZE_FLUTTER_CANDIDATE in \
      "$HOME/fvm/versions/$RAZE_FVM_VERSION/bin/flutter" \
      "$HOME/.fvm/versions/$RAZE_FVM_VERSION/bin/flutter"
    do
      if [ -x "$RAZE_FLUTTER_CANDIDATE" ]; then
        RAZE_FLUTTER_KIND=direct
        RAZE_FLUTTER_BIN="$RAZE_FLUTTER_CANDIDATE"
        return
      fi
    done
  fi

  if command -v flutter >/dev/null 2>&1; then
    RAZE_FLUTTER_KIND=direct
    RAZE_FLUTTER_BIN=$(command -v flutter)
    return
  fi

  fail 'Flutter was not found. Install FVM/Flutter and run: fvm flutter doctor'
}

run_flutter() {
  if [ "$RAZE_FLUTTER_KIND" = fvm ]; then
    fvm flutter "$@"
  else
    "$RAZE_FLUTTER_BIN" "$@"
  fi
}

if [ "${1:-}" = '--help' ] || [ "${1:-}" = '-h' ]; then
  print_usage
  exit 0
fi

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  print_usage >&2
  exit 2
fi

RAZE_PLATFORM=$1
RAZE_DEVICE_ID=${2:-}
case "$RAZE_PLATFORM" in
  android|ios) ;;
  macos) fail 'This project has no macOS target. Use "ios" for an iPhone or iPad.' ;;
  *) fail 'Platform must be "android" or "ios".' ;;
esac

resolve_flutter

command -v python3 >/dev/null 2>&1 || fail 'Python 3 is needed to select and validate the connected device.'
RAZE_DEVICE_JSON=$(run_flutter devices --machine)
RAZE_DEVICE_IDS=$(printf '%s\n' "$RAZE_DEVICE_JSON" | python3 -c '
import json
import sys

requested = sys.argv[1]
explicit_id = sys.argv[2]
devices = json.load(sys.stdin)
for device in devices:
    target = str(device.get("targetPlatform", ""))
    matches = target.startswith("android-") if requested == "android" else target == "ios"
    physical_ios = requested != "ios" or not device.get("emulator", False)
    requested_id = not explicit_id or device.get("id") == explicit_id
    if matches and physical_ios and requested_id and device.get("isSupported", True):
        print(device["id"])
' "$RAZE_PLATFORM" "$RAZE_DEVICE_ID")

RAZE_DEVICE_COUNT=$(printf '%s\n' "$RAZE_DEVICE_IDS" | awk 'NF { count++ } END { print count + 0 }')
if [ -n "$RAZE_DEVICE_ID" ]; then
  if [ "$RAZE_DEVICE_COUNT" -eq 0 ]; then
    run_flutter devices
    fail "Device '$RAZE_DEVICE_ID' is not a supported connected $RAZE_PLATFORM device. iOS release mode requires a physical device."
  fi
else
  if [ "$RAZE_DEVICE_COUNT" -eq 0 ]; then
    run_flutter devices
    fail "No supported $RAZE_PLATFORM device is connected. iOS release mode requires a physical device."
  fi
  if [ "$RAZE_DEVICE_COUNT" -gt 1 ]; then
    run_flutter devices
    fail "More than one $RAZE_PLATFORM device is connected. Run this again with a device ID."
  fi
  RAZE_DEVICE_ID=$RAZE_DEVICE_IDS
fi

printf 'Running Raze Store in release mode on %s...\n' "$RAZE_DEVICE_ID"
run_flutter run --release -d "$RAZE_DEVICE_ID"
