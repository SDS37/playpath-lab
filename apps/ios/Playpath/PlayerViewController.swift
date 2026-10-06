import AVFoundation
import UIKit

/// The clear HLS screen. The picture is an `AVPlayerLayer`. The system transport bar is not used.
final class PlayerViewController: UIViewController {
    private let session = PlaybackSession()
    private let videoView = PlayerLayerView()
    private let controls = PlaybackControlsView()
    private var backgroundObserver: NSObjectProtocol?
    private let screenPadding: CGFloat = 12

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = PlayerColors.background
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.accessibilityLabel = "playpath-bars"
        videoView.isAccessibilityElement = true
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoView)
        view.addSubview(controls)
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: screenPadding),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: screenPadding),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -screenPadding),
            videoView.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -screenPadding),
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: screenPadding),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -screenPadding),
            controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -screenPadding),
        ])
        if let layer = videoView.playerLayer {
            session.attach(to: layer)
        }
        session.onSnapshot = { [weak self] snapshot in
            self?.controls.apply(snapshot)
            self?.showCaption(snapshot.caption)
        }
        controls.onPlay = { [weak self] in
            self?.session.play()
        }
        controls.onCaptions = { [weak self] enabled in
            self?.session.setCaptions(enabled)
        }
        controls.onPause = { [weak self] in
            self?.session.pause()
        }
        controls.onSeek = { [weak self] positionMs in
            self?.session.seek(to: positionMs)
        }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.session.pause()
        }
        guard let url = URL(string: "http://127.0.0.1:8084/master.m3u8") else {
            return
        }
        session.play(url: url)
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }

    private func showCaption(_ text: String) {
        videoView.showCaption(text)
        videoView.accessibilityValue = text.isEmpty ? nil : text
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }
}

/// Hosts the `AVPlayerLayer` that shows frames. Transport controls stay off.
private final class PlayerLayerView: UIView {
    private let captionLabel = UILabel()

    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer? {
        layer as? AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        captionLabel.textColor = PlayerColors.text
        captionLabel.backgroundColor = PlayerColors.background.withAlphaComponent(0.72)
        captionLabel.textAlignment = .center
        captionLabel.numberOfLines = 0
        captionLabel.font = .preferredFont(forTextStyle: .title3)
        captionLabel.isHidden = true
        captionLabel.isUserInteractionEnabled = false
        addSubview(captionLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let videoRect = playerLayer?.videoRect, !videoRect.isEmpty, !captionLabel.isHidden else {
            return
        }
        let inset: CGFloat = 12
        let maxWidth = max(0, videoRect.width - inset * 2)
        let fitted = captionLabel.sizeThatFits(CGSize(width: maxWidth, height: videoRect.height))
        let width = min(fitted.width, maxWidth)
        let height = min(fitted.height, videoRect.height)
        captionLabel.frame = CGRect(
            x: videoRect.midX - width / 2,
            y: videoRect.maxY - height - inset,
            width: width,
            height: height
        )
    }

    func showCaption(_ text: String) {
        captionLabel.text = text
        captionLabel.isHidden = text.isEmpty
        setNeedsLayout()
    }
}
