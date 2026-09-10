# DynamicNotch

A glass macOS notch panel with a compact Dashboard and dedicated productivity pages. Build and run the DynamicNotch scheme in Xcode.

## Navigation

The first page is **Dashboard**: four horizontal sections separated by dividers — Todo, mini music, Pomodoro and Day Progress. When history contains notifications, up to three newest cards appear below a horizontal divider. The panel grows with the cards; dismissing or clearing them shrinks it back. “View all” opens notification history. Click a section to open its detail page. Icon tabs provide access to every page; hover an icon for its name.

- **Calendar:** month grid on the left, selected day's events on the right. Navigate months, select a day, jump to today or refresh. All-day and timed events are supported. EventKit updates refresh the list.
- **Media:** larger cover art, title, artist, album, source app, progress and playback controls. Clicking the artwork opens the player.
- **Todo:** cards with editable parent tasks and one level of subtasks. Add, edit, complete and delete either; deleting a parent removes its children, and completing a parent completes its children. Send either to Pomodoro; saved locally.
- **Notes:** note list on the left and title/body editor on the right. Changes save automatically. The previous single Quick Note is migrated once; deleting it does not recreate it on restart.
- **Pomodoro:** circular timer on the left; selectable focus-task queue and completed-session history on the right. Presets: 5, 15, 25 and 50 minutes, plus a saved custom duration of 1–240 minutes. Linked subtasks show “Parent › Subtask” in the queue and session history. Pause/resume/stop supported. The session records its original task name when it finishes. Breaks are started manually. Timers survive sleep, not application termination.
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

Dashboard is 640 × 150 logical points when empty and grows to at most 640 × 389 with three recent notification cards; detail pages are 640 × 330 points so split editors and calendar grids have room. Notification previews remain 460 × 96 points. The glass appearance uses an AppKit behind-window visual effect. File-drop content is centered.

Hover opens only within the physical camera cutout measured by NSScreen. The connected display measured 185 × 32 points at Retina 2× during earlier validation. Collapsed overlay is transparent on notched screens, preserving the real silhouette. Displays without a cutout get a 170 × 24 point virtual notch. A 16-point side gutter accommodates the top curves. Size and corner animation lasts 0.42 seconds, with 0.38-second page transitions and a gradual content fade; Reduce Motion skips it.

## Other tools

- File drop: local files can be copied or sent through the system share sheet, including AirDrop when offered. No transfer begins automatically.
- Clipboard: optional session-only history of up to 50 text copies. Click to copy again or clear. Concealed/transient/generated pasteboard types are skipped.
- Notifications: up to 100 session-only entries, preview on arrival for four seconds, dismiss and clear. New arrivals replace the preview, and entries remain as separate cards with app icons. Closing a card removes that entry; opening its preview retains it in history. The bell tab shows capture status and an Enable button. Settings has a labeled preview test.
- Settings: activity visibility, tint, opacity and corner radius. Right-click the panel or use the menu bar item to access/quit the app.

## Notification delivery and app icons

DynamicNotch uses `dynamicnotch.png` for its macOS app icon, menu bar icon, and its own notification cards. AppIcon contains all ten macOS sizes; the notification logo is a separate bundled image asset.

The local icon catalog includes ChatGPT/GPT, Instagram, tiket.com, Telegram, WhatsApp and Gmail. It recognizes app names, known domains, bundle IDs, and common iPhone-mirroring labels. Installed apps can supply additional icons via Launch Services. Unknown identities keep a generic icon. No notification text or sender names are sent to an icon service. Artwork and source URLs are recorded in `DynamicNotch/NotificationIconCatalog.json`; `Tools/fetch-notification-icons.py` refreshes the bundled artwork from Apple's App Store lookup API.

### Direct capture (new default when capture is enabled)

This mode reads new records from the local Notification Center database, without needing an on-screen native banner. To set it up:

1. Run the updated app and open Settings → Notifications. Enable capture and **Read directly from Notification Center**.
2. Use **Full Disk Access…** to allow the running DynamicNotch app in macOS Privacy & Security, then restart the app.
3. Check that Settings reports **Direct capture active** before changing native banner settings.
4. In macOS Notifications settings, use alert style **None** for source apps where available. Keep **Allow Notifications** and **Show in Notification Center** enabled. Keep iPhone notification mirroring enabled; turning it off stops delivery to the Mac entirely.
5. Send a new notification and verify that a notch card appears. Confirm native suppression separately for each source, especially mirrored iPhone apps whose available settings may differ.

The app cannot grant Full Disk Access or silently configure native notification permissions. This session could not open the protected system database, so real iPhone/Chrome delivery and suppression are **not yet verified**. Build and fixture tests do not prove that the installed macOS database has the expected schema or that native alert settings have been applied.

The reader opens SQLite strictly read-only, polls every 350 ms with a single reader, skips pre-session history, and distinguishes repeated equal-text messages by record ID. It never changes or deletes system notifications. It reads only plain title/subtitle/body fields and reports skipped unsupported records. The database path and binary-plist schema are private macOS implementation details; OS updates can break this mode. Notifications arrive only after macOS writes them to the database, which can introduce latency. Sources not saved there cannot be captured by this mode.

Schema reference: [mac_apt's Notification Center parser](https://github.com/ydkhatri/mac_apt/blob/master/plugins/notifications.py). System settings: [Apple notification settings](https://support.apple.com/guide/mac-help/notifications-settings-mh40583/mac), [iPhone notifications on Mac](https://support.apple.com/en-us/120684).

### Accessibility fallback

Disable direct capture to use visible-banner capture. It requires Accessibility and native banners enabled, so it cannot provide strictly banner-free delivery. Close attempts are serialized with capture; only supported close/cancel actions and exact close buttons are used. It does not press notification bodies or move windows off-screen, and failures are reported rather than marked successful. Identical visible text is deduplicated with a one-second grace period. Unsupported Accessibility layouts and hidden previews can be missed.

## Media dependency

Metadata streams through [MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter), pinned to `5b6afde3f501a3da567e23bf7f23d562938a1809` via Swift Package Manager. Xcode embeds the framework and Perl resource; the first resolution needs internet access. Existing native playback commands remain the primary control path. MediaRemote is a private framework and player/macOS compatibility may change. Artwork is shown when supplied by the player.

## Validation

```sh
xcodebuild -project DynamicNotch.xcodeproj -scheme DynamicNotch -configuration Debug -derivedDataPath /tmp/DynamicNotch-build CODE_SIGNING_ALLOWED=NO build
swiftc -module-cache-path /tmp/DynamicNotch-module-cache DynamicNotch/ProductivityStore.swift Tests/ProductivityChecks.swift -o /tmp/DynamicNotch-productivity-checks
/tmp/DynamicNotch-productivity-checks
swiftc -module-cache-path /tmp/DynamicNotch-module-cache DynamicNotch/ActivityStore.swift DynamicNotch/NotificationStore.swift DynamicNotch/NotificationIdentity.swift DynamicNotch/NotificationDatabase.swift DynamicNotch/ProductivityStore.swift Tests/TimerChecks.swift -o /tmp/DynamicNotch-timer-checks
/tmp/DynamicNotch-timer-checks
```

Productivity checks cover task/session persistence, one-time note migration, deletion and daylight-saving day progress. Other standalone checks in Tests cover timer behavior, notification history and notch geometry. The Open-Meteo city search and current-conditions flow was exercised successfully using Jakarta. AppKit snapshots were used to inspect page layouts with fixture media. Calendar permission and Google account sync still require validation with an authorized account; a successful build alone does not verify them.

Remaining integrations include system Clock timers, downloads, recording detection, system HUD alerts, lock screen, direct Messages/Mail and localization.

Database fixture checks (no real notification data):

```sh
swiftc -module-cache-path /tmp/DynamicNotch-module-cache DynamicNotch/NotificationDatabase.swift Tests/NotificationDatabaseChecks.swift -o /tmp/DynamicNotch-database-checks
/tmp/DynamicNotch-database-checks
```

The notification icon checks in `Tests/NotificationChecks.swift` must run from an app bundle with the built `Assets.car` and `NotificationIconCatalog.json` in `Contents/Resources` so they validate the actual shipped assets.
