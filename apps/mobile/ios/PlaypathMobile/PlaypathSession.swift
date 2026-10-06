import AVFoundation
import Foundation

/// AVPlayer renders the picture. JavaScript never sees samples.
@objc(PlaypathSession)
final class PlaypathSession: NSObject {
    @objc var onSnapshot: ((NSDictionary) -> Void)?
    @objc var onPlaybackEvent: ((String) -> Void)?

    private let player = AVPlayer()
    private let picture = AVPlayerLayer()
    private var loadedURL: String?
    private var sessionId = ""
    private var loadedAt = Date()
    private var readyAt: Date?
    private var startupLogged = false
    private var seeking = false
    private var seekGeneration = 0
    private var didPlayToEnd = false
    private var wantsPlayback = false
    private var failureMessage: String?
    private var recordedHeight = 0
    private var recordedBandwidth = 0
    private var timeObserver: Any?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var accessLogObserver: NSObjectProtocol?
    private var presentationObservation: NSKeyValueObservation?
    private var released = false

    override init() {
        super.init()
        picture.player = player
        picture.videoGravity = .resizeAspect
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            self?.publish()
        }
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.publish()
        }
    }

    @objc func attach(to host: UIView) {
        if picture.superlayer !== host.layer {
            picture.removeFromSuperlayer()
            host.layer.addSublayer(picture)
        }
        picture.frame = host.bounds
    }

    @objc func layout(in host: UIView) {
        picture.frame = host.bounds
    }

    @objc func load(manifestUrl: String) {
        guard !released, !manifestUrl.isEmpty, manifestUrl != loadedURL else {
            return
        }
        guard let url = URL(string: manifestUrl) else {
            failureMessage = "Playback failed."
            publish()
            return
        }
        loadedURL = manifestUrl
        sessionId = UUID().uuidString
        loadedAt = Date()
        readyAt = nil
        startupLogged = false
        seeking = false
        didPlayToEnd = false
        failureMessage = nil
        recordedHeight = 0
        recordedBandwidth = 0
        let item = AVPlayerItem(url: url)
        observe(item)
        player.replaceCurrentItem(with: item)
        if wantsPlayback {
            player.play()
        }
        publish()
    }

    @objc func play() {
        guard !released else {
            return
        }
        wantsPlayback = true
        if didPlayToEnd {
            didPlayToEnd = false
            player.seek(to: .zero)
        }
        player.play()
        publish()
    }

    @objc func pause() {
        guard !released else {
            return
        }
        wantsPlayback = false
        player.pause()
        publish()
    }

    @objc func seek(positionMs: Int) {
        guard !released else {
            return
        }
        seekGeneration += 1
        let generation = seekGeneration
        didPlayToEnd = false
        seeking = player.timeControlStatus != .paused
        let time = CMTime(value: CMTimeValue(max(0, positionMs)), timescale: 1000)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.seekGeneration == generation else {
                    return
                }
                self.seeking = false
                self.publish()
            }
        }
        publish()
    }

    @objc func releasePlayer() {
        guard !released else {
            return
        }
        released = true
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        timeControlObservation?.invalidate()
        itemStatusObservation?.invalidate()
        removeItemObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        picture.removeFromSuperlayer()
    }

    private func observe(_ item: AVPlayerItem) {
        removeItemObservers()
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                self?.noteStatus(of: item)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.didPlayToEnd = true
            self?.player.pause()
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
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
    }

    private func noteStatus(of item: AVPlayerItem) {
        guard !released, item === player.currentItem else {
            return
        }
        if item.status == .readyToPlay, readyAt == nil {
            readyAt = Date()
        }
        if item.status == .failed {
            failureMessage = "Playback failed."
        }
        publish()
    }

    private func rememberVariant(of item: AVPlayerItem) {
        guard !released, item === player.currentItem else {
            return
        }
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
        emit(
            bitrateEvent(
                sessionId: sessionId,
                at: utcTimestamp(),
                positionMs: milliseconds(player.currentTime()),
                height: height,
                bandwidthBps: nextBandwidth
            )
        )
        publish()
    }

    private func publish() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.publish()
            }
            return
        }
        guard !released else {
            return
        }
        noteStartup()
        let item = player.currentItem
        let payload: [String: Any] = [
            "playbackState": playbackStateName(),
            "stalled": player.timeControlStatus == .waitingToPlayAtSpecifiedRate && !seeking,
            "adPlaying": false,
            "positionMs": milliseconds(player.currentTime()),
            "durationMs": milliseconds(item?.duration ?? .indefinite),
            "error": failureMessage ?? "",
        ]
        onSnapshot?(payload as NSDictionary)
    }

    private func noteStartup() {
        guard !startupLogged, player.timeControlStatus == .playing, let loadedURL else {
            return
        }
        if readyAt == nil, player.currentItem?.status == .readyToPlay {
            readyAt = Date()
        }
        startupLogged = true
        let frameAt = readyAt ?? Date()
        let startupMs = Int(frameAt.timeIntervalSince(loadedAt) * 1000)
        emit(
            startupEvent(
                sessionId: sessionId,
                at: utcTimestamp(),
                positionMs: milliseconds(player.currentTime()),
                startupMs: startupMs,
                manifestUrl: loadedURL
            )
        )
    }

    private func emit(_ json: String) {
        print(json)
        onPlaybackEvent?(json)
    }

    private func playbackStateName() -> String {
        if didPlayToEnd || failureMessage != nil {
            return "ended"
        }
        if player.timeControlStatus == .paused {
            return "paused"
        }
        if seeking {
            return "seeking"
        }
        switch player.timeControlStatus {
        case .playing, .waitingToPlayAtSpecifiedRate:
            return "playing"
        case .paused:
            return "paused"
        @unknown default:
            return "paused"
        }
    }

    private func milliseconds(_ time: CMTime) -> Int {
        guard time.isNumeric, time.seconds.isFinite else {
            return 0
        }
        return max(0, Int((time.seconds * 1000).rounded()))
    }
}

func utcTimestamp(_ date: Date = Date()) -> String {
    let clock = ISO8601DateFormatter()
    clock.timeZone = TimeZone(secondsFromGMT: 0)
    clock.formatOptions = [.withInternetDateTime]
    return clock.string(from: date)
}

func manifestUrlForEvent(_ url: String) -> String {
    let withoutFragment = url.split(separator: "#", maxSplits: 1).first.map(String.init) ?? url
    let withoutQuery = withoutFragment.split(separator: "?", maxSplits: 1).first.map(String.init) ?? withoutFragment
    guard let schemeEnd = withoutQuery.range(of: "://") else {
        return withoutQuery
    }
    let scheme = withoutQuery[..<schemeEnd.upperBound]
    let rest = withoutQuery[schemeEnd.upperBound...]
    guard let at = rest.firstIndex(of: "@") else {
        return withoutQuery
    }
    return String(scheme) + String(rest[rest.index(after: at)...])
}

func startupEvent(
    sessionId: String,
    at: String,
    positionMs: Int,
    startupMs: Int,
    manifestUrl: String
) -> String {
    var line = envelope(sessionId: sessionId, event: "startup", at: at, positionMs: positionMs)
    line += ",\"startupMs\":\(max(0, startupMs))"
    line += ",\"manifestUrl\":\(jsonString(manifestUrlForEvent(manifestUrl)))"
    line += "}"
    return line
}

func bitrateEvent(
    sessionId: String,
    at: String,
    positionMs: Int,
    height: Int,
    bandwidthBps: Int
) -> String {
    var line = envelope(sessionId: sessionId, event: "bitrate", at: at, positionMs: positionMs)
    if height > 0 {
        line += ",\"height\":\(height)"
    }
    if bandwidthBps > 0 {
        line += ",\"bandwidthBps\":\(bandwidthBps)"
    }
    line += "}"
    return line
}

private func envelope(sessionId: String, event: String, at: String, positionMs: Int) -> String {
    var line = "{\"version\":1,\"titleId\":\"playpath-bars\""
    line += ",\"sessionId\":\(jsonString(sessionId)),\"platform\":\"react-native\",\"engine\":\"avplayer\""
    line += ",\"event\":\(jsonString(event)),\"at\":\(jsonString(at))"
    line += ",\"positionMs\":\(max(0, positionMs))"
    return line
}

private func jsonString(_ value: String) -> String {
    var escaped = ""
    for character in value {
        switch character {
        case "\\":
            escaped += "\\\\"
        case "\"":
            escaped += "\\\""
        case "\n":
            escaped += "\\n"
        case "\r":
            escaped += "\\r"
        default:
            escaped.append(character)
        }
    }
    return "\"\(escaped)\""
}
