#!/bin/sh

set -eu

RAZE_PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$RAZE_PROJECT_DIR"

print_usage() {
  cat <<'EOF'
Build a Raze Store release artifact.

Usage:
  sh release.sh android [version]
  sh release.sh ios [version]

Examples:
  sh release.sh android
  sh release.sh android 1.0
  sh release.sh android 1.2.3+4
  sh release.sh ios 1.2.3

The version is optional. When omitted, the version in pubspec.yaml is used.
One- and two-part versions are normalized; for example, 1.0 becomes 1.0.0.
A supplied version overrides only that build and does not edit pubspec.yaml.
If an artifact with the same version already exists, it is kept and the new
filename receives a UTC timestamp.

iOS attempts a development IPA by default and requires valid Apple signing.
Override the export method when your Apple account has the required signing
certificate and provisioning profile:
  RAZE_IOS_EXPORT_METHOD=app-store sh release.sh ios 1.2.3+4
  RAZE_IOS_EXPORT_METHOD=ad-hoc sh release.sh ios 1.2.3+4
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

choose_release_file() {
  RAZE_RELEASE_STEM=$1
  RAZE_RELEASE_EXTENSION=$2
  RAZE_RELEASE_FILE="$RAZE_RELEASE_STEM.$RAZE_RELEASE_EXTENSION"
  if [ ! -e "$RAZE_RELEASE_FILE" ]; then
    return
  fi

  RAZE_RELEASE_TIMESTAMP=$(date -u '+%Y%m%d-%H%M%S')
  RAZE_RELEASE_FILE="$RAZE_RELEASE_STEM-$RAZE_RELEASE_TIMESTAMP.$RAZE_RELEASE_EXTENSION"
  RAZE_RELEASE_COUNTER=2
  while [ -e "$RAZE_RELEASE_FILE" ]; do
    RAZE_RELEASE_FILE="$RAZE_RELEASE_STEM-$RAZE_RELEASE_TIMESTAMP-$RAZE_RELEASE_COUNTER.$RAZE_RELEASE_EXTENSION"
    RAZE_RELEASE_COUNTER=$((RAZE_RELEASE_COUNTER + 1))
  done

  printf 'An existing release with this version was kept.\n'
}

normalize_version_name() {
  RAZE_NAME_TO_NORMALIZE=$1
  if ! printf '%s\n' "$RAZE_NAME_TO_NORMALIZE" | grep -Eq '^[0-9]+(\.[0-9]+){0,2}$'; then
    fail "Invalid version '${RAZE_NAME_TO_NORMALIZE}'. Use a version such as 1.0 or 1.2.3."
  fi

  case "$RAZE_NAME_TO_NORMALIZE" in
    *.*.*) RAZE_NORMALIZED_NAME=$RAZE_NAME_TO_NORMALIZE ;;
    *.*) RAZE_NORMALIZED_NAME="$RAZE_NAME_TO_NORMALIZE.0" ;;
    *) RAZE_NORMALIZED_NAME="$RAZE_NAME_TO_NORMALIZE.0.0" ;;
  esac
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
RAZE_REQUESTED_VERSION=${2:-}
case "$RAZE_PLATFORM" in
  android|ios) ;;
  macos) fail 'This project has no macOS target. Use "ios" to create an iPhone/iPad IPA.' ;;
  *) fail 'Platform must be "android" or "ios".' ;;
esac

RAZE_CONFIGURED_VERSION=$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -n 1 | tr -d "\"'")
[ -n "$RAZE_CONFIGURED_VERSION" ] || fail 'Could not read the version from pubspec.yaml.'

case "$RAZE_CONFIGURED_VERSION" in
  *+*)
    RAZE_CONFIGURED_NAME=${RAZE_CONFIGURED_VERSION%%+*}
    RAZE_CONFIGURED_NUMBER=${RAZE_CONFIGURED_VERSION#*+}
    ;;
  *)
    RAZE_CONFIGURED_NAME=$RAZE_CONFIGURED_VERSION
    RAZE_CONFIGURED_NUMBER=1
    ;;
esac

normalize_version_name "$RAZE_CONFIGURED_NAME"
RAZE_BUILD_NAME=$RAZE_NORMALIZED_NAME
RAZE_BUILD_NUMBER=$RAZE_CONFIGURED_NUMBER
RAZE_USE_VERSION_OVERRIDE=false

if [ -n "$RAZE_REQUESTED_VERSION" ]; then
  case "$RAZE_REQUESTED_VERSION" in
    *+*)
      RAZE_REQUESTED_NAME=${RAZE_REQUESTED_VERSION%%+*}
      RAZE_REQUESTED_NUMBER=${RAZE_REQUESTED_VERSION#*+}
      ;;
    *)
      RAZE_REQUESTED_NAME=$RAZE_REQUESTED_VERSION
      RAZE_REQUESTED_NUMBER=$RAZE_CONFIGURED_NUMBER
      ;;
  esac

  normalize_version_name "$RAZE_REQUESTED_NAME"
  RAZE_BUILD_NAME=$RAZE_NORMALIZED_NAME
  RAZE_BUILD_NUMBER=$RAZE_REQUESTED_NUMBER
  RAZE_USE_VERSION_OVERRIDE=true
fi

if ! printf '%s\n' "$RAZE_BUILD_NUMBER" | grep -Eq '^[1-9][0-9]*$'; then
  fail 'The build number after "+" must be a positive integer.'
fi

RAZE_OUTPUT_DIR="$RAZE_PROJECT_DIR/outputs/releases"
mkdir -p "$RAZE_OUTPUT_DIR"
resolve_flutter

printf 'Building Raze Store %s+%s for %s...\n' \
  "$RAZE_BUILD_NAME" "$RAZE_BUILD_NUMBER" "$RAZE_PLATFORM"

if [ "$RAZE_PLATFORM" = android ]; then
  if [ "$RAZE_USE_VERSION_OVERRIDE" = true ]; then
    run_flutter build apk --release \
      "--build-name=$RAZE_BUILD_NAME" \
      "--build-number=$RAZE_BUILD_NUMBER"
  else
    run_flutter build apk --release
  fi

  RAZE_ANDROID_SOURCE="$RAZE_PROJECT_DIR/build/app/outputs/flutter-apk/app-release.apk"
  [ -f "$RAZE_ANDROID_SOURCE" ] || fail 'Flutter completed but app-release.apk was not found.'
  choose_release_file \
    "$RAZE_OUTPUT_DIR/raze-store-android-v$RAZE_BUILD_NAME-build$RAZE_BUILD_NUMBER" \
    apk
  cp "$RAZE_ANDROID_SOURCE" "$RAZE_RELEASE_FILE"

  printf '\nAPK created:\n  %s\n' "$RAZE_RELEASE_FILE"
  printf '\nWarning: the project currently uses the Android debug signing key for release builds.\n'
  printf 'This APK can be sideloaded for testing, but configure a private release key before publishing it.\n'
  exit 0
fi

RAZE_IOS_EXPORT_METHOD=${RAZE_IOS_EXPORT_METHOD:-development}
case "$RAZE_IOS_EXPORT_METHOD" in
  development|ad-hoc|app-store|enterprise) ;;
  *) fail 'RAZE_IOS_EXPORT_METHOD must be development, ad-hoc, app-store, or enterprise.' ;;
esac

RAZE_IPA_MARKER=$(mktemp "${TMPDIR:-/tmp}/raze-store-ipa.XXXXXX")
trap 'rm -f "$RAZE_IPA_MARKER"' 0 HUP INT TERM

if [ "$RAZE_USE_VERSION_OVERRIDE" = true ]; then
  run_flutter build ipa --release \
    "--build-name=$RAZE_BUILD_NAME" \
    "--build-number=$RAZE_BUILD_NUMBER" \
    "--export-method=$RAZE_IOS_EXPORT_METHOD"
else
  run_flutter build ipa --release "--export-method=$RAZE_IOS_EXPORT_METHOD"
fi

RAZE_IPA_SOURCE=$(find "$RAZE_PROJECT_DIR/build/ios/ipa" -maxdepth 1 -type f -name '*.ipa' -newer "$RAZE_IPA_MARKER" -print 2>/dev/null | head -n 1)
[ -n "$RAZE_IPA_SOURCE" ] && [ -f "$RAZE_IPA_SOURCE" ] || fail 'Flutter completed but a newly generated IPA was not found.'

choose_release_file \
  "$RAZE_OUTPUT_DIR/raze-store-ios-v$RAZE_BUILD_NAME-build$RAZE_BUILD_NUMBER" \
  ipa
cp "$RAZE_IPA_SOURCE" "$RAZE_RELEASE_FILE"

printf '\nIPA created:\n  %s\n' "$RAZE_RELEASE_FILE"
case "$RAZE_IOS_EXPORT_METHOD" in
  development)
    printf '\nThis development IPA works only on devices allowed by its provisioning profile.\n'
    ;;
  ad-hoc)
    printf '\nThis ad-hoc IPA works only on devices allowed by its distribution profile.\n'
    ;;
  app-store)
    printf '\nThis app-store IPA is for App Store Connect or TestFlight, not direct installation.\n'
    ;;
  enterprise)
    printf '\nDistribute this enterprise IPA only under your organization’s Apple program rules.\n'
    ;;
esac
printf 'For general friend testing, TestFlight is the recommended distribution method.\n'
