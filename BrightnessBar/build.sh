#!/bin/bash
set -euo pipefail

APP_NAME="BrightnessBar"
BUILD_DIR="./build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS" "$RESOURCES"

echo "==> Compiling C shim..."
clang -c IOAVService.c -o "$BUILD_DIR/IOAVService.o" \
    -target arm64-apple-macos12.0

echo "==> Compiling Swift sources..."
swiftc \
    main.swift \
    AppDelegate.swift \
    BrightnessController.swift \
    BrightnessViewController.swift \
    -framework Cocoa \
    -framework CoreGraphics \
    -framework IOKit \
    -framework CoreDisplay \
    -import-objc-header IOAVService.h \
    -target arm64-apple-macos12.0 \
    -O \
    "$BUILD_DIR/IOAVService.o" \
    -o "$MACOS/$APP_NAME"

echo "==> Copying Info.plist..."
cp Info.plist "$CONTENTS/Info.plist"

echo "==> Ad-hoc signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "Build complete: $APP_BUNDLE"
echo "Run with: open $APP_BUNDLE"
