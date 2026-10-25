#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Configuration
SIGNING_IDENTITY="Developer ID Application: Doug Dowenr (J77629PP5S)"
KEYCHAIN_PROFILE="InfraProxy"   # local notarytool credential alias on the build Mac; not shipped, not renamed
BUNDLE_ID="com.dynadobe.infravibe"
ENTITLEMENTS="infravibe.entitlements"
APP_VERSION="2.13.0"
APP_BUILD="18"
SPARKLE_FEED="https://github.com/netsecdevio/infravibe/releases/latest/download/appcast.xml"

# Parse arguments
NOTARIZE=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --notarize) NOTARIZE=true ;;
        --help)
            echo "Usage: ./build.sh [--notarize]"
            echo "  --notarize  Sign and notarize the app for distribution"
            exit 0
            ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

bash scripts/fetch-sparkle.sh
(cd Web && npm ci --ignore-scripts --no-fund && npm audit --omit=dev)
SPARKLE_PUBLIC_KEY=$(cat Resources/sparkle-public-key.txt)
echo "Building Infravibe..."

# Clean previous builds
rm -rf infravibe.app

# Compile each supported architecture, then sign the combined Universal 2 binary.
BUILD_SLICES=$(mktemp -d)
trap 'rm -rf "$BUILD_SLICES"' EXIT
for ARCH in arm64 x86_64; do
swiftc -target "$ARCH-apple-macosx15.5" -o "$BUILD_SLICES/Infravibe-$ARCH" \
    Sources/ProxyModels.swift Sources/HttpProxyExecutable.swift \
    Sources/IdentityMigration.swift \
    Sources/LaunchctlServiceManager.swift \
    Sources/InfravibeManager.swift \
    Sources/InfravibeActions.swift \
    Sources/DevOpsWorkspace.swift Sources/DevOpsConfiguration.swift Sources/DevOps.swift Sources/Operations.swift \
    Sources/CloudOperations.swift \
    Sources/OperationsCommand.swift \
    Sources/MenuBarPanel.swift \
    Sources/RemoteAccess.swift \
    Sources/AppUpdater.swift \
    Sources/AppSettings.swift \
    Sources/BrowserKeys.swift Sources/AgentAccess.swift Sources/TerminalSession.swift Sources/BrowserServer.swift \
    Sources/BrowserDashboard.swift \
    Sources/main.swift \
    -framework Cocoa \
    -framework UserNotifications \
    -F Vendor/Sparkle -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks
clang -target "$ARCH-apple-macosx15.5" -O2 -Wall -Wextra Sources/Helpers/TerminalHost.c -o "$BUILD_SLICES/TerminalHost-$ARCH"
done
lipo -create "$BUILD_SLICES/Infravibe-arm64" "$BUILD_SLICES/Infravibe-x86_64" -output Infravibe


# Create app bundle
mkdir -p infravibe.app/Contents/MacOS
mkdir -p infravibe.app/Contents/Resources
mkdir -p infravibe.app/Contents/Frameworks
lipo -create "$BUILD_SLICES/TerminalHost-arm64" "$BUILD_SLICES/TerminalHost-x86_64" -output infravibe.app/Contents/MacOS/TerminalHost
mkdir -p infravibe.app/Contents/Resources/Web
cp Web/index.html Web/app.js Web/style.css infravibe.app/Contents/Resources/Web/
cp Web/node_modules/@xterm/xterm/lib/xterm.js Web/node_modules/@xterm/xterm/css/xterm.css infravibe.app/Contents/Resources/Web/
cp Web/node_modules/@xterm/addon-fit/lib/addon-fit.js infravibe.app/Contents/Resources/Web/fit.js
cp Web/node_modules/@xterm/xterm/LICENSE infravibe.app/Contents/Resources/xterm-LICENSE.txt
cp Web/node_modules/@xterm/addon-fit/LICENSE infravibe.app/Contents/Resources/xterm-fit-LICENSE.txt
ditto Vendor/Sparkle/Sparkle.framework infravibe.app/Contents/Frameworks/Sparkle.framework
cp Vendor/Sparkle/LICENSE infravibe.app/Contents/Resources/Sparkle-LICENSE.txt
cp Resources/VibeTunnel-LICENSE.txt infravibe.app/Contents/Resources/
cp Resources/terminal.sb infravibe.app/Contents/Resources/
cp THIRD_PARTY_NOTICES.md infravibe.app/Contents/Resources/

# Copy executable
mv Infravibe infravibe.app/Contents/MacOS/

# Create app icon (if icon.png exists)
if [ -f "icon.png" ]; then
    mkdir -p infravibe.app/Contents/Resources/AppIcon.iconset

    # Generate iconset from PNG
    sips -z 16 16     icon.png --out infravibe.app/Contents/Resources/AppIcon.iconset/icon_16x16.png
    sips -z 32 32     icon.png --out infravibe.app/Contents/Resources/AppIcon.iconset/icon_16x16@2x.png
    sips -z 32 32     icon.png --out infravibe.app/Contents/Resources/AppIcon.iconset/icon_32x32.png
    sips -z 64 64     icon.png --out infravibe.app/Contents/Resources/AppIcon.iconset/icon_32x32@2x.png
    sips -z 128 128   icon.png --out infravibe.app/Contents/Resources/AppIcon.iconset/icon_128x128.png
    sips -z 256 256   icon.png --out infravibe.app/Contents/Resources/AppIcon.iconset/icon_128x128@2x.png
    sips -z 256 256   icon.png --out infravibe.app/Contents/Resources/AppIcon.iconset/icon_256x256.png
    sips -z 512 512   icon.png --out infravibe.app/Contents/Resources/AppIcon.iconset/icon_256x256@2x.png
    sips -z 512 512   icon.png --out infravibe.app/Contents/Resources/AppIcon.iconset/icon_512x512.png
    sips -z 1024 1024 icon.png --out infravibe.app/Contents/Resources/AppIcon.iconset/icon_512x512@2x.png

    # Convert to icns
    iconutil -c icns infravibe.app/Contents/Resources/AppIcon.iconset
    rm -rf infravibe.app/Contents/Resources/AppIcon.iconset

    ICON_LINE="
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
else
    ICON_LINE=""
fi

# Create Info.plist
cat > infravibe.app/Contents/Info.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Infravibe</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>infravibe</string>
    <key>CFBundleDisplayName</key>
    <string>infravibe</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD}</string>
    <key>SUFeedURL</key>
    <string>${SPARKLE_FEED}</string>
    <key>SUPublicEDKey</key>
    <string>${SPARKLE_PUBLIC_KEY}</string>
    <key>SURequireSignedFeed</key>
    <true/>
    <key>SUVerifyUpdateBeforeExtraction</key>
    <true/>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUAutomaticallyUpdate</key>
    <false/>
    <key>SUAllowsAutomaticUpdates</key>
    <false/>
    <key>SUEnableSystemProfiling</key>
    <false/>
    <key>LSMinimumSystemVersion</key>
    <string>15.5</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>infravibe connects to monitoring servers and infrastructure you configure on your local network.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>infravibe opens Google Cloud SSH connections in your preferred terminal.</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>${ICON_LINE}
</dict>
</plist>
EOF

bash scripts/verify-architectures.sh infravibe.app
echo "✅ infravibe.app created successfully"

# Code signing and notarization
if [ "$NOTARIZE" = true ]; then
    echo ""
    echo "🔐 Signing app with hardened runtime..."

    # Sign nested Sparkle helpers inside-out, retaining their required entitlements.
    SPARKLE_ROOT="infravibe.app/Contents/Frameworks/Sparkle.framework/Versions/B"
    for component in "$SPARKLE_ROOT/XPCServices/Downloader.xpc" \
                     "$SPARKLE_ROOT/XPCServices/Installer.xpc" \
                     "$SPARKLE_ROOT/Autoupdate" "$SPARKLE_ROOT/Updater.app" \
                     "infravibe.app/Contents/Frameworks/Sparkle.framework"; do
        codesign --force --options runtime --preserve-metadata=identifier,entitlements \
            --sign "$SIGNING_IDENTITY" --timestamp "$component"
    done

    codesign --force --options runtime --sign "$SIGNING_IDENTITY" --timestamp infravibe.app/Contents/MacOS/TerminalHost

    # Sign the app with hardened runtime (required for notarization)
    codesign --force --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGNING_IDENTITY" \
        --timestamp \
        infravibe.app

    # Verify the signature
    echo "🔍 Verifying signature..."
    codesign --verify --deep --strict --verbose=2 infravibe.app

    # Create a zip for notarization
    echo "📦 Creating zip for notarization..."
    rm -f Infravibe.zip
    ditto -c -k --keepParent infravibe.app Infravibe.zip

    # Submit for notarization
    echo "📤 Submitting for notarization (this may take a few minutes)..."
    xcrun notarytool submit Infravibe.zip \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait

    # Staple the notarization ticket
    echo "📎 Stapling notarization ticket..."
    xcrun stapler staple infravibe.app

    # Verify stapling
    echo "🔍 Verifying stapled app..."
    xcrun stapler validate infravibe.app

    # Clean up
    rm -f Infravibe.zip

    echo ""
    echo "✅ infravibe.app is signed and notarized!"
    echo "📦 Ready for distribution"
else
    echo ""
    echo "💡 To sign and notarize for distribution, run:"
    echo "   ./build.sh --notarize"
    echo ""
    echo "📦 Ready for local testing"
fi
