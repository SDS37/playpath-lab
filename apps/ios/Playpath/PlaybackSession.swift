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
    var adPlaying = false
    var height = 0
    var bandwidthBps = 0
    var captions = true
    var caption = ""
    var error: String?
}

private enum AdPhase {
    case off
    case creative
    case resume
}

private let creativeTimeoutNanoseconds: UInt64 = 5_000_000_000

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
    private var replaying = false
    private var wantsPlayback = false
    private var seekGeneration = 0
    private var cueMs: Int?
    private var creativeURL: URL?
    private var filmCueMs: Int?
    private var filmCueSeeked = false
    private var adPlayed = false
    private var adPhase = AdPhase.off
    private var adAttempt = 0
    private var creativeAssigned = false
    private var creativeStarted = false
    private var startupLogged = false
    private var loadedAt = Date()
    private var captions = true
    private var captionText = ""
    private var captionGeneration = 0
    private var audioGeneration = 0
    private let captionOutput = CaptionOutput()
    private var activeCaptionOutput: AVPlayerItemLegibleOutput?
    private var timeObserver: Any?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var accessLogObserver: NSObjectProtocol?
    private var presentationObservation: NSKeyValueObservation?

    init() {
        captionOutput.onCues = { [weak self] output, text in
            self?.noteCaption(text, from: output)
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            self?.publish()
        }
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.tick()
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
        replaying = false
        wantsPlayback = true
        seekGeneration += 1
        failureMessage = nil
        sessionId = UUID().uuidString
        recordedHeight = 0
        recordedBandwidth = 0
        cueMs = nil
        creativeURL = nil
        filmCueMs = nil
        filmCueSeeked = false
        adPlayed = false
        adPhase = .off
        adAttempt += 1
        creativeAssigned = false
        creativeStarted = false
        startupLogged = false
        loadedAt = Date()
        let attempt = adAttempt
        let item = AVPlayerItem(url: url)
        observe(item)
        player.replaceCurrentItem(with: item)
        player.play()
        publish()
        readCue(attempt)
    }

    /// Resumes playback. After the item ends, or after a failed item, playback starts again.
    func play() {
        wantsPlayback = true
        if adPhase != .off {
            player.play()
            publish()
            return
        }
        if player.currentItem?.status == .failed, let loadedURL {
            play(url: loadedURL)
            return
        }
        if didPlayToEnd {
            didPlayToEnd = false
            seeking = false
            replaying = true
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                DispatchQueue.main.async {
                    guard let self, finished else {
                        return
                    }
                    if self.milliseconds(self.player.currentTime()) < 1_000 {
                        self.replaying = false
                    }
                    self.publish()
                }
            }
            player.play()
            publish()
            return
        }
        player.play()
        publish()
        if atCue() {
            playCreative()
        }
    }

    /// Selects or clears the text track the menu already contains.
    func setCaptions(_ enabled: Bool) {
        captions = enabled
        if !enabled {
            captionText = ""
        }
        if adPhase != .creative, let item = player.currentItem {
            selectCaptions(on: item)
        }
        publish()
    }

    /// Pauses playback.
    func pause() {
        wantsPlayback = false
        player.pause()
        publish()
    }

    /// Seeks to `positionMs` on the film timeline.
    func seek(to positionMs: Int) {
        if adPhase != .off {
            return
        }
        seekGeneration += 1
        let generation = seekGeneration
        let resumePlaying = wantsPlayback || seeking
        seeking = resumePlaying
        didPlayToEnd = false
        let time = CMTime(seconds: Double(positionMs) / 1000, preferredTimescale: 1000)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, generation == self.seekGeneration else {
                    return
                }
                self.seeking = false
                if finished, self.atCue() {
                    self.playCreative()
                }
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
        let output = AVPlayerItemLegibleOutput()
        output.suppressesPlayerRendering = true
        output.setDelegate(captionOutput, queue: .main)
        item.add(output)
        activeCaptionOutput = output
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            self?.itemEnded(note.object as? AVPlayerItem)
        }
        failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] note in
            self?.itemFailed(note.object as? AVPlayerItem)
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
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.noteStatus(of: item)
            }
            return
        }
        guard item === player.currentItem else {
            return
        }
        if item.status == .readyToPlay {
            if adPhase == .creative {
                creativeStarted = true
            } else {
                selectCaptions(on: item)
                selectAudio(on: item)
                if adPhase == .resume {
                    arriveAtCue()
                }
            }
        }
        if item.status == .failed {
            if adPhase == .creative {
                if creativeFailure() {
                    resumeFilm(completed: false)
                }
                return
            }
            if adPhase == .resume {
                adPhase = .off
            }
            failureMessage = "Playback failed."
        }
        publish()
    }

    private func itemEnded(_ item: AVPlayerItem?) {
        guard item === player.currentItem else {
            return
        }
        if adPhase == .creative, creativeAssigned {
            creativeStarted = true
            resumeFilm(completed: true)
            return
        }
        didPlayToEnd = true
        seeking = false
        publish()
    }

    private func itemFailed(_ item: AVPlayerItem?) {
        guard item === player.currentItem else {
            return
        }
        if adPhase == .creative {
            if creativeFailure() {
                resumeFilm(completed: false)
            }
            return
        }
        if adPhase == .resume {
            adPhase = .off
        }
        failureMessage = "Playback failed."
        publish()
    }

    /// Records the rung `AVPlayer` chose. Controls do not read it and do not pick one.
    private func rememberVariant(of item: AVPlayerItem) {
        guard adPhase == .off, item === player.currentItem else {
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
        print(bitrateEvent(
            sessionId: sessionId,
            at: utcTimestamp(),
            positionMs: milliseconds(player.currentTime()),
            height: height,
            bandwidthBps: nextBandwidth
        ))
        publish()
    }

    private func tick() {
        if replaying, milliseconds(player.currentTime()) < 1_000 {
            replaying = false
        }
        if adPhase == .resume {
            arriveAtCue()
        } else if adPhase == .off, atCue() {
            playCreative()
        }
        publish()
    }

    private func readCue(_ attempt: Int) {
        Task { [weak self] in
            let midroll = await fetchMidroll()
            guard let self else {
                return
            }
            await MainActor.run {
                guard attempt == self.adAttempt, let midroll, let url = URL(string: midroll.mediaUrl) else {
                    return
                }
                self.cueMs = midroll.cueMs
                self.creativeURL = url
            }
        }
    }

    private func atCue() -> Bool {
        if replaying || seeking || adPlayed || adPhase != .off {
            return false
        }
        guard let cueMs, creativeURL != nil else {
            return false
        }
        let ended = didPlayToEnd || player.currentItem?.status == .failed
        return playingAtCue(
            currentTimeMs: milliseconds(player.currentTime()),
            cueMs: cueMs,
            paused: !wantsPlayback,
            ended: ended
        )
    }

    private func creativeFailure() -> Bool {
        guard creativeAssigned else {
            return false
        }
        guard let item = player.currentItem else {
            return true
        }
        let current = (item.asset as? AVURLAsset)?.url.absoluteString
        return current == nil || current == creativeURL?.absoluteString
    }

    private func playCreative() {
        guard !adPlayed, adPhase == .off, let creativeURL else {
            return
        }
        adPlayed = true
        adPhase = .creative
        captionText = ""
        creativeAssigned = false
        creativeStarted = false
        let attempt = adAttempt
        let item = AVPlayerItem(url: creativeURL)
        observe(item)
        player.replaceCurrentItem(with: item)
        creativeAssigned = true
        player.play()
        logAd("start")
        failIfStuck(attempt, phase: .creative)
        publish()
    }

    private func resumeFilm(completed: Bool) {
        guard adPhase == .creative else {
            return
        }
        logAd(completed ? "complete" : "error")
        guard let loadedURL, let cueMs else {
            adPhase = .off
            failureMessage = "Playback failed."
            publish()
            return
        }
        adAttempt += 1
        let attempt = adAttempt
        // The player rate is already zero when the creative reaches its end.
        let resumePlaying = wantsPlayback
        adPhase = .resume
        creativeAssigned = false
        creativeStarted = false
        filmCueMs = cueMs
        filmCueSeeked = false
        didPlayToEnd = false
        seeking = false
        let item = AVPlayerItem(url: loadedURL)
        observe(item)
        player.replaceCurrentItem(with: item)
        if resumePlaying {
            player.play()
        } else {
            player.pause()
        }
        failIfStuck(attempt, phase: .resume)
        publish()
    }

    private func arriveAtCue() {
        guard adPhase == .resume else {
            return
        }
        let position = milliseconds(player.currentTime())
        if let filmCueMs, !resumedAtCue(positionMs: position, cueMs: filmCueMs) {
            if !filmCueSeeked, player.currentItem?.status == .readyToPlay {
                filmCueSeeked = true
                let time = CMTime(seconds: Double(filmCueMs) / 1000, preferredTimescale: 1000)
                player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            return
        }
        filmCueMs = nil
        adPhase = .off
    }

    private func failIfStuck(_ attempt: Int, phase: AdPhase) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: creativeTimeoutNanoseconds)
            guard let self else {
                return
            }
            await MainActor.run {
                guard attempt == self.adAttempt, self.adPhase == phase else {
                    return
                }
                if phase == .creative, !self.creativeStarted {
                    self.resumeFilm(completed: false)
                    return
                }
                if phase == .resume {
                    self.adPhase = .off
                    self.failureMessage = "Playback failed."
                    self.publish()
                }
            }
        }
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
            adPlaying: adPhase != .off,
            height: recordedHeight,
            bandwidthBps: recordedBandwidth,
            captions: captions,
            caption: adPhase == .off && captions ? captionText : "",
            error: failureMessage
        )
        snapshot = next
        onSnapshot?(next)
        noteStartup()
    }

    private func noteStartup() {
        guard !startupLogged, adPhase == .off, player.timeControlStatus == .playing, let loadedURL else {
            return
        }
        startupLogged = true
        let elapsed = Int(Date().timeIntervalSince(loadedAt) * 1000)
        print(startupEvent(
            sessionId: sessionId,
            at: utcTimestamp(),
            positionMs: milliseconds(player.currentTime()),
            startupMs: elapsed,
            manifestUrl: loadedURL.absoluteString
        ))
    }

    private func logAd(_ action: String) {
        print(adEvent(
            sessionId: sessionId,
            at: utcTimestamp(),
            positionMs: cueMs ?? 0,
            action: action
        ))
    }

    private func noteCaption(_ text: String, from output: AVPlayerItemLegibleOutput) {
        if output !== activeCaptionOutput || adPhase == .creative || !captions || captionText == text {
            return
        }
        captionText = text
        publish()
    }

    private func selectCaptions(on item: AVPlayerItem) {
        captionGeneration += 1
        let generation = captionGeneration
        let show = captions
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let group = try? await item.asset.loadMediaSelectionGroup(for: .legible)
            guard generation == self.captionGeneration, self.player.currentItem === item else {
                return
            }
            guard let group else {
                return
            }
            if show, self.captions {
                let english = group.options.first { option in
                    option.extendedLanguageTag == "en" ||
                        option.extendedLanguageTag == "eng" ||
                        option.locale?.language.languageCode?.identifier == "en"
                }
                if let option = english ?? group.defaultOption ?? group.options.first {
                    item.select(option, in: group)
                }
            } else {
                item.select(nil, in: group)
                self.captionText = ""
                self.publish()
            }
        }
    }

    private func selectAudio(on item: AVPlayerItem) {
        audioGeneration += 1
        let generation = audioGeneration
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let group = try? await item.asset.loadMediaSelectionGroup(for: .audible)
            guard generation == self.audioGeneration, self.player.currentItem === item else {
                return
            }
            guard let group else {
                return
            }
            let english = group.options.first { option in
                option.extendedLanguageTag == "en" ||
                    option.extendedLanguageTag == "eng" ||
                    option.locale?.language.languageCode?.identifier == "en"
            }
            if let option = english ?? group.defaultOption ?? group.options.first {
                item.select(option, in: group)
            }
        }
    }

    private func playbackState() -> PlaybackState {
        if didPlayToEnd {
            return .ended
        }
        if player.timeControlStatus == .paused {
            return .paused
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

private final class CaptionOutput: NSObject, AVPlayerItemLegibleOutputPushDelegate {
    var onCues: ((AVPlayerItemLegibleOutput, String) -> Void)?

    func legibleOutput(
        _ output: AVPlayerItemLegibleOutput,
        didOutputAttributedStrings strings: [NSAttributedString],
        nativeSampleBuffers nativeSamples: [Any],
        forItemTime itemTime: CMTime
    ) {
        onCues?(output, strings.map(\.string).joined(separator: "\n"))
    }
}
