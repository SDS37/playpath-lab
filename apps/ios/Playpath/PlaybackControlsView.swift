import UIKit

/// Named colors for the UIKit screen, matching the lab control tokens.
enum PlayerColors {
    static let background = UIColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)
    static let control = UIColor(red: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255, alpha: 1)
    static let text = UIColor(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF4 / 255, alpha: 1)
    static let accent = UIColor(red: 0x8E / 255, green: 0xB6 / 255, blue: 0xFF / 255, alpha: 1)
    static let danger = UIColor(red: 1, green: 0xB4 / 255, blue: 0xB4 / 255, alpha: 1)
}

/// Play and pause for one session snapshot. This view does not import AVFoundation.
final class PlaybackControlsView: UIView {
    /// Called when the visible action is Play.
    var onPlay: (() -> Void)?

    /// Called when the visible action is Pause.
    var onPause: (() -> Void)?

    private let button = UIButton(type: .system)
    private let errorLabel = UILabel()
    private var showsPause = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = PlayerColors.accent
        configuration.baseForegroundColor = PlayerColors.background
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        button.configuration = configuration
        button.addTarget(self, action: #selector(tap), for: .touchUpInside)

        errorLabel.textColor = PlayerColors.danger
        errorLabel.font = .preferredFont(forTextStyle: .body)
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        let stack = UIStackView(arrangedSubviews: [button, errorLabel])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
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
        errorLabel.text = snapshot.error
        errorLabel.isHidden = snapshot.error == nil
    }

    @objc private func tap() {
        if showsPause {
            onPause?()
        } else {
            onPlay?()
        }
    }
}
