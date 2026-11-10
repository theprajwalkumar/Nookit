#!/usr/bin/env bash
# Build Nookit.app directly with swiftc.
#
# Why not `swift build`? The Command Line Tools installed on the current machine
# ship a PackageDescription module whose private .swiftinterface is newer than
# the compiler expects, so *every* SwiftPM manifest fails to link before any app
# code is compiled. Compiling the sources directly avoids SwiftPM entirely and
# still produces a normal, double-clickable .app bundle.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP="build/Nookit.app"
BIN="build/nookit"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos14.0"

# Pick an SDK whose SwiftUI can actually compile here. The Command Line Tools
# on this machine ship SDK 27.2, whose SwiftUI declares @State (and friends) as
# macros whose plugin (SwiftUIMacros) is missing from the same toolchain. That
# makes every SwiftUI file fail with "plugin for module 'SwiftUIMacros' not
# found". Probe candidate SDKs and use the newest one that compiles a @State
# view, falling back to the default SDK if none pass.
SDK="$(xcrun --show-sdk-path)"
PROBE_DIR="$(mktemp -d)"
cat > "$PROBE_DIR/probe.swift" <<'EOF'
import SwiftUI
struct _NookitSDKProbe: View {
    @State private var value = 0
    var body: some View { Text("\(value)") }
}
EOF
sdk_compiles() {
  swiftc -parse-as-library -swift-version 5 -target "$TARGET" -sdk "$1" \
    -c "$PROBE_DIR/probe.swift" -o "$PROBE_DIR/probe.o" >/dev/null 2>&1
}
if ! sdk_compiles "$SDK"; then
  for candidate in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -V -r); do
    if [ -e "$candidate" ] && sdk_compiles "$candidate"; then
      SDK="$candidate"
      break
    fi
  done
fi
rm -rf "$PROBE_DIR"
echo "› SDK: $SDK"

SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find Sources/Nookit -name '*.swift' | sort)

if [ "${#SOURCES[@]}" -eq 0 ]; then
  echo "✗ no Swift sources found" >&2
  exit 1
fi

echo "› compiling ${#SOURCES[@]} Swift files ($CONFIG, $TARGET)"
mkdir -p build
FLAGS=(-parse-as-library -swift-version 5 -target "$TARGET" -sdk "$SDK")
if [ "$CONFIG" = "release" ]; then
  FLAGS+=(-O)
else
  FLAGS+=(-Onone -g)
fi

swiftc "${FLAGS[@]}" -o "$BIN" "${SOURCES[@]}"

echo "› assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Nookit"
cp Info.plist "$APP/Contents/Info.plist"
cp Sources/Nookit/Resources/catalog.json "$APP/Contents/Resources/catalog.json"

# Icon: rasterize the vector mark at each required size, then pack an .icns.
if [ -f Assets/AppIcon.svg ]; then
  TMP="$(mktemp -d)"
  ICONSET="$TMP/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    qlmanage -t -s "$size" -o "$TMP" Assets/AppIcon.svg >/dev/null 2>&1 || true
    src="$TMP/AppIcon.svg.png"
    if [ -f "$src" ]; then
      cp "$src" "$ICONSET/icon_${size}x${size}.png"
      cp "$src" "$ICONSET/icon_$((size * 2))x$((size * 2)).png" 2>/dev/null || true
    fi
  done
  if [ -f "$ICONSET/icon_512x512.png" ]; then
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP"
fi

# Ad-hoc sign so Gatekeeper is at least internally consistent for local runs.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "✓ $APP"
echo "  open $APP"
