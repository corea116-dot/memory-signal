#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build Resources
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$PWD/build/ModuleCache"
APP="$PWD/../메모리 신호.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc Tools/ExtractIcons.swift -o build/extract-icons
build/extract-icons Resources/source-icons.png Resources
xcrun swiftc -swift-version 6 Sources/Pressure.swift Sources/MemorySnapshot.swift Tests/main.swift -o build/pressure-tests
build/pressure-tests
xcrun swiftc -swift-version 6 -O -target arm64-apple-macosx13.0 Sources/*.swift \
  -o "$APP/Contents/MacOS/MemoryPressure" -framework AppKit -framework ServiceManagement -framework UserNotifications
cp Resources/*.png "$APP/Contents/Resources/"
ICONSET="$PWD/build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
python3 - "$ICONSET" "$APP/Contents/Resources/AppIcon.icns" <<'ICONPY'
import pathlib, struct, sys
source = pathlib.Path(sys.argv[1])
entries = [('icp4', '16x16'), ('icp5', '32x32'), ('icp6', '32x32@2x'),
           ('ic07', '128x128'), ('ic08', '256x256'), ('ic09', '512x512'),
           ('ic10', '512x512@2x'), ('ic11', '16x16@2x'),
           ('ic12', '32x32@2x'), ('ic13', '128x128@2x'), ('ic14', '256x256@2x')]
chunks = []
for kind, name in entries:
    data = (source / ('icon_' + name + '.png')).read_bytes()
    chunks.append(kind.encode('ascii') + struct.pack('>I', len(data) + 8) + data)
body = b''.join(chunks)
pathlib.Path(sys.argv[2]).write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
ICONPY
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.memory-pressure</string>
<key>CFBundleName</key><string>메모리 신호</string>
<key>CFBundleDisplayName</key><string>메모리 신호</string>
<key>CFBundleExecutable</key><string>MemoryPressure</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --identifier local.memory-pressure "$APP"
codesign --verify --strict "$APP"
printf 'Built: %s\n' "$APP"
