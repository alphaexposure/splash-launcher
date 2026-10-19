#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
icon='Sources/SplashLauncher/Resources/Splash.icns'
mark='Sources/SplashLauncher/SplashMark.swift'
# Regenerate the icon when it is missing or the shared mark has changed.
if [[ ! -s "$icon" || "$mark" -nt "$icon" || Scripts/make-icon/main.swift -nt "$icon" ]]; then
  mkdir -p Sources/SplashLauncher/Resources .build
  swiftc -O Scripts/make-icon/main.swift "$mark" -o .build/make-icon
  .build/make-icon
  iconutil -c icns .build/Splash.iconset -o "$icon"
fi
swift build -c release --product SplashLauncher
app='dist/Splash Launcher.app'
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Sources/SplashLauncher/Resources/Splash.icns "$app/Contents/Resources/Splash.icns"
cp .build/release/SplashLauncher "$app/Contents/MacOS/SplashLauncher"
cp -R .build/release/SplashLauncher_SplashLauncher.bundle "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>SplashLauncher</string>
  <key>CFBundleIdentifier</key><string>io.github.alphaexposure.SplashLauncher</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleIconFile</key><string>Splash.icns</string>
  <key>CFBundleName</key><string>Splash Launcher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$app/Contents/Info.plist"
test -s "$app/Contents/Resources/Splash.icns"
# Refresh the bundle date so macOS notices resources changed during an in-place build.
touch "$app"
codesign --force --sign - "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$PWD/$app"
print -r -- "$PWD/$app"
