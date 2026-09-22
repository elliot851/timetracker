#!/bin/bash
# Builds TimeTracker.app from the Swift sources in this folder.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/TimeTracker.app"
CACHE="${TMPDIR:-/tmp}"
export XCRUN_DB_PATH="$CACHE/xcrun_db"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc \
	-swift-version 5 \
	-target "$(uname -m)-apple-macos14.0" \
	-module-cache-path "$CACHE/swiftcache" \
	-O \
	-o "$APP/Contents/MacOS/TimeTracker" \
	Sources/*.swift

./make-icon.sh
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"

# Prefer the stable self-signed identity (set up via ./setup-signing.sh) so the
# Screen Recording grant survives rebuilds. Fall back to ad-hoc if it is missing.
IDENTITY="TimeTracker Dev"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
	codesign --force --sign "$IDENTITY" "$APP"
	echo "Signerad med \"$IDENTITY\"."
else
	codesign --force --sign - "$APP"
	echo "Ad-hoc-signerad (kör ./setup-signing.sh för en stabil identitet)."
fi

echo "Byggd: $(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"

# Install into /Applications so the app can be opened by double-click without commands.
# The stable signature means the Screen Recording grant carries over to this copy.
INSTALLED="/Applications/TimeTracker.app"
if [ -w /Applications ] || [ ! -e "$INSTALLED" ]; then
	pkill -x TimeTracker 2>/dev/null || true
	rm -rf "$INSTALLED"
	cp -R "$APP" "$INSTALLED"
	echo "Installerad: $INSTALLED"
else
	echo "Kunde inte skriva till /Applications — kopiera dit manuellt en gång."
fi
