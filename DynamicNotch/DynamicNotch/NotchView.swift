//
//  NotchView.swift
//  DynamicNotch
//

import SwiftUI
import AppKit

// Notch shape with concave (inverse) corners at top-left and top-right
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var topRadius: CGFloat = 16

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topRadius) }
        set { bottomRadius = newValue.first; topRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, rect.height / 2)
        let concaveR = topRadius

        var path = Path()

        // Begin outside left edge, at screen top
        path.move(to: CGPoint(x: rect.minX - concaveR, y: rect.minY))

        // Concave cubic bezier pulling into top-left — control points create the "pulled in" look
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + concaveR),
            control1: CGPoint(x: rect.minX - concaveR * 0.1, y: rect.minY),
            control2: CGPoint(x: rect.minX, y: rect.minY + concaveR * 0.1)
        )

        // Left edge down to bottom-left curve start
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))

        // Bottom-left rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))

        // Bottom-right rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - r),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )

        // Right edge up to top-right concave start
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + concaveR))

        // Concave cubic bezier pulling out to top-right
        path.addCurve(
            to: CGPoint(x: rect.maxX + concaveR, y: rect.minY),
            control1: CGPoint(x: rect.maxX, y: rect.minY + concaveR * 0.1),
            control2: CGPoint(x: rect.maxX + concaveR * 0.1, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}

struct NotchView: View {
    private var state = NotchState.shared
    private var activities = ActivityStore.shared
    @AppStorage("showMusic") private var showMusic = true
    @AppStorage("showTimer") private var showTimer = true
    @AppStorage("showFiles") private var showFiles = true
    @AppStorage("note") private var note = ""
    @AppStorage("notchOpacity") private var opacity = 1.0
    @AppStorage("notchRadius") private var radius = 24.0
    @AppStorage("notchBlue") private var blue = false
    @AppStorage("notchGlass") private var glass = true
    @State private var targeted = false

    private var tabs: [String] {
        ["dashboard", "calendar"] + (showMusic ? ["music"] : []) + ["todo", "notes"] + (showTimer ? ["timer"] : []) + ["day", "weather"] + (showFiles ? ["files"] : []) + ["clipboard", "notifications"]
    }
    private func label(_ tab: String) -> String {
        switch tab {
        case "music": "Media"
        case "timer": "Pomodoro"
        case "day": "Day Progress"
        default: tab.capitalized
        }
    }
    private func icon(_ tab: String) -> String {
        switch tab {
        case "dashboard": "square.grid.2x2"
        case "calendar": "calendar"
        case "todo": "checklist"
        case "day": "chart.bar.fill"
        case "weather": "cloud.sun"
        case "music": "music.note"
        case "timer": "timer"
        case "files": "tray.and.arrow.down"
        case "notes": "note.text"
        case "clipboard": "doc.on.clipboard"
        case "notifications": "bell"
        default: "gearshape"
        }
    }

    private var notifications = NotificationStore.shared
    private var clipboard = ClipboardStore.shared

    var body: some View {
        let shape = NotchShape(bottomRadius: 8 + (radius - 8) * state.revealProgress,
                               topRadius: 16 * state.revealProgress)
        ZStack(alignment: .top) {
            Group {
                if glass {
                    GlassBackground()
                        .overlay((blue ? Color.blue : .black).opacity(0.18 * opacity))
                        .overlay(LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    (blue ? Color(red: 0.02, green: 0.05, blue: 0.12) : Color.black).opacity(opacity)
                }
            }
            .frame(width: state.presentationSize.width + 32, height: state.presentationSize.height)
            .frame(width: state.presentationSize.width, height: state.presentationSize.height)
            .allowsHitTesting(false)
            .clipShape(shape)
            .opacity(state.hasPhysicalNotch ? state.revealProgress : 1)
            shape.stroke(.white.opacity(0.18 * state.revealProgress), lineWidth: 0.7)
            if state.revealProgress > 0 {
                if !state.isExpanded, let item = notifications.preview ?? notifications.lastPreview {
                    notificationPreview(item)
                } else {
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach(tabs, id: \.self) { tab in
                            Button { activities.selected = tab } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: icon(tab))
                                    if activities.selected == tab {
                                        Text(label(tab))
                                    }
                                    if tab == "notifications", !notifications.items.isEmpty {
                                        Text("\(notifications.items.count)").foregroundStyle(.orange)
                                    }
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 7).frame(height: 24)
                                .background(activities.selected == tab ? .white.opacity(0.12) : .clear, in: Capsule())
                            }.help(label(tab)).accessibilityLabel(label(tab))
                        }
                        Spacer(minLength: 0)
                        Button { SettingsWindowController.shared.show() } label: {
                            Image(systemName: "gearshape").frame(width: 24, height: 24)
                        }.help("Open Settings")
                        Button { state.isExpanded = false } label: {
                            Image(systemName: "chevron.up").frame(width: 22, height: 22)
                        }.help("Collapse")
                    }
                    content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .opacity(state.contentOpacity)
                }
                .padding(.horizontal, 18).padding(.bottom, 10)
                .padding(.top, state.collapsedSize.height + 3)
                .frame(width: NotchState.size(for: state.renderedPage).width, height: NotchState.size(for: state.renderedPage).height)
                .opacity(max(0, (state.revealProgress - 0.45) / 0.55))
                .allowsHitTesting(state.revealProgress > 0.95)
                }
            }
        }
        .frame(width: state.presentationSize.width, height: state.presentationSize.height)
        .clipShape(shape)
        .contentShape(shape)
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .buttonStyle(NotchButtonStyle())
        .dropDestination(for: URL.self) { urls, _ in showFiles && activities.accept(urls) } isTargeted: { inside in
            targeted = inside
            state.isDropTargeted = inside && showFiles
            if inside && showFiles { state.isExpanded = true }
        }
        .overlay { if targeted && showFiles { shape.stroke(.blue, lineWidth: 1) } }
        .overlay(alignment: .bottom) {
            if state.isExpanded, let item = notifications.preview {
                HStack(spacing: 10) {
                    Group {
                        if let icon = item.appIcon {
                            Image(nsImage: icon)
                                .resizable().scaledToFill()
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        } else {
                            Image(systemName: "app.fill")
                                .foregroundStyle(.mint)
                                .frame(width: 28, height: 28)
                        }
                    }
                    Button {
                        activities.selected = "notifications"
                        notifications.preview = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.source).font(.system(size: 10, weight: .semibold))
                            Text(item.message).font(.system(size: 11)).lineLimit(2)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button { notifications.preview = nil } label: { Image(systemName: "xmark") }.help("Dismiss preview")
                }
                .padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
        .contextMenu {
            Button("Expand") { state.isExpanded = true }
            Button("Settings") { SettingsWindowController.shared.show() }
            Divider()
            Button("Quit DynamicNotch") { NSApp.terminate(nil) }
        }
        .onChange(of: tabs) { _, available in
            if !available.contains(activities.selected) { activities.selected = available[0] }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var content: some View {
        switch state.renderedPage {
        case "dashboard": DashboardView()
        case "calendar": CalendarPageView()
        case "todo": TodoView()
        case "day": DayProgressView()
        case "weather": WeatherPageView()
        case "timer": PomodoroView()
        case "files": filesContent
        case "notes": NotesView()
        case "notifications": notificationContent
        case "clipboard": clipboardContent
        default: musicContent
        }
    }

    private var musicContent: some View {
        let media = MediaRemoteManager.shared
        return VStack(spacing: 24) {
            HStack(spacing: 22) {
                Button { media.openPlayer() } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08))
                        if let artwork = media.artwork { Image(nsImage: artwork).resizable().scaledToFill() }
                        else { Image(systemName: "music.note").foregroundStyle(.white.opacity(0.4)) }
                    }.frame(width: 110, height: 110).clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                }.help("Open player")
                VStack(alignment: .leading, spacing: 3) {
                    Text(media.title.isEmpty ? "Ready when you are" : media.title)
                        .font(.system(size: 18, weight: .semibold)).lineLimit(2)
                    Text(media.title.isEmpty ? media.statusMessage : media.artist)
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    Text(media.album).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    Text(media.applicationName.uppercased()).font(.system(size: 8, weight: .medium))
                        .tracking(1).foregroundStyle(.white.opacity(0.3)).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 12) {
                    Button { media.previousTrack() } label: { Image(systemName: "backward.fill").frame(width: 24, height: 30) }.accessibilityLabel("Previous track")
                    Button { media.togglePlayPause() } label: {
                        Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                            .foregroundStyle(.black).frame(width: 32, height: 32).background(.white, in: Circle())
                    }.accessibilityLabel(media.isPlaying ? "Pause" : "Play")
                    Button { media.nextTrack() } label: { Image(systemName: "forward.fill").frame(width: 24, height: 30) }.accessibilityLabel("Next track")
                }.font(.system(size: 13))
            }
            HStack(spacing: 8) {
                Text(MediaRemoteManager.timeLabel(media.elapsed))
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule().fill(.white.opacity(0.8)).frame(width: geometry.size.width * media.progress)
                    }
                }.frame(height: 3)
                Text(media.duration > 0 ? MediaRemoteManager.timeLabel(media.duration) : "--:--")
            }.font(.system(size: 8, design: .monospaced)).foregroundStyle(.white.opacity(0.4))
        }.padding(18).frame(maxHeight: .infinity)
    }

    private var filesContent: some View {
        VStack(spacing: 5) {
            Image(systemName: targeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 22, weight: .light)).foregroundStyle(targeted ? .blue : .white.opacity(0.7))
            Text(activities.files.isEmpty ? "Drop files into notch" : "\(activities.files.count) files ready")
                .font(.system(size: 11, weight: .medium))
            if !activities.files.isEmpty {
                HStack(spacing: 18) {
                    Button("Copy") { activities.copyFiles() }
                    ShareLink(items: activities.files) { Text("Share / AirDrop") }
                    Button("Clear") { activities.files = [] }
                }.font(.system(size: 10))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
    }

    private func notificationPreview(_ item: NotchNotification) -> some View {
        HStack(spacing: 10) {
            Group {
                if let icon = item.appIcon {
                    Image(nsImage: icon)
                        .resizable().scaledToFill()
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 17)).foregroundStyle(.white.opacity(0.9))
                        .frame(width: 34, height: 34).background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Button {
                activities.selected = "notifications"
                state.isExpanded = true
                notifications.preview = nil
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.source).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(item.message).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { notifications.preview = nil } label: {
                Image(systemName: "xmark").font(.system(size: 10)).frame(width: 22, height: 28)
            }.help("Dismiss preview")
        }
        .padding(.horizontal, 18).padding(.top, state.collapsedSize.height + 5).padding(.bottom, 8)
        .frame(width: NotchState.previewSize.width, height: NotchState.previewSize.height)
        .opacity(state.revealProgress)
    }

    private var clipboardContent: some View {
        VStack(spacing: 4) {
            HStack {
                Toggle("Clipboard history", isOn: Bindable(clipboard).enabled)
                Spacer()
                Button("Clear") { clipboard.clear() }
            }.font(.system(size: 10))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if clipboard.items.isEmpty {
                        Text(clipboard.enabled ? "Copy text to start your history" : "Enable to keep up to 50 text copies for this session")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    ForEach(clipboard.items) { item in
                        Button { clipboard.copy(item) } label: {
                            Text(item.text).font(.system(size: 11)).lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(5)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                        }.help("Copy again")
                    }
                }
            }
        }
    }

    private var notificationContent: some View {
        // Group items by source, preserving insertion order
        let grouped: [(source: String, items: [NotchNotification])] = {
            var order: [String] = []
            var dict: [String: [NotchNotification]] = [:]
            for item in notifications.items {
                if dict[item.source] == nil { order.append(item.source) }
                dict[item.source, default: []].append(item)
            }
            return order.map { (source: $0, items: dict[$0]!) }
        }()

        return VStack(spacing: 4) {
            HStack {
                Text(notifications.captureStatus)
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                if !notifications.captureEnabled || !notifications.accessibilityGranted {
                    Button("Enable") { notifications.requestAccess() }.font(.system(size: 10, weight: .semibold))
                }
                Button("Clear") { notifications.clear() }.font(.system(size: 9))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if notifications.items.isEmpty {
                        Text("No notifications yet").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    ForEach(grouped, id: \.source) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            // Source header
                            HStack(spacing: 5) {
                                Image(systemName: "bell.fill").foregroundStyle(.orange).font(.system(size: 9))
                                Text(group.source).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                                Spacer()
                                Text("\(group.items.count)").font(.system(size: 8)).foregroundStyle(.white.opacity(0.35))
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)

                            Divider().background(.white.opacity(0.1))

                            // Items inside the card
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                    HStack(alignment: .top, spacing: 8) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Text(item.date, style: .time).foregroundStyle(.secondary)
                                                Spacer()
                                                Button { notifications.dismiss(item.id) } label: {
                                                    Image(systemName: "xmark").font(.system(size: 8))
                                                }.help("Remove")
                                            }
                                            Text(item.message).textSelection(.enabled)
                                        }
                                    }
                                    .font(.system(size: 10))
                                    .padding(.horizontal, 8).padding(.vertical, 5)

                                    if index < group.items.count - 1 {
                                        Divider().background(.white.opacity(0.06)).padding(.horizontal, 8)
                                    }
                                }
                            }
                        }
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }


}


private struct NotchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
