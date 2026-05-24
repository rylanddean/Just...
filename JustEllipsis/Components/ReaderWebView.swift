import SwiftUI
import WebKit

struct ReaderWebView: UIViewRepresentable {
    let html: String
    var onScrollProgress: (Double) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollProgress: onScrollProgress)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.delegate = context.coordinator
        webView.backgroundColor = UIColor(AppTheme.background)
        webView.isOpaque = false
        webView.scrollView.backgroundColor = UIColor(AppTheme.background)
        webView.scrollView.showsVerticalScrollIndicator = false
        // Disable external navigation
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onScrollProgress = onScrollProgress
        if context.coordinator.loadedHTML != html {
            context.coordinator.loadedHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, WKNavigationDelegate {
        var onScrollProgress: (Double) -> Void
        var loadedHTML: String = ""

        init(onScrollProgress: @escaping (Double) -> Void) {
            self.onScrollProgress = onScrollProgress
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let maxOffset = scrollView.contentSize.height - scrollView.bounds.height
            guard maxOffset > 0 else { return }
            let progress = min(1.0, max(0.0, scrollView.contentOffset.y / maxOffset))
            onScrollProgress(progress)
        }

        // Block external navigation clicks
        func webView(
            _ webView: WKWebView,
            decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if action.navigationType == .linkActivated {
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
