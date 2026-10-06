import Foundation

/// VAST document for the lab mid-roll.
let midrollVastURL = URL(string: "http://127.0.0.1:8083/vast/midroll.xml")

/// One linear creative and the film position it interrupts.
struct Midroll {
    /// Film position where the creative belongs, in milliseconds.
    var cueMs: Int

    /// Progressive file the engine plays for the creative.
    var mediaUrl: String
}

private let clockPattern = try? NSRegularExpression(
    pattern: #"timeOffset="(\d{2}):(\d{2}):(\d{2})\.(\d{3})""#
)
private let mediaPattern = try? NSRegularExpression(
    pattern: #"<MediaFile\b[^>]*>\s*<!\[CDATA\[(https?://[^\]\s]+)\]\]>\s*</MediaFile>"#
)

/// Reads the cue and the media file. An impression URL is not a media file.
func readMidroll(_ xml: String) -> Midroll? {
    guard let clockPattern, let mediaPattern else {
        return nil
    }
    let range = NSRange(xml.startIndex..., in: xml)
    guard
        let time = clockPattern.firstMatch(in: xml, range: range),
        let media = mediaPattern.firstMatch(in: xml, range: range),
        let hours = capture(time, at: 1, in: xml).flatMap(Int.init),
        let minutes = capture(time, at: 2, in: xml).flatMap(Int.init),
        let seconds = capture(time, at: 3, in: xml).flatMap(Int.init),
        let millis = capture(time, at: 4, in: xml).flatMap(Int.init),
        let mediaUrl = capture(media, at: 1, in: xml),
        !mediaUrl.isEmpty
    else {
        return nil
    }
    let cueMs = ((hours * 60 * 60) + (minutes * 60) + seconds) * 1000 + millis
    return Midroll(cueMs: cueMs, mediaUrl: mediaUrl)
}

/// The film has reached the cue, within a one second window.
func resumedAtCue(positionMs: Int, cueMs: Int) -> Bool {
    positionMs + 1_000 >= cueMs
}

/// Playing playback has reached the cue. A paused or ended film has not.
func playingAtCue(currentTimeMs: Int, cueMs: Int, paused: Bool, ended: Bool) -> Bool {
    if paused || ended || cueMs < 0 || currentTimeMs < 0 {
        return false
    }
    return currentTimeMs >= cueMs
}

/// Loads the VAST document. A redirect or a failed request is no creative.
func fetchMidroll() async -> Midroll? {
    guard let midrollVastURL else {
        return nil
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 2
    configuration.timeoutIntervalForResource = 2
    let loader = MidrollLoader()
    let session = URLSession(configuration: configuration, delegate: loader, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    var request = URLRequest(url: midrollVastURL, timeoutInterval: 2)
    request.httpMethod = "GET"
    do {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        guard let xml = String(data: data, encoding: .utf8) else {
            return nil
        }
        return readMidroll(xml)
    } catch {
        return nil
    }
}

private func capture(_ match: NSTextCheckingResult, at index: Int, in text: String) -> String? {
    let range = match.range(at: index)
    guard range.location != NSNotFound, let span = Range(range, in: text) else {
        return nil
    }
    return String(text[span])
}

/// Refuses redirects so a VAST response cannot be swapped for another URL.
private final class MidrollLoader: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
