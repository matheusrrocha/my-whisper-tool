#!/bin/bash
# Builds WhisperFlow.app into build/ from the SwiftPM binary.
set -euo pipefail
cd "$(dirname "$0")/.."

# The macOS 27 beta Command Line Tools ship a broken SwiftPM manifest library;
# prefer the Homebrew toolchain (brew install swift) when present.
SWIFT=swift
if [ -x /opt/homebrew/opt/swift/bin/swift ]; then
  SWIFT=/opt/homebrew/opt/swift/bin/swift
fi

"$SWIFT" build -c release

APP="build/WhisperFlow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/WhisperFlow "$APP/Contents/MacOS/WhisperFlow"
cp scripts/Info.plist "$APP/Contents/Info.plist"

# Prefer the stable self-signed identity (scripts/make-signing-cert.sh) so
# Accessibility/Microphone grants survive rebuilds. Fall back to ad-hoc, where
# every rebuild requires re-granting Accessibility.
IDENTITY="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "WhisperFlow Signing"; then
  IDENTITY="WhisperFlow Signing"
fi
codesign --force --sign "$IDENTITY" "$APP"

echo
echo "Built $APP (signed: $IDENTITY)"
echo "Run it with: open $APP"
