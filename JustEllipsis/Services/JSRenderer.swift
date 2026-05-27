import Foundation
import WebKit

/// Renders a URL in a headless WKWebView, executes JavaScript, and returns the fully-rendered HTML.
/// Used as a fallback when URLSession returns a skeleton page (< 50 words after stripping).
@MainActor
final class JSRenderer: NSObject {
    static let shared = JSRenderer()
    private override init() { super.init() }

    enum JSRenderError: Error {
        case timeout
        case navigationFailed(Error)
    }

    private var continuation: CheckedContinuation<String, Error>?
    private var webView: WKWebView?
    private var timeoutTask: Task<Void, Never>?

    func render(url: URL, timeout: TimeInterval = 12) async throws -> String {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        webView = wv

        defer {
            timeoutTask?.cancel()
            timeoutTask = nil
            webView?.navigationDelegate = nil
            webView = nil
        }

        return try await withCheckedThrowingContinuation { cont in
            continuation = cont

            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.fail(with: JSRenderError.timeout)
            }

            wv.load(URLRequest(url: url))
        }
    }

    // MARK: - Private

    private func fail(with error: Error) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(throwing: error)
    }

    private func succeed(html: String) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(returning: html)
    }

    private func extractAndSucceed() async {
        guard let wv = webView else { return }

        // Poll until body has real text content, up to 5 × 500 ms.
        // Covers SPAs that do async data fetching after initial navigation completes.
        for _ in 0..<5 {
            let length = (try? await wv.evaluateJavaScript(
                "document.body ? document.body.innerText.trim().length : 0"
            ) as? Int) ?? 0
            if length > 200 { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        guard continuation != nil else { return }

        guard let html = try? await wv.evaluateJavaScript(
            "document.documentElement.outerHTML"
        ) as? String else {
            fail(with: JSRenderError.timeout)
            return
        }

        succeed(html: html)
    }
}

// MARK: - WKNavigationDelegate

extension JSRenderer: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            await self?.extractAndSucceed()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.fail(with: JSRenderError.navigationFailed(error))
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.fail(with: JSRenderError.navigationFailed(error))
        }
    }
}
