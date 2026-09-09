#!/bin/bash
set -e

APP_NAME="DynamicNotch"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Cleaning previous build..."
rm -rf "$APP_BUNDLE"

echo "==> Creating bundle structure..."
mkdir -p "$MACOS" "$RESOURCES"

echo "==> Compiling Swift sources..."
swiftc \
    main.swift \
    AppDelegate.swift \
    NotchWindowController.swift \
    NotchView.swift \
    ContentViews.swift \
    BrightnessController.swift \
    MusicMonitor.swift \
    NotificationMonitor.swift \
    -o "$MACOS/$APP_NAME" \
    -framework Cocoa \
    -framework IOKit \
    -target arm64-apple-macosx12.0 \
    -O

echo "==> Copying Info.plist..."
cp Info.plist "$CONTENTS/Info.plist"

echo "==> Done! Run with:"
echo "    open $APP_BUNDLE"
