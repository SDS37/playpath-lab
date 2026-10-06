import AVFoundation
import UIKit

/// The clear HLS screen. The picture is an `AVPlayerLayer`. The system transport bar is not used.
final class PlayerViewController: UIViewController {
    private let session = PlaybackSession()
    private let videoView = PlayerLayerView()
    private let captionLabel = UILabel()
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
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.textColor = PlayerColors.text
        captionLabel.backgroundColor = PlayerColors.background.withAlphaComponent(0.72)
        captionLabel.textAlignment = .center
        captionLabel.numberOfLines = 0
        captionLabel.font = .preferredFont(forTextStyle: .title3)
        captionLabel.isHidden = true
        view.addSubview(videoView)
        videoView.addSubview(captionLabel)
        view.addSubview(controls)
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: screenPadding),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: screenPadding),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -screenPadding),
            videoView.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -screenPadding),
            captionLabel.leadingAnchor.constraint(equalTo: videoView.leadingAnchor, constant: screenPadding),
            captionLabel.trailingAnchor.constraint(equalTo: videoView.trailingAnchor, constant: -screenPadding),
            captionLabel.bottomAnchor.constraint(equalTo: videoView.bottomAnchor, constant: -screenPadding),
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
        captionLabel.text = text
        captionLabel.isHidden = text.isEmpty
        videoView.accessibilityValue = text.isEmpty ? nil : text
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }
}

/// Hosts the `AVPlayerLayer` that shows frames. Transport controls stay off.
private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer? {
        layer as? AVPlayerLayer
    }
}
