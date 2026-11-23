#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Build a release: test, build the app, zip it, stamp the cask's sha256.
# Afterwards: attach ClaudeSwap.zip to a GitHub release tagged v<version> and copy
# packaging/claude-swap-bar.rb into the tap as Casks/claude-swap-bar.rb.

# The version lives in three places; refuse to build if they disagree.
CODE="$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/SwapCore/Settings.swift)"
PLIST="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)"
CASK="$(sed -n 's/^  version "\(.*\)"/\1/p' packaging/claude-swap-bar.rb)"
if [ "$CODE" != "$PLIST" ] || [ "$CODE" != "$CASK" ]; then
  echo "version mismatch: code=$CODE Info.plist=$PLIST cask=$CASK" >&2
  exit 1
fi

swift test
./packaging/make-app.sh

rm -f ClaudeSwap.zip
# ditto keeps the code signature intact.
ditto -c -k --sequesterRsrc --keepParent "Claude Swap.app" ClaudeSwap.zip

SHA="$(shasum -a 256 ClaudeSwap.zip | awk '{print $1}')"
/usr/bin/sed -i '' -E "s|sha256 \"[a-f0-9]*\"|sha256 \"${SHA}\"|" packaging/claude-swap-bar.rb

echo "Built ClaudeSwap.zip ($(ls -lh ClaudeSwap.zip | awk '{print $5}')), sha256 ${SHA}"
echo "Next:"
echo "  gh release create v${CODE} ClaudeSwap.zip -R mafex11/claude-swap-bar --title \"Claude Swap ${CODE}\" --notes ..."
echo "  cp packaging/claude-swap-bar.rb ../homebrew-tap/Casks/claude-swap-bar.rb"
