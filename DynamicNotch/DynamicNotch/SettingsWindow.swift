import AppKit
import SwiftUI

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    func show() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 590),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            panel.title = "DynamicNotch Settings"
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 540, height: 460)
            panel.contentView = NSHostingView(rootView: SettingsPanelView())
            panel.center()
            window = panel
        }
        NotchState.shared.isExpanded = false
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsPanelView: View {
    @AppStorage("showMusic") private var showMusic = true
    @AppStorage("showTimer") private var showTimer = true
    @AppStorage("showFiles") private var showFiles = true
    @AppStorage("notchOpacity") private var opacity = 1.0
    @AppStorage("notchRadius") private var radius = 24.0
    @AppStorage("notchBlue") private var blue = false
    @AppStorage("notchGlass") private var glass = true
    @Bindable private var notifications = NotificationStore.shared
    @Bindable private var clipboard = ClipboardStore.shared
    @Bindable private var calendar = CalendarStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Make the notch yours", systemImage: "slider.horizontal.3").font(.title2).fontWeight(.semibold)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Appearance & activities") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Show Media", isOn: $showMusic)
                            Toggle("Show Pomodoro", isOn: $showTimer)
                            Toggle("Enable file drop", isOn: $showFiles)
                            Toggle("Blue glass tint", isOn: $blue)
                            Toggle("Glassmorphism background", isOn: $glass)
                            HStack { Text("Tint strength"); Slider(value: $opacity, in: 0.7...1) }
                            HStack { Text("Corner radius"); Slider(value: $radius, in: 8...36) }
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("Calendar") {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(calendar.status).font(.callout).foregroundStyle(.secondary)
                            HStack {
                                Button("Allow access") { Task { await calendar.connect() } }.disabled(calendar.requesting)
                                Button("Privacy settings") { calendar.openPrivacy() }
                                Button("Google / accounts") { calendar.openAccounts() }
                            }
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("Notifications") {
                        VStack(alignment: .leading, spacing: 9) {
                            Toggle("Capture app notifications", isOn: $notifications.captureEnabled)
                            Toggle("Read directly from Notification Center", isOn: $notifications.directCaptureEnabled)
                            if notifications.directCaptureEnabled {
                                Text("For notch-only notifications: grant Full Disk Access, then silence banners below. Keep Allow Notifications and Show in Notification Center enabled.").font(.caption)
                                HStack {
                                    Button("Full Disk Access…") { notifications.openFullDiskAccess() }
                                    Button("Native notification settings…") { notifications.openNotificationSettings() }
                                }
                                HStack {
                                    Button("Silence native banners") { notifications.silenceNativeBanners() }
                                    if notifications.bannersSilenced {
                                        Button("Restore original styles") { notifications.restoreNativeBanners() }
                                    }
                                }
                                Text("Silencing sets every app's alert style to None so macOS never draws banners — notifications still arrive in the notch. Restore brings back the original styles.").font(.caption).foregroundStyle(.secondary)
                                Text("The database format is private and may change with macOS updates. Capture starts with new arrivals; existing history is not imported. Delivery waits for macOS to save the notification.").font(.caption).foregroundStyle(.secondary)
                            }
                            if !notifications.directCaptureEnabled { Toggle("Dismiss native banner after capture", isOn: $notifications.dismissNativeBanners) }
                            Text(notifications.captureStatus).font(.callout)
                            Text(notifications.diagnostics).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            HStack {
                                if notifications.directCaptureEnabled {
                                    Button("Check access") { notifications.refreshPermission() }
                                } else {
                                    Button("Allow Accessibility") { notifications.requestAccess() }
                                    Button("Open permission settings") { notifications.openPrivacy() }
                                }
                                Button("Test preview") { notifications.add(message: "This is a DynamicNotch preview test.") }
                            }
                            if !notifications.directCaptureEnabled { Text("Accessibility mode requires visible banners and may briefly overlap native notifications. Direct mode is required for no-banner delivery.").font(.caption).foregroundStyle(.secondary) }
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("Clipboard & local data") {
                        VStack(alignment: .leading, spacing: 9) {
                            Toggle("Keep clipboard text history for this session", isOn: $clipboard.enabled)
                            HStack {
                                Button("Clear clipboard history") { clipboard.clear() }
                                Button("Clear notification history") { notifications.clear() }
                            }
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }.padding(22).frame(minWidth: 500, minHeight: 420)
            .onAppear { calendar.refresh(); notifications.refreshPermission() }
    }
}
