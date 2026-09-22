#!/bin/bash
# Generates Resources/AppIcon.icns from Resources/icon-source.png
set -euo pipefail
cd "$(dirname "$0")"

CACHE="${TMPDIR:-/tmp}"
export XCRUN_DB_PATH="$CACHE/xcrun_db"
BINARY="$CACHE/makeicon"

if [ ! -x "$BINARY" ] || [ tools/MakeIcon.swift -nt "$BINARY" ]; then
	swiftc -swift-version 5 -module-cache-path "$CACHE/swiftcache" -O \
		-o "$BINARY" tools/MakeIcon.swift
fi

"$BINARY" Resources/icon-source.png Resources/AppIcon.icns
