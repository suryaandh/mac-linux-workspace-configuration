# DynamicNotch

A glass macOS notch panel with a compact Dashboard and dedicated productivity pages. Build and run the DynamicNotch scheme in Xcode.

## Navigation

The first page is **Dashboard**: four horizontal sections separated by dividers — Todo, mini music, Pomodoro and Day Progress. Click a section to open its detail page. Icon tabs provide access to every page; hover an icon for its name.

- **Calendar:** month grid on the left, selected day's events on the right. Navigate months, select a day, jump to today or refresh. All-day and timed events are supported. EventKit updates refresh the list.
- **Media:** larger cover art, title, artist, album, source app, progress and playback controls. Clicking the artwork opens the player.
- **Todo:** add, edit, complete and delete tasks; saved locally.
- **Notes:** note list on the left and title/body editor on the right. Changes save automatically. The previous single Quick Note is migrated once; deleting it does not recreate it on restart.
- **Pomodoro:** circular timer on the left; selectable focus-task queue and completed-session history on the right. Presets: 5, 15, 25 and 50 minutes. Pause/resume/stop supported. The session records its original task name when it finishes. Breaks are started manually. Timers survive sleep, not application termination.
- **Day Progress:** local calendar-day percentage and task/focus summary. Calculation accounts for daylight-saving days and refreshes every 30 seconds.
- **Weather:** search a city, choose among matching locations, view temperature, feels-like temperature, humidity and wind, then refresh when needed. Conditions are model data from [Open-Meteo](https://open-meteo.com/), fetched on demand; no location permission or API key is used. A failure is shown explicitly. The selected city is session-only.

Todo, notes, focus tasks and up to 200 completed sessions persist in UserDefaults on this Mac. They are separate from Apple Reminders and do not sync to cloud accounts.

## Connect Google Calendar

1. Add Google under macOS **System Settings → Internet Accounts**, and enable Calendars.
2. Confirm the calendars/events appear in Apple Calendar.
3. Open DynamicNotch's Calendar tab and select **Allow Calendar access**.

The Connect Google account button opens Internet Accounts. This is integration through macOS calendar synchronization, not a separate OAuth login inside DynamicNotch. DynamicNotch reads synced events; it does not create or modify them. The EventKit permission is called “full access” by macOS because event reads require it.

Sources: [Google Calendar setup](https://support.google.com/calendar/answer/99358), [Apple account setup](https://support.apple.com/en-ca/guide/calendar/-icl4308d6701/mac).

## Panel behavior

Dashboard is 640 × 150 logical points; detail pages are 640 × 330 points so split editors and calendar grids have room. Notification previews remain 460 × 96 points. The glass appearance uses an AppKit behind-window visual effect. File-drop content is centered.

Hover opens only within the physical camera cutout measured by NSScreen. The connected display measured 185 × 32 points at Retina 2× during earlier validation. Collapsed overlay is transparent on notched screens, preserving the real silhouette. Displays without a cutout get a 170 × 24 point virtual notch. A 16-point side gutter accommodates the top curves. Size and corner animation lasts 0.38 seconds; Reduce Motion skips it.

## Other tools

- File drop: local files can be copied or sent through the system share sheet, including AirDrop when offered. No transfer begins automatically.
- Clipboard: optional session-only history of up to 50 text copies. Click to copy again or clear. Concealed/transient/generated pasteboard types are skipped.
- Notifications: up to 100 session-only entries, preview on arrival for six seconds, dismiss and clear. New arrivals replace the preview, and every entry remains in history. The bell tab shows capture status and an Enable button. Settings has a labeled preview test.
- Settings: activity visibility, tint, opacity and corner radius. Right-click the panel or use the menu bar item to access/quit the app.

## Notification coverage

Optional system capture reads visible Notification Center Accessibility text every 350 ms without overlapping scans. Enable capture and grant Accessibility to the running app. Keep macOS banners enabled. Identical visible snapshots within 30 seconds are deduplicated.

This does **not** replace macOS notification delivery or suppress native banners. Hidden previews, Focus-suppressed banners, unsupported Accessibility content and banners missed between scans cannot be guaranteed. Notification Center can expose a group as one snapshot. Chrome/WhatsApp capture still needs live verification after permission is granted. Messages/Mail snippets require a readable notification; direct mailbox access and sender avatars are not implemented. See [Apple notification API scope](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter).

## Media dependency

Metadata streams through [MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter), pinned to `5b6afde3f501a3da567e23bf7f23d562938a1809` via Swift Package Manager. Xcode embeds the framework and Perl resource; the first resolution needs internet access. Existing native playback commands remain the primary control path. MediaRemote is a private framework and player/macOS compatibility may change. Artwork is shown when supplied by the player.

## Validation

```sh
xcodebuild -project DynamicNotch.xcodeproj -scheme DynamicNotch -configuration Debug -derivedDataPath /tmp/DynamicNotch-build CODE_SIGNING_ALLOWED=NO build
swiftc -module-cache-path /tmp/DynamicNotch-module-cache DynamicNotch/ProductivityStore.swift Tests/ProductivityChecks.swift -o /tmp/DynamicNotch-productivity-checks
/tmp/DynamicNotch-productivity-checks
swiftc -module-cache-path /tmp/DynamicNotch-module-cache DynamicNotch/ActivityStore.swift DynamicNotch/NotificationStore.swift DynamicNotch/ProductivityStore.swift Tests/TimerChecks.swift -o /tmp/DynamicNotch-timer-checks
/tmp/DynamicNotch-timer-checks
```

Productivity checks cover task/session persistence, one-time note migration, deletion and daylight-saving day progress. Other standalone checks in Tests cover timer behavior, notification history and notch geometry. The Open-Meteo city search and current-conditions flow was exercised successfully using Jakarta. AppKit snapshots were used to inspect page layouts with fixture media. Calendar permission and Google account sync still require validation with an authorized account; a successful build alone does not verify them.

Remaining integrations include system Clock timers, downloads, recording detection, system HUD alerts, lock screen, direct Messages/Mail and localization.
