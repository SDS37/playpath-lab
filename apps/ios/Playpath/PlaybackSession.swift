import AVFoundation
import Foundation

/// Engine states the controls can draw.
enum PlaybackState {
    case paused
    case playing
    case seeking
    case ended
}

/// The latest engine snapshot. Controls draw this and do not read the player.
struct PlaybackSnapshot {
    var playbackState: PlaybackState = .paused
    var isStalled = false
    var positionMs = 0
    var durationMs = 0
    var height = 0
    var bandwidthBps = 0
    var error: String?
}

/// Plays a clear HLS URL and publishes engine state.
///
/// FairPlay will attach an `AVContentKeySession` to the asset when an FPS certificate exists.
/// This PoC does not create that session, and it does not report a FairPlay result.
final class PlaybackSession {
    /// The latest snapshot.
    private(set) var snapshot = PlaybackSnapshot()

    /// Called on the main queue after each snapshot.
    var onSnapshot: ((PlaybackSnapshot) -> Void)?

    private let player = AVPlayer()
    private var loadedURL: URL?
    private var didPlayToEnd = false
    private var seeking = false
    private var failureMessage: String?
    private var sessionId = ""
    private var recordedHeight = 0
    private var recordedBandwidth = 0
    private var timeObserver: Any?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var accessLogObserver: NSObjectProtocol?
    private var presentationObservation: NSKeyValueObservation?

    init() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            self?.publish()
        }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.publish()
        }
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeControlObservation?.invalidate()
        itemStatusObservation?.invalidate()
        removeItemObservers()
    }

    /// Shows frames from this session in `layer`.
    func attach(to layer: AVPlayerLayer) {
        layer.player = player
        layer.videoGravity = .resizeAspect
    }

    /// Loads `url` and starts playback.
    func play(url: URL) {
        loadedURL = url
        didPlayToEnd = false
        seeking = false
        failureMessage = nil
        sessionId = UUID().uuidString
        recordedHeight = 0
        recordedBandwidth = 0
        let item = AVPlayerItem(url: url)
        observe(item)
        player.replaceCurrentItem(with: item)
        player.play()
        publish()
    }

    /// Resumes playback. After the item ends, or after a failed item, playback starts again.
    func play() {
        if player.currentItem?.status == .failed, let loadedURL {
            play(url: loadedURL)
            return
        }
        if didPlayToEnd {
            didPlayToEnd = false
            seeking = false
            player.seek(to: .zero)
        }
        player.play()
        publish()
    }

    /// Pauses playback.
    func pause() {
        player.pause()
        publish()
    }

    /// Seeks to `positionMs` on the film timeline.
    func seek(to positionMs: Int) {
        let resumePlaying = player.timeControlStatus == .playing || seeking
        seeking = resumePlaying
        didPlayToEnd = false
        let time = CMTime(seconds: Double(positionMs) / 1000, preferredTimescale: 1000)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, finished else {
                    return
                }
                self.seeking = false
                self.publish()
            }
        }
        publish()
    }

    private func observe(_ item: AVPlayerItem) {
        itemStatusObservation?.invalidate()
        removeItemObservers()
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            self?.noteStatus(of: item)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.didPlayToEnd = true
            self?.seeking = false
            self?.publish()
        }
        failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.failureMessage = "Playback failed."
            self?.publish()
        }
        accessLogObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: item,
            queue: .main
        ) { [weak self] note in
            guard let item = note.object as? AVPlayerItem else {
                return
            }
            self?.rememberVariant(of: item)
        }
        presentationObservation = item.observe(\.presentationSize, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                self?.rememberVariant(of: item)
            }
        }
    }

    private func removeItemObservers() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let failedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
        }
        if let accessLogObserver {
            NotificationCenter.default.removeObserver(accessLogObserver)
        }
        endObserver = nil
        failedObserver = nil
        accessLogObserver = nil
        presentationObservation?.invalidate()
        presentationObservation = nil
    }

    private func noteStatus(of item: AVPlayerItem) {
        if item.status == .failed {
            failureMessage = "Playback failed."
        }
        publish()
    }

    /// Records the rung `AVPlayer` chose. Controls do not read it and do not pick one.
    private func rememberVariant(of item: AVPlayerItem) {
        let bitrate = item.accessLog()?.events.last?.indicatedBitrate
        let bandwidth = bitrate.map { value -> Int in
            guard value.isFinite, value > 0 else {
                return 0
            }
            return Int(value.rounded())
        } ?? 0
        let presentationHeight = Int(item.presentationSize.height.rounded())
        let height = presentationHeight > 0 ? presentationHeight : recordedHeight
        let nextBandwidth = bandwidth > 0 ? bandwidth : recordedBandwidth
        guard height > 0 || nextBandwidth > 0 else {
            return
        }
        guard height != recordedHeight || nextBandwidth != recordedBandwidth else {
            return
        }
        recordedHeight = height
        recordedBandwidth = nextBandwidth
        logBitrate(height: height, bandwidthBps: nextBandwidth)
        publish()
    }

    private func logBitrate(height: Int, bandwidthBps: Int) {
        let clock = ISO8601DateFormatter()
        var line = "{\"version\":1,\"titleId\":\"playpath-bars\""
        line += ",\"sessionId\":\"\(sessionId)\",\"platform\":\"ios\",\"engine\":\"avplayer\""
        line += ",\"event\":\"bitrate\",\"at\":\"\(clock.string(from: Date()))\""
        line += ",\"positionMs\":\(snapshot.positionMs)"
        if height > 0 {
            line += ",\"height\":\(height)"
        }
        if bandwidthBps > 0 {
            line += ",\"bandwidthBps\":\(bandwidthBps)"
        }
        line += "}"
        print(line)
    }

    private func publish() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.publish()
            }
            return
        }
        let item = player.currentItem
        let next = PlaybackSnapshot(
            playbackState: playbackState(),
            isStalled: player.timeControlStatus == .waitingToPlayAtSpecifiedRate && !seeking,
            positionMs: milliseconds(player.currentTime()),
            durationMs: milliseconds(item?.duration ?? .indefinite),
            height: recordedHeight,
            bandwidthBps: recordedBandwidth,
            error: failureMessage
        )
        snapshot = next
        onSnapshot?(next)
    }

    private func playbackState() -> PlaybackState {
        if didPlayToEnd {
            return .ended
        }
        if seeking {
            return .seeking
        }
        switch player.timeControlStatus {
        case .playing, .waitingToPlayAtSpecifiedRate:
            return .playing
        case .paused:
            return .paused
        @unknown default:
            return .paused
        }
    }

    private func milliseconds(_ time: CMTime) -> Int {
        guard time.isNumeric else {
            return 0
        }
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, seconds > 0 else {
            return 0
        }
        return Int((seconds * 1000).rounded())
    }
}
