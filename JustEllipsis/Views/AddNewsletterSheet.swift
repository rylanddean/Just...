import SwiftUI
import WebKit
import OSLog

private let ktnLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "JustEllipsis", category: "KtN")

// MARK: - Sheet

struct AddNewsletterSheet: View {
    let onSubscribe: (_ feedURL: String, _ email: String, _ title: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    /// Captured on the URL-entry screen; passed to the in-app subscribe browser.
    @State private var newsletterWebsiteURL: String
    /// When a pre-filled URL is provided (e.g. from the newsletter directory) we
    /// skip the URL-entry screen and land directly on the KtN webview.
    @State private var path: [Step]

    init(prefilledURL: String = "", onSubscribe: @escaping (_ feedURL: String, _ email: String, _ title: String) -> Void) {
        self.onSubscribe = onSubscribe
        self._newsletterWebsiteURL = State(initialValue: prefilledURL)
        self._path = State(initialValue: prefilledURL.isEmpty ? [] : [.ktn])
    }

    enum Step: Hashable {
        case ktn
        case address(email: String, feedURL: String, title: String)
        case subscribe(email: String, feedURL: String, title: String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            urlEntryScreen
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .ktn:
                        KtNScreen(
                            onFeedCreated: { email, feedURL, title in
                                if !newsletterWebsiteURL.isEmpty {
                                    path.append(.subscribe(email: email, feedURL: feedURL, title: title))
                                } else {
                                    path.append(.address(email: email, feedURL: feedURL, title: title))
                                }
                            },
                            onCancel: { dismiss() }
                        )
                    case .address(let email, let feedURL, let title):
                        AddressScreen(
                            newsletterName: title,
                            email: email,
                            onDone: { onSubscribe(feedURL, email, title); dismiss() },
                            onCancel: { dismiss() }
                        )
                    case .subscribe(let email, let feedURL, let title):
                        SubscribeScreen(
                            email: email,
                            websiteURL: newsletterWebsiteURL,
                            onDone: { onSubscribe(feedURL, email, title); dismiss() },
                            onCancel: { dismiss() }
                        )
                    }
                }
        }
        .presentationDetents([.large])
    }

    // MARK: - URL entry screen (step 1)
    // Inline so it can bind directly to $newsletterWebsiteURL.

    private var urlEntryScreen: some View {
        ZStack {
            appTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NEWSLETTER WEBSITE")
                        .font(AppTheme.sansSerif(11, weight: .medium))
                        .foregroundStyle(appTheme.textFaint)
                        .kerning(2)

                    TextField("https://...", text: $newsletterWebsiteURL)
                        .font(AppTheme.sansSerif(15))
                        .foregroundStyle(appTheme.heading)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .padding(AppTheme.cardPadding)
                        .background(appTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                }

                Text("The page where you sign up. We'll open it for you after generating your address.")
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(appTheme.textFaint)
                    .lineSpacing(3)

                Spacer()

                Button {
                    path.append(.ktn)
                } label: {
                    HStack {
                        Spacer()
                        Text("Continue")
                            .font(AppTheme.sansSerif(15, weight: .semibold))
                            .foregroundStyle(appTheme.background)
                        Spacer()
                    }
                    .frame(height: 48)
                    .background(appTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(AppTheme.pagePadding)
        }
        .navigationTitle("Newsletter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(appTheme.accent)
            }
        }
        .toolbarBackground(appTheme.background, for: .navigationBar)
        .toolbarColorScheme(appTheme.colorScheme == .dark ? .dark : .light, for: .navigationBar)
    }
}

// MARK: - Shared web view state

/// Observable state updated by a WKWebView coordinator and read by its host view.
@Observable
final class WebViewState {
    var isLoading = true
    var loadError: String? = nil
    /// Updated on every navigation finish — lets host views react to URL changes.
    var currentURL: URL? = nil
    /// Page title at the time of the last navigation finish.
    var currentTitle: String = ""
}

// MARK: - Step 2: KtN screen

/// Hosts the Kill the Newsletter webview. Self-contained so its WebViewState
/// is fresh every time the step is pushed onto the navigation stack.
private struct KtNScreen: View {
    let onFeedCreated: (_ email: String, _ feedURL: String, _ title: String) -> Void
    let onCancel: () -> Void

    @Environment(\.appTheme) private var appTheme
    @State private var webState = WebViewState()
    @State private var webViewID = UUID()

    /// True when the webview has landed on a /feeds/<id> success page.
    private var isOnSuccessPage: Bool {
        guard let path = webState.currentURL?.path else { return false }
        return KillTheNewsletterWebView.extractFeedId(from: path) != nil
    }

    var body: some View {
        ZStack {
            appTheme.background.ignoresSafeArea()

            if webState.loadError == nil {
                KillTheNewsletterWebView(
                    state: webState,
                    onFeedCreated: onFeedCreated
                )
                .id(webViewID)
                .ignoresSafeArea(edges: .bottom)
                .opacity(webState.isLoading ? 0 : 1)
            }

            if webState.isLoading && webState.loadError == nil {
                ProgressView()
                    .tint(appTheme.accent)
                    .scaleEffect(1.2)
            }

            if let error = webState.loadError {
                VStack(spacing: 20) {
                    Text(error)
                        .font(AppTheme.sansSerif(14))
                        .foregroundStyle(appTheme.textFaint)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.pagePadding)

                    Button {
                        webState = WebViewState()
                        webViewID = UUID()
                    } label: {
                        Text("Try again")
                            .font(AppTheme.sansSerif(14, weight: .medium))
                            .foregroundStyle(appTheme.accent)
                    }
                }
            }
        }
        .navigationTitle("Newsletter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
                    .foregroundStyle(appTheme.accent)
            }
            // Manual fallback: visible once we're on the /feeds/<id> success page.
            // Handles cases where the JS message bridge silently fails.
            if isOnSuccessPage {
                ToolbarItem(placement: .primaryAction) {
                    Button("Continue") { advanceFromSuccessPage() }
                        .font(AppTheme.sansSerif(15, weight: .semibold))
                        .foregroundStyle(appTheme.accent)
                }
            }
        }
        .toolbarBackground(appTheme.background, for: .navigationBar)
        .toolbarColorScheme(appTheme.colorScheme == .dark ? .dark : .light, for: .navigationBar)
        .onChange(of: webState.currentURL) { _, newURL in
            ktnLog.debug("KtNScreen: currentURL changed → \(newURL?.absoluteString ?? "nil") isOnSuccessPage=\(self.isOnSuccessPage)")
        }
    }

    /// Called when the user taps Continue on the success page.
    /// Extracts feed data from the tracked URL/title rather than relying on JS.
    private func advanceFromSuccessPage() {
        guard let path = webState.currentURL?.path,
              let feedId = KillTheNewsletterWebView.extractFeedId(from: path)
        else { return }

        let rawTitle = webState.currentTitle
        let title = rawTitle
            .replacingOccurrences(of: " | Kill the Newsletter!", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let email   = "\(feedId)@kill-the-newsletter.com"
        let feedURL = "https://kill-the-newsletter.com/feeds/\(feedId).xml"
        onFeedCreated(email, feedURL, title.isEmpty ? "Newsletter" : title)
    }
}

// MARK: - WKWebView wrapper for Kill the Newsletter

/// Loads kill-the-newsletter.com and automatically detects a successful feed creation.
/// When KtN's form is submitted, it redirects to `/feeds/<id>`. A JS observer picks up
/// that URL pattern, derives the reading address and Atom feed URL from the ID, and
/// reports them back to Swift via WKScriptMessageHandler.
struct KillTheNewsletterWebView: UIViewRepresentable {
    let state: WebViewState
    let onFeedCreated: (_ email: String, _ feedURL: String, _ title: String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, onFeedCreated: onFeedCreated)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()

        let detectionScript = WKUserScript(
            source: Self.detectionJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(detectionScript)
        contentController.add(context.coordinator, name: "feedCreated")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        // Transparent background: the app's dark surface shows through until
        // the page's own styles load, preventing the white-flash problem.
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        // Allow Safari Web Inspector in debug builds
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        webView.load(URLRequest(url: URL(string: "https://kill-the-newsletter.com")!))
        context.coordinator.startObserving(webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Keep coordinator references current across SwiftUI redraws
        context.coordinator.state = state
        context.coordinator.onFeedCreated = onFeedCreated
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.urlObservation = nil
        coordinator.titleObservation = nil
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "feedCreated")
    }

    // Extracts the feed ID from a /feeds/<id> path. Returns nil for any other path.
    static func extractFeedId(from path: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "^/feeds/([A-Za-z0-9]{8,})$"),
              let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
              let range = Range(match.range(at: 1), in: path)
        else { return nil }
        return String(path[range])
    }

    // Runs at document-end. Detects /feeds/<id> (the KtN success page).
    // Feed IDs are alphanumeric; we require ≥ 8 chars to avoid false positives.
    // Strips the " | Kill the Newsletter!" suffix from the page title.
    private static let detectionJS = """
    (function() {
        var m = window.location.pathname.match(/^\\/feeds\\/([A-Za-z0-9]{8,})$/);
        if (!m) return;
        var raw = (document.title || '').trim();
        var title = raw.replace(/\\s*[|\\u2014\\u2013\\-].*$/, '').trim();
        window.webkit.messageHandlers.feedCreated.postMessage({ feedId: m[1], title: title });
    })();
    """

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var state: WebViewState
        var onFeedCreated: (String, String, String) -> Void
        private var didReport = false

        /// KVO tokens — held for the lifetime of the WKWebView.
        fileprivate var urlObservation: NSKeyValueObservation?
        fileprivate var titleObservation: NSKeyValueObservation?

        init(state: WebViewState, onFeedCreated: @escaping (String, String, String) -> Void) {
            self.state = state
            self.onFeedCreated = onFeedCreated
        }

        // MARK: KVO

        /// Attach KVO observers to the web view. Called once from makeUIView.
        /// KtN uses client-side JS navigation after form submission, so
        /// WKNavigationDelegate alone won't catch the /feeds/<id> redirect.
        /// Observing `url` directly fires on every URL change including pushState.
        func startObserving(_ webView: WKWebView) {
            urlObservation = webView.observe(\.url, options: .new) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.handleURLChange(in: wv) }
            }
            titleObservation = webView.observe(\.title, options: .new) { [weak self] wv, _ in
                MainActor.assumeIsolated {
                    let t = wv.title ?? ""
                    ktnLog.debug("KVO title → \(t)")
                    self?.state.currentTitle = t
                }
            }
        }

        private func handleURLChange(in webView: WKWebView) {
            guard let url = webView.url else { return }
            ktnLog.debug("KVO url → \(url.absoluteString)")
            state.currentURL = url

            guard !didReport,
                  let feedId = KillTheNewsletterWebView.extractFeedId(from: url.path)
            else { return }

            didReport = true
            ktnLog.info("KVO detected feedId=\(feedId)")

            let email   = "\(feedId)@kill-the-newsletter.com"
            let feedURL = "https://kill-the-newsletter.com/feeds/\(feedId).xml"

            // Title may not be set yet at URL-change time — ask the page directly.
            webView.evaluateJavaScript("document.title") { [weak self] result, error in
                if let error { ktnLog.error("evaluateJavaScript(title) error: \(error)") }
                let rawTitle = (result as? String) ?? ""
                let title = rawTitle
                    .replacingOccurrences(of: " | Kill the Newsletter!", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                ktnLog.info("KVO title from JS: \(title)")
                self?.onFeedCreated(email, feedURL, title.isEmpty ? "Newsletter" : title)
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            ktnLog.debug("didCommit: \(webView.url?.absoluteString ?? "nil")")
            state.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let urlStr = webView.url?.absoluteString ?? "nil"
            ktnLog.debug("didFinish: url=\(urlStr) didReport=\(self.didReport)")
            state.isLoading = false
            // KVO handles detection; JS injection is a belt-and-suspenders fallback
            // for any edge case where pushState fires without triggering KVO.
            guard !didReport else { return }
            webView.evaluateJavaScript(KillTheNewsletterWebView.detectionJS) { result, error in
                if let error { ktnLog.error("JS injection error: \(error)") }
                else { ktnLog.debug("JS injection result: \(String(describing: result))") }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            ktnLog.error("didFailProvisionalNavigation: \(error)")
            state.isLoading = false
            state.loadError = "Couldn't load the page. Check your connection and try again."
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            ktnLog.error("didFail: \(error)")
            state.isLoading = false
            state.loadError = "Couldn't load the page. Check your connection and try again."
        }

        // MARK: WKScriptMessageHandler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            ktnLog.debug("JS bridge message: \(message.name) body=\(String(describing: message.body))")
            guard !didReport,
                  message.name == "feedCreated",
                  let body = message.body as? [String: Any],
                  let feedId = body["feedId"] as? String, !feedId.isEmpty
            else {
                ktnLog.warning("JS bridge guard failed (didReport=\(self.didReport))")
                return
            }

            didReport = true
            ktnLog.info("JS bridge detected feedId=\(feedId)")

            let rawTitle = (body["title"] as? String) ?? ""
            let title    = rawTitle.isEmpty ? "Newsletter" : rawTitle
            let email    = "\(feedId)@kill-the-newsletter.com"
            let feedURL  = "https://kill-the-newsletter.com/feeds/\(feedId).xml"
            onFeedCreated(email, feedURL, title)
        }
    }
}

// MARK: - Step 3a: Address screen (fallback — no website URL entered)

private struct AddressScreen: View {
    let newsletterName: String
    let email: String
    let onDone: () -> Void
    let onCancel: () -> Void

    @Environment(\.appTheme) private var appTheme
    @State private var justCopied = false

    var body: some View {
        ZStack {
            appTheme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR READING ADDRESS")
                        .font(AppTheme.sansSerif(11, weight: .medium))
                        .foregroundStyle(appTheme.accent)
                        .kerning(2)

                    Button {
                        copyAddress()
                    } label: {
                        HStack(spacing: 12) {
                            Text(email)
                                .font(AppTheme.sansSerif(13))
                                .foregroundStyle(appTheme.heading)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 14))
                                .foregroundStyle(justCopied ? appTheme.accent : appTheme.textFaint)
                                .animation(.easeInOut(duration: 0.15), value: justCopied)
                        }
                        .padding(AppTheme.cardPadding)
                        .background(appTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                    }
                    .buttonStyle(.plain)
                }

                Text("Paste this into the subscription form for \(newsletterName). New editions will appear in your feeds automatically.")
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(appTheme.textFaint)
                    .lineSpacing(3)

                Spacer()

                Button {
                    onDone()
                } label: {
                    HStack {
                        Spacer()
                        Text("Done")
                            .font(AppTheme.sansSerif(15, weight: .semibold))
                            .foregroundStyle(appTheme.background)
                        Spacer()
                    }
                    .frame(height: 48)
                    .background(appTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(AppTheme.pagePadding)
        }
        .navigationTitle("Newsletter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
                    .foregroundStyle(appTheme.accent)
            }
        }
        .toolbarBackground(appTheme.background, for: .navigationBar)
        .toolbarColorScheme(appTheme.colorScheme == .dark ? .dark : .light, for: .navigationBar)
    }

    private func copyAddress() {
        UIPasteboard.general.string = email
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            justCopied = false
        }
    }
}

// MARK: - Step 3b: Subscribe screen (in-app browser with email pinned)

private struct SubscribeScreen: View {
    let email: String
    let websiteURL: String
    let onDone: () -> Void
    let onCancel: () -> Void

    @Environment(\.appTheme) private var appTheme
    @State private var webState = WebViewState()
    @State private var webViewID = UUID()
    @State private var justCopied = false

    var body: some View {
        ZStack {
            appTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Sticky email banner
                emailBanner

                Rectangle()
                    .fill(appTheme.separator)
                    .frame(height: 1)

                // In-app browser
                ZStack {
                    if webState.loadError == nil {
                        SimpleWebView(url: normalisedURL, state: webState)
                            .id(webViewID)
                            .opacity(webState.isLoading ? 0 : 1)
                    }

                    if webState.isLoading && webState.loadError == nil {
                        ProgressView()
                            .tint(appTheme.accent)
                            .scaleEffect(1.2)
                    }

                    if let error = webState.loadError {
                        VStack(spacing: 20) {
                            Text(error)
                                .font(AppTheme.sansSerif(14))
                                .foregroundStyle(appTheme.textFaint)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, AppTheme.pagePadding)

                            Button {
                                webState = WebViewState()
                                webViewID = UUID()
                            } label: {
                                Text("Try again")
                                    .font(AppTheme.sansSerif(14, weight: .medium))
                                    .foregroundStyle(appTheme.accent)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationTitle("Subscribe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
                    .foregroundStyle(appTheme.accent)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Done") { onDone() }
                    .font(AppTheme.sansSerif(15, weight: .semibold))
                    .foregroundStyle(appTheme.accent)
            }
        }
        .toolbarBackground(appTheme.background, for: .navigationBar)
        .toolbarColorScheme(appTheme.colorScheme == .dark ? .dark : .light, for: .navigationBar)
        .onAppear {
            // Pre-copy the email so the user can paste it immediately into the subscribe form.
            UIPasteboard.general.string = email
        }
    }

    // MARK: - Email banner

    private var emailBanner: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SUBSCRIPTION ADDRESS")
                    .font(AppTheme.sansSerif(10, weight: .medium))
                    .foregroundStyle(appTheme.accent)
                    .kerning(2)

                Text(email)
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(appTheme.heading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                copyEmail()
            } label: {
                Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14))
                    .foregroundStyle(justCopied ? appTheme.accent : appTheme.textFaint)
                    .animation(.easeInOut(duration: 0.15), value: justCopied)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.vertical, 10)
        .background(appTheme.surface)
    }

    private func copyEmail() {
        UIPasteboard.general.string = email
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            justCopied = false
        }
    }

    private var normalisedURL: String {
        let t = websiteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t.hasPrefix("http://") || t.hasPrefix("https://")) ? t : "https://\(t)"
    }
}

// MARK: - Simple WKWebView (plain browser, no JS injection)

private struct SimpleWebView: UIViewRepresentable {
    let url: String
    let state: WebViewState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        if let u = URL(string: url) {
            webView.load(URLRequest(url: u))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.state = state
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var state: WebViewState

        init(state: WebViewState) { self.state = state }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            DispatchQueue.main.async { self.state.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.state.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
            DispatchQueue.main.async {
                self.state.isLoading = false
                self.state.loadError = "Couldn't load the page. Check your connection and try again."
            }
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError _: Error) {
            DispatchQueue.main.async {
                self.state.isLoading = false
                self.state.loadError = "Couldn't load the page. Check your connection and try again."
            }
        }
    }
}
