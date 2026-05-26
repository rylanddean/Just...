import SwiftUI
import WebKit

struct ReaderWebView: UIViewRepresentable {
    let html: String
    var theme: ReaderTheme = .ember
    var fontSize: CGFloat = CGFloat(ReaderTextSize.defaultValue)
    var onScrollProgress: (Double) -> Void = { _ in }
    var onNearBottom: (Bool) -> Void = { _ in }
    var onOverScrollDelta: (CGFloat) -> Void = { _ in }
    var onReflectTrigger: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onScrollProgress: onScrollProgress,
            onNearBottom: onNearBottom,
            onOverScrollDelta: onOverScrollDelta,
            onReflectTrigger: onReflectTrigger
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.delegate = context.coordinator
        webView.backgroundColor = UIColor(theme.bg)
        webView.isOpaque = false
        webView.scrollView.backgroundColor = UIColor(theme.bg)
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onScrollProgress = onScrollProgress
        context.coordinator.onNearBottom = onNearBottom
        context.coordinator.onOverScrollDelta = onOverScrollDelta
        context.coordinator.onReflectTrigger = onReflectTrigger
        context.coordinator.requestedFontSize = fontSize
        let bgColor = UIColor(theme.bg)
        webView.backgroundColor = bgColor
        webView.scrollView.backgroundColor = bgColor
        if context.coordinator.loadedHTML != html {
            context.coordinator.loadedHTML = html
            context.coordinator.didTrigger = false
            context.coordinator.wasNearBottom = false
            webView.loadHTMLString(html, baseURL: nil)
        } else {
            context.coordinator.applyFontSizeIfNeeded(on: webView)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, WKNavigationDelegate {
        var onScrollProgress: (Double) -> Void
        var onNearBottom: (Bool) -> Void
        var onOverScrollDelta: (CGFloat) -> Void
        var onReflectTrigger: () -> Void
        var loadedHTML: String = ""
        var didTrigger = false
        var wasNearBottom = false
        var requestedFontSize: CGFloat = CGFloat(ReaderTextSize.defaultValue)
        private var appliedFontSize: CGFloat = -1

        init(
            onScrollProgress: @escaping (Double) -> Void,
            onNearBottom: @escaping (Bool) -> Void,
            onOverScrollDelta: @escaping (CGFloat) -> Void,
            onReflectTrigger: @escaping () -> Void
        ) {
            self.onScrollProgress = onScrollProgress
            self.onNearBottom = onNearBottom
            self.onOverScrollDelta = onOverScrollDelta
            self.onReflectTrigger = onReflectTrigger
        }

        func applyFontSizeIfNeeded(on webView: WKWebView) {
            guard abs(appliedFontSize - requestedFontSize) > 0.1 else { return }
            let minSize = CGFloat(ReaderTextSize.minValue)
            let maxSize = CGFloat(ReaderTextSize.maxValue)
            let clamped = min(max(requestedFontSize, minSize), maxSize)
            appliedFontSize = clamped
            let js = """
            document.documentElement.style.setProperty('--reader-font-size', '\(clamped)px');
            document.body.style.fontSize = '\(clamped)px';
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let maxNatural = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            let offset = scrollView.contentOffset.y

            // Read progress
            if maxNatural > 0 {
                let progress = min(1.0, max(0.0, offset / maxNatural))
                onScrollProgress(progress)
            }

            // Near-bottom toggle — guard maxNatural > 0 so short articles don't
            // show the indicator before content height is known
            let nearBottom = maxNatural > 0 && (maxNatural - offset) < 150
            if nearBottom != wasNearBottom {
                wasNearBottom = nearBottom
                onNearBottom(nearBottom)
            }

            // Over-scroll — only track active drag; momentum never triggers reflect
            let rawDelta = offset - maxNatural
            if scrollView.isDragging && rawDelta > 0 {
                onOverScrollDelta(rawDelta)
                if rawDelta >= 80 && !didTrigger {
                    didTrigger = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onReflectTrigger()
                }
            } else if rawDelta <= 0 {
                onOverScrollDelta(0)
            }
            // momentum over-scroll: leave visual frozen until content springs back
        }

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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyFontSizeIfNeeded(on: webView)
        }
    }
}
