#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Build "Claude Swap.app": a universal (Apple Silicon + Intel) release binary in a
# bundle, signed ad hoc.

swift build -c release --arch arm64 --arch x86_64

APP="Claude Swap.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/apple/Products/Release/ClaudeSwap "$APP/Contents/MacOS/ClaudeSwap"
cp packaging/Info.plist "$APP/Contents/Info.plist"

[ -f packaging/AppIcon.icns ] || ./packaging/make-icon.sh
cp packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad hoc signature: enough to run locally and for login-item registration.
codesign --force --sign - "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/ClaudeSwap"))"
