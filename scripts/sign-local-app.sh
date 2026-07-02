#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <app-path> <identity-name> [entitlements-path]" >&2
  exit 64
fi

APP_PATH="$1"
IDENTITY="$2"
ENTITLEMENTS_PATH="${3:-}"

if [ ! -d "$APP_PATH" ]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 66
fi

if ! security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$IDENTITY\"" >/dev/null; then
  echo "Code signing identity not found: $IDENTITY" >&2
  echo "Run: make local-signing-cert" >&2
  exit 69
fi

echo "Signing $APP_PATH with: $IDENTITY"

# Xcode's Debug local build may still produce ad-hoc nested code. Re-sign the
# full bundle first, then apply the app entitlements to the top-level bundle.
codesign \
  --force \
  --deep \
  --sign "$IDENTITY" \
  --timestamp=none \
  --preserve-metadata=identifier,entitlements,flags \
  "$APP_PATH"

TOP_LEVEL_SIGN_ARGS=(
  --force
  --sign "$IDENTITY"
  --timestamp=none
)

if [ -n "$ENTITLEMENTS_PATH" ]; then
  if [ ! -f "$ENTITLEMENTS_PATH" ]; then
    echo "Entitlements file not found: $ENTITLEMENTS_PATH" >&2
    exit 66
  fi
  TOP_LEVEL_SIGN_ARGS+=(--entitlements "$ENTITLEMENTS_PATH")
fi

codesign "${TOP_LEVEL_SIGN_ARGS[@]}" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Signed and verified: $APP_PATH"
