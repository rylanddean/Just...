import SwiftUI
import WebKit

private let tapLinkJS = """
(function(){
  document.addEventListener('click',function(e){
    var el=e.target;
    while(el&&el.tagName!=='A'){el=el.parentElement;}
    if(!el||!el.href||!el.href.startsWith('http'))return;
    window.webkit.messageHandlers.tapLink.postMessage(el.href);
  },true);
})();
"""

private let quoteSelectionJS = """
(function(){
  var debounce;
  document.addEventListener('selectionchange',function(){
    clearTimeout(debounce);
    var sel=window.getSelection();
    var text=sel?sel.toString().trim():'';
    if(!text){
      window.webkit.messageHandlers.quoteSelected.postMessage('');
      return;
    }
    debounce=setTimeout(function(){
      window.webkit.messageHandlers.quoteSelected.postMessage(text);
    },2000);
  });
})();
"""

struct ReaderWebView: UIViewRepresentable {
    let html: String
    var theme: ReaderTheme = .ember
    var fontSize: CGFloat = CGFloat(ReaderTextSize.defaultValue)
    var lineSpacing: CGFloat = CGFloat(ReaderLineSpacing.defaultValue)
    var onScrollProgress: (Double) -> Void = { _ in }
    var onNearBottom: (Bool) -> Void = { _ in }
    var onOverScrollDelta: (CGFloat) -> Void = { _ in }
    var onReflectTrigger: () -> Void = {}
    var onLinkTapped: (String) -> Void = { _ in }
    var onQuoteSelected: (String) -> Void = { _ in }
    var clearSelectionToken: UUID? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onScrollProgress: onScrollProgress,
            onNearBottom: onNearBottom,
            onOverScrollDelta: onOverScrollDelta,
            onReflectTrigger: onReflectTrigger,
            onLinkTapped: onLinkTapped,
            onQuoteSelected: onQuoteSelected
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let tapScript = WKUserScript(source: tapLinkJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        let quoteScript = WKUserScript(source: quoteSelectionJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(tapScript)
        config.userContentController.addUserScript(quoteScript)
        config.userContentController.add(ScriptMessageProxy(context.coordinator), name: "tapLink")
        config.userContentController.add(ScriptMessageProxy(context.coordinator), name: "quoteSelected")
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
        context.coordinator.onLinkTapped = onLinkTapped
        context.coordinator.onQuoteSelected = onQuoteSelected
        context.coordinator.requestedFontSize = fontSize
        context.coordinator.requestedLineSpacing = lineSpacing
        if context.coordinator.lastClearSelectionToken != clearSelectionToken {
            context.coordinator.lastClearSelectionToken = clearSelectionToken
            webView.evaluateJavaScript("window.getSelection().removeAllRanges()", completionHandler: nil)
        }
        let bgColor = UIColor(theme.bg)
        webView.backgroundColor = bgColor
        webView.scrollView.backgroundColor = bgColor
        if context.coordinator.loadedHTML != html {
            context.coordinator.loadedHTML = html
            context.coordinator.appliedNightMode = nil  // reset so injection fires after load
            context.coordinator.appliedFontSize = -1  // reset so font size reapplies after load
            context.coordinator.appliedLineSpacing = -1  // reset so line spacing reapplies after load
            context.coordinator.didTrigger = false
            context.coordinator.wasNearBottom = false
            webView.loadHTMLString(html, baseURL: nil)
        } else {
            context.coordinator.applyFontSizeIfNeeded(on: webView)
            context.coordinator.applyLineSpacingIfNeeded(on: webView)
            // When night mode toggles on a page that is already loaded, update
            // colours via a CSS override instead of reloading the whole article.
            let isNight = (theme == .night)
            if context.coordinator.appliedNightMode != isNight {
                context.coordinator.appliedNightMode = isNight
                context.coordinator.applyNightModeCSS(isNight, theme: theme, on: webView)
            }
        }
    }

    // Breaks the retain cycle: WKUserContentController strongly retains its
    // message handlers, so we give it a proxy that holds a weak coordinator ref.
    private class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
        weak var coordinator: Coordinator?
        init(_ coordinator: Coordinator) { self.coordinator = coordinator }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            coordinator?.userContentController(controller, didReceive: message)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, WKNavigationDelegate, WKScriptMessageHandler {
        var onScrollProgress: (Double) -> Void
        var onNearBottom: (Bool) -> Void
        var onOverScrollDelta: (CGFloat) -> Void
        var onReflectTrigger: () -> Void
        var onLinkTapped: (String) -> Void
        var onQuoteSelected: (String) -> Void
        var loadedHTML: String = ""
        var didTrigger = false
        var wasNearBottom = false
        var requestedFontSize: CGFloat = CGFloat(ReaderTextSize.defaultValue)
        var requestedLineSpacing: CGFloat = CGFloat(ReaderLineSpacing.defaultValue)
        var appliedNightMode: Bool? = nil
        var appliedFontSize: CGFloat = -1
        var appliedLineSpacing: CGFloat = -1
        var lastClearSelectionToken: UUID? = nil

        init(
            onScrollProgress: @escaping (Double) -> Void,
            onNearBottom: @escaping (Bool) -> Void,
            onOverScrollDelta: @escaping (CGFloat) -> Void,
            onReflectTrigger: @escaping () -> Void,
            onLinkTapped: @escaping (String) -> Void,
            onQuoteSelected: @escaping (String) -> Void
        ) {
            self.onScrollProgress = onScrollProgress
            self.onNearBottom = onNearBottom
            self.onOverScrollDelta = onOverScrollDelta
            self.onReflectTrigger = onReflectTrigger
            self.onLinkTapped = onLinkTapped
            self.onQuoteSelected = onQuoteSelected
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "tapLink", let urlString = message.body as? String {
                DispatchQueue.main.async { self.onLinkTapped(urlString) }
            } else if message.name == "quoteSelected", let text = message.body as? String {
                DispatchQueue.main.async { self.onQuoteSelected(text) }
            }
        }

        func applyNightModeCSS(_ isNight: Bool, theme: ReaderTheme, on webView: WKWebView) {
            let js: String
            if isNight {
                let bg      = theme.bgHex
                let text    = theme.textHex
                let heading = theme.headingHex
                let accent  = theme.accentHex
                js = """
                (function(){
                    var s=document.getElementById('jst-nm');
                    if(!s){s=document.createElement('style');s.id='jst-nm';document.head&&document.head.appendChild(s);}
                    s.textContent=':root{--link-decoration:underline;}html,body{background:\(bg)!important;color:\(text)!important;}h1,h2,h3,h4{color:\(heading)!important;}a{color:\(accent)!important;}';
                })();
                """
            } else {
                js = "(function(){var s=document.getElementById('jst-nm');if(s)s.parentNode.removeChild(s);})();"
            }
            webView.evaluateJavaScript(js, completionHandler: nil)
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

        func applyLineSpacingIfNeeded(on webView: WKWebView) {
            guard abs(appliedLineSpacing - requestedLineSpacing) > 0.01 else { return }
            let minLS = CGFloat(ReaderLineSpacing.minValue)
            let maxLS = CGFloat(ReaderLineSpacing.maxValue)
            let clamped = min(max(requestedLineSpacing, minLS), maxLS)
            appliedLineSpacing = clamped
            let js = "document.documentElement.style.setProperty('--reader-line-height', '\(clamped)');"
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
            preferences: WKWebpagePreferences,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
        ) {
            if action.navigationType == .linkActivated {
                decisionHandler(.cancel, preferences)
            } else {
                decisionHandler(.allow, preferences)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyFontSizeIfNeeded(on: webView)
            applyLineSpacingIfNeeded(on: webView)
        }
    }
}
