import UIKit
import WebKit

/// Lays an HTML page out at phone width in an off-screen web view and turns it into
/// a PDF or a single long image, both of which open straight from a chat or email.
@MainActor
final class PageRenderer: NSObject, WKNavigationDelegate {
    enum RenderError: LocalizedError {
        case loadFailed, tooLong

        var errorDescription: String? {
            switch self {
            case .loadFailed: "The page couldn't be laid out. Try again."
            case .tooLong: "The trip is too long for one image. Pick fewer cities, or export as PDF."
            }
        }
    }

    /// Phone-ish reading width; the page's own CSS takes it from here.
    static let width: CGFloat = 430
    /// Longer images get unreliable to render and to view in chat apps.
    private static let maxImageHeight: CGFloat = 20_000

    private var webView: WKWebView?
    private var loaded: CheckedContinuation<Void, Error>?

    /// One tall page, so it reads like the web page with no page breaks.
    func pdf(html: String) async throws -> Data {
        let view = try await layOut(html)
        defer { tearDown() }
        let config = WKPDFConfiguration()
        config.rect = CGRect(origin: .zero, size: view.scrollView.contentSize)
        return try await view.pdf(configuration: config)
    }

    /// The whole page as one PNG at 3x.
    func image(html: String) async throws -> Data {
        let view = try await layOut(html)
        defer { tearDown() }
        let size = view.scrollView.contentSize
        guard size.height <= Self.maxImageHeight else { throw RenderError.tooLong }
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: size)
        config.afterScreenUpdates = true
        let image = try await view.takeSnapshot(configuration: config)
        guard let data = image.pngData() else { throw RenderError.loadFailed }
        return data
    }

    // MARK: Layout

    private func layOut(_ html: String) async throws -> WKWebView {
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: Self.width, height: 800))
        // Exports always use the light look, whatever the phone's setting.
        view.overrideUserInterfaceStyle = .light
        view.isOpaque = false
        view.navigationDelegate = self
        // Snapshots need the view in a window; keep it out of sight.
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        view.frame.origin = CGPoint(x: -Self.width * 3, y: 0)
        window?.addSubview(view)
        webView = view

        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            loaded = c
            view.loadHTMLString(html, baseURL: nil)
        }
        // Grow the view to the full page so everything is laid out and drawn.
        let height = (try? await view.evaluateJavaScript("document.documentElement.scrollHeight") as? CGFloat) ?? 800
        view.frame.size.height = max(height, 100)
        try? await Task.sleep(for: .milliseconds(250))
        return view
    }

    private func tearDown() {
        webView?.removeFromSuperview()
        webView = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume(); loaded = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: RenderError.loadFailed); loaded = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: RenderError.loadFailed); loaded = nil
    }
}
