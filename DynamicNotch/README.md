# DynamicNotch

Dynamic notch overlay for MacBook. Extends the notch area with contextual information.

## Features

- **Music** - shows current track title and artist, auto-expands on track change
- **Notifications** - displays system notifications in the notch area
- **Brightness** - shows a brightness indicator when it changes
- Smooth expand/collapse animation
- Transparent and non-interactive when collapsed

## Requirements

- macOS 12+ on a MacBook with a notch (MacBook Pro 2021+, MacBook Air 2022+)
- Xcode Command Line Tools (`xcode-select --install`)

## Build & Run

```bash
cd DynamicNotch
bash build.sh
open build/DynamicNotch.app
```

## Technical Notes

- Music info is fetched via `MRMediaRemoteGetNowPlayingInfo` (MediaRemote private framework)
- Notifications are monitored via notification observers
- The overlay window uses `NSWindow` level `.screenSaver` to stay on top
- No accessibility permission required

## Structure

```
AppDelegate.swift            app entry point
NotchWindowController.swift  window management and positioning
NotchView.swift              root view with expand/collapse logic
ContentViews.swift           MusicContentView, NotificationContentView, BrightnessContentView
MusicMonitor.swift           polls MediaRemote for now playing info
NotificationMonitor.swift    monitors system notifications
build.sh                     build script (swiftc, no Xcode project)
```
