import SwiftUI
import WebKit

// MARK: - Sheet

struct AddNewsletterSheet: View {
    let onSubscribe: (_ feedURL: String, _ email: String, _ title: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    @State private var path: [Step] = []
    // Shared state updated by the WKWebView coordinator
    @State private var webState = WebViewState()
    // Incrementing this forces SwiftUI to recreate the WKWebView on retry
    @State private var webViewID = UUID()

    enum Step: Hashable {
        case address(email: String, feedURL: String, title: String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            webScreen
                .navigationDestination(for: Step.self) { step in
                    if case .address(let email, let feedURL, let title) = step {
                        AddressScreen(
                            newsletterName: title,
                            email: email,
                            feedURL: feedURL,
                            onDone: { onSubscribe(feedURL, email, title) },
                            onCancel: { dismiss() }
                        )
                    }
                }
        }
        .presentationDetents([.large])
    }

    // MARK: - Web screen

    private var webScreen: some View {
        ZStack {
            // App background fills the frame before the page renders,
            // preventing the default white WKWebView flash.
            appTheme.background.ignoresSafeArea()

            // Web view — invisible until the page finishes loading
            if webState.loadError == nil {
                KillTheNewsletterWebView(
                    state: webState,
                    onFeedCreated: { email, feedURL, title in
                        path.append(.address(email: email, feedURL: feedURL, title: title))
                    }
                )
                .id(webViewID)
                .ignoresSafeArea(edges: .bottom)
                .opacity(webState.isLoading ? 0 : 1)
            }

            // Loading indicator — shown while the page is fetching / rendering
            if webState.isLoading && webState.loadError == nil {
                ProgressView()
                    .tint(appTheme.accent)
                    .scaleEffect(1.2)
            }

            // Error state with retry
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
                Button("Cancel") { dismiss() }
                    .foregroundStyle(appTheme.accent)
            }
        }
        .toolbarBackground(appTheme.background, for: .navigationBar)
        .toolbarColorScheme(appTheme.colorScheme == .dark ? .dark : .light, for: .navigationBar)
    }
}

// MARK: - Shared web view state

/// Observable state updated by the WKWebView coordinator and read by AddNewsletterSheet.
@Observable
final class WebViewState {
    var isLoading = true
    var loadError: String? = nil
}

// MARK: - WKWebView wrapper

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
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Keep coordinator references current across SwiftUI redraws
        context.coordinator.state = state
        context.coordinator.onFeedCreated = onFeedCreated
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "feedCreated")
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

        init(state: WebViewState, onFeedCreated: @escaping (String, String, String) -> Void) {
            self.state = state
            self.onFeedCreated = onFeedCreated
        }

        // Reset the loading indicator on every new navigation so internal
        // page links (e.g. back to home) also show a brief loading state.
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            DispatchQueue.main.async { self.state.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.state.isLoading = false }
            guard !didReport else { return }
            // Belt-and-suspenders: re-run the detection script after navigation
            // completes in case client-side routing skipped document-end injection.
            webView.evaluateJavaScript(KillTheNewsletterWebView.detectionJS, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.state.isLoading = false
                self.state.loadError = "Couldn't load the page. Check your connection and try again."
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.state.isLoading = false
                self.state.loadError = "Couldn't load the page. Check your connection and try again."
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard !didReport,
                  message.name == "feedCreated",
                  let body = message.body as? [String: Any],
                  let feedId = body["feedId"] as? String, !feedId.isEmpty
            else { return }

            didReport = true

            let rawTitle = (body["title"] as? String) ?? ""
            let title    = rawTitle.isEmpty ? "Newsletter" : rawTitle
            let email    = "\(feedId)@kill-the-newsletter.com"
            let feedURL  = "https://kill-the-newsletter.com/feeds/\(feedId).xml"

            DispatchQueue.main.async {
                self.onFeedCreated(email, feedURL, title)
            }
        }
    }
}

// MARK: - Address screen

private struct AddressScreen: View {
    let newsletterName: String
    let email: String
    let feedURL: String
    let onDone: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
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

                            Image(systemName: "doc.on.doc")
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
                    dismiss()
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
