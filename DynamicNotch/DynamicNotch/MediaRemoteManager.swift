import AppKit
import Observation
import MediaRemoteAdapter

// Keep the existing working native command path; metadata uses the helper because
// modern macOS restricts reads from ordinary application processes.
private let mediaRemoteHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
private typealias SendCommand = @convention(c) (Int, AnyObject?) -> Bool
private let nativeSendCommand: SendCommand? = {
    guard let handle = mediaRemoteHandle, let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else { return nil }
    return unsafeBitCast(symbol, to: SendCommand.self)
}()

@Observable
final class MediaRemoteManager {
    static let shared = MediaRemoteManager()

    private(set) var title = ""
    private(set) var artist = ""
    private(set) var album = ""
    private(set) var applicationName = ""
    private(set) var artwork: NSImage?
    private(set) var isPlaying = false
    private(set) var duration: Double = 0
    private(set) var elapsed: Double = 0
    private(set) var statusMessage = "Connecting to your player…"
    var progress: Double { duration > 0 ? min(max(elapsed / duration, 0), 1) : 0 }

    private let controller = MediaController()
    private var payload: TrackInfo.Payload?
    private var timer: Timer?
    private var reconnect: Task<Void, Never>?
    private var stopped = false
    private var receivedResponse = false
    private var startupCheck: Task<Void, Never>?

    private init() {
        controller.onTrackInfoReceived = { [weak self] info in
            self?.receive(info)
        }
        controller.onDecodingError = { [weak self] _, _ in
            self?.statusMessage = "Could not read media details"
        }
        controller.onListenerTerminated = { [weak self] in
            guard let self, !self.stopped else { return }
            self.statusMessage = "Reconnecting to your player…"
            self.reconnect?.cancel()
            self.reconnect = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self, !self.stopped else { return }
                self.controller.startListening()
            }
        }
        controller.startListening()
        startupCheck = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, !self.receivedResponse else { return }
            self.statusMessage = "Media connection unavailable"
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }

    private func receive(_ info: TrackInfo?) {
        receivedResponse = true
        payload = info?.payload
        title = payload?.title ?? ""
        artist = payload?.artist ?? ""
        album = payload?.album ?? ""
        applicationName = payload?.applicationName ?? ""
        artwork = payload?.artwork
        isPlaying = payload?.isPlaying ?? false
        duration = Self.nonnegative((payload?.durationMicros ?? 0) / 1_000_000)
        statusMessage = title.isEmpty ? "Play something in your music app" : ""
        updateProgress()
    }

    private func updateProgress() {
        let position = payload?.currentElapsedTime ?? ((payload?.elapsedTimeMicros ?? 0) / 1_000_000)
        elapsed = Self.nonnegative(position)
        if duration > 0 { elapsed = min(elapsed, duration) }
    }

    private static func nonnegative(_ value: Double) -> Double { value.isFinite ? max(0, value) : 0 }

    static func timeLabel(_ value: Double) -> String {
        let seconds = Int(min(nonnegative(value), Double(Int32.max)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    func openPlayer() {
        guard let id = payload?.bundleIdentifier,
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: .init())
    }

    func stop() {
        stopped = true
        reconnect?.cancel()
        startupCheck?.cancel()
        timer?.invalidate()
        controller.stopListening()
    }

    func togglePlayPause() {
        if nativeSendCommand?(2, nil) != true { controller.togglePlayPause() }
    }
    func nextTrack() {
        if nativeSendCommand?(4, nil) != true { controller.nextTrack() }
    }
    func previousTrack() {
        if nativeSendCommand?(5, nil) != true { controller.previousTrack() }
    }
}
