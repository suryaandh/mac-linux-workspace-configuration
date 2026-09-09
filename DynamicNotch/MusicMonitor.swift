import Cocoa

class MusicMonitor {

    static let shared = MusicMonitor()
    private init() {}

    private var timer: Timer?
    private var lastTrackID: String?

    private static let mediaRemoteHandle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkNowPlaying()
        }
        timer?.fire()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkNowPlaying() {
        guard let handle = MusicMonitor.mediaRemoteHandle,
              let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else { return }

        typealias GetNowPlayingInfoFunc = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
        let getNowPlayingInfo = unsafeBitCast(sym, to: GetNowPlayingInfoFunc.self)

        getNowPlayingInfo(DispatchQueue.main) { [weak self] info in
            guard let info = info,
                  let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
                  let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String else { return }

            let trackID = "\(title)-\(artist)"
            guard trackID != self?.lastTrackID else { return }
            self?.lastTrackID = trackID

            var artwork: NSImage?
            if let artworkData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                artwork = NSImage(data: artworkData)
            }

            self?.notify(title: title, artist: artist, artwork: artwork)
        }
    }

    private func notify(title: String, artist: String, artwork: NSImage?) {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appDelegate.notchWindowController?.expand(with: .music(title: title, artist: artist, artwork: artwork))
    }
}
