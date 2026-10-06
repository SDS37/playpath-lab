import UIKit

/// Named colors for the UIKit screen, matching the lab control tokens.
enum PlayerColors {
    static let background = UIColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)
    static let control = UIColor(red: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255, alpha: 1)
    static let text = UIColor(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF4 / 255, alpha: 1)
    static let accent = UIColor(red: 0x8E / 255, green: 0xB6 / 255, blue: 0xFF / 255, alpha: 1)
    static let danger = UIColor(red: 1, green: 0xB4 / 255, blue: 0xB4 / 255, alpha: 1)
}

/// Play, pause, seek, and time for one session snapshot. This view does not import AVFoundation.
final class PlaybackControlsView: UIView {
    /// Called when the visible action is Play.
    var onPlay: (() -> Void)?

    /// Called when the visible action is Pause.
    var onPause: (() -> Void)?

    /// Called with a film position in milliseconds. Ignored while a creative is playing.
    var onSeek: ((Int) -> Void)?

    /// Called with the next captions state. The session selects the menu text track.
    var onCaptions: ((Bool) -> Void)?

    private let button = UIButton(type: .system)
    private let captionsButton = UIButton(type: .system)
    private let seek = UISlider()
    private let timeLabel = UILabel()
    private let stallLabel = UILabel()
    private let errorLabel = UILabel()
    private var showsPause = false
    private var captionsOn = true
    private var seekLocked = false
    private let barSpacing: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = PlayerColors.control
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = PlayerColors.accent
        configuration.baseForegroundColor = PlayerColors.background
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.preferredFont(forTextStyle: .body)
            return outgoing
        }
        button.configuration = configuration
        button.addTarget(self, action: #selector(tap), for: .touchUpInside)
        captionsButton.configuration = configuration
        captionsButton.addTarget(self, action: #selector(toggleCaptions), for: .touchUpInside)
        captionsButton.configuration?.title = "Captions"

        seek.minimumTrackTintColor = PlayerColors.accent
        seek.maximumTrackTintColor = PlayerColors.text.withAlphaComponent(0.35)
        seek.thumbTintColor = PlayerColors.accent
        seek.minimumValue = 0
        seek.maximumValue = 1
        seek.isEnabled = false
        seek.accessibilityLabel = "Seek"
        seek.addTarget(self, action: #selector(slide), for: .valueChanged)

        timeLabel.textColor = PlayerColors.text
        timeLabel.font = .preferredFont(forTextStyle: .body)

        stallLabel.text = "Buffering"
        stallLabel.textColor = PlayerColors.text
        stallLabel.font = .preferredFont(forTextStyle: .body)
        stallLabel.isHidden = true

        errorLabel.textColor = PlayerColors.danger
        errorLabel.font = .preferredFont(forTextStyle: .body)
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        let buttonRow = UIStackView(arrangedSubviews: [button, captionsButton, UIView()])
        buttonRow.spacing = barSpacing
        buttonRow.axis = .horizontal
        let stack = UIStackView(arrangedSubviews: [buttonRow, seek, timeLabel, stallLabel, errorLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = barSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: barSpacing),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: barSpacing),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -barSpacing),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -barSpacing),
        ])
        apply(PlaybackSnapshot())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// Draws `snapshot`. Pause is visible while playback is playing or seeking.
    func apply(_ snapshot: PlaybackSnapshot) {
        showsPause = snapshot.playbackState == .playing || snapshot.playbackState == .seeking
        let title = showsPause ? "Pause" : "Play"
        button.configuration?.title = title
        button.accessibilityLabel = title
        captionsOn = snapshot.captions
        captionsButton.accessibilityLabel = "Captions"
        captionsButton.accessibilityValue = snapshot.captions ? "on" : "off"
        seekLocked = snapshot.adPlaying
        let duration = max(snapshot.durationMs, 0)
        seek.isEnabled = !seekLocked && duration > 0
        seek.maximumValue = Float(duration > 0 ? duration : 1)
        if !seek.isTracking {
            let position = min(max(snapshot.positionMs, 0), duration)
            seek.value = Float(duration > 0 ? position : 0)
        }
        seek.accessibilityValue = formatTime(snapshot.positionMs)
        let prefix = snapshot.adPlaying ? "Ad " : ""
        timeLabel.text = "\(prefix)\(formatTime(snapshot.positionMs)) / \(formatTime(snapshot.durationMs))"
        stallLabel.isHidden = !snapshot.isStalled
        errorLabel.text = snapshot.error
        errorLabel.isHidden = snapshot.error == nil
    }

    @objc private func toggleCaptions() {
        onCaptions?(!captionsOn)
    }

    @objc private func tap() {
        if showsPause {
            onPause?()
        } else {
            onPlay?()
        }
    }

    @objc private func slide() {
        if seekLocked || !seek.isEnabled {
            return
        }
        onSeek?(Int(seek.value.rounded()))
    }
}

private func formatTime(_ positionMs: Int) -> String {
    let totalSeconds = max(0, positionMs / 1_000)
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return "\(minutes):\(String(format: "%02d", seconds))"
}
