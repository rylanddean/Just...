import SwiftUI
import SwiftData
import SafariServices
import MessageUI

struct ReaderView: View {
    let source: ReadingSource
    var editionMode: Bool = false

    private var sourceURL: String { source.url }

    private var sourceDomain: String {
        switch source {
        case .queued(let link): return link.domain ?? domainFromURL(link.url)
        case .digest(_, _, let d, _): return d
        case .dailyEdition(_, _, let d, _): return d
        }
    }
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.appTheme) private var appTheme

    @AppStorage(ReaderTheme.defaultsKey)         private var themeRaw:           String = "ember"
    @AppStorage(ReaderTextSize.defaultsKey)      private var readerTextSize:     Double = ReaderTextSize.defaultValue
    @AppStorage(ReaderLineSpacing.defaultsKey)   private var readerLineSpacing:  Double = ReaderLineSpacing.defaultValue
    @AppStorage(NightModeService.startHourKey)   private var nightStartHour:     Int    = NightModeService.defaultStartHour
    @AppStorage(NightModeService.startMinuteKey) private var nightStartMinute:   Int    = NightModeService.defaultStartMinute
    @AppStorage(NightModeService.overrideKey)    private var nightOverride:      String = "auto"

    private var effectiveReaderTheme: ReaderTheme {
        let base = ReaderTheme(rawValue: themeRaw) ?? .ember
        return NightModeService.isActive(hour: nightStartHour, minute: nightStartMinute, override: nightOverride) ? .night : base
    }

    @State private var viewModel = ReaderViewModel()
    @State private var pendingEntry: BrainEntry?
    @State private var safariURL: URL?
    @State private var pendingThreadLink: PendingThreadLink?
    @State private var pendingQuote: PendingQuote?
    @State private var pendingMessageQuote: PendingQuote?
    @State private var showQuoteSaved = false
    @State private var clearSelectionToken: UUID?
    @State private var isNearBottom = false
    @State private var overScrollDelta: CGFloat = 0
    @State private var isTextSizeControlVisible = false
    @State private var loadingMessageIndex = 0

    private let loadingMessages = [
        "Polishing commas...",
        "Untangling the good parts...",
        "Shushing pop-ups and ads...",
        "Brewing your reading tea...",
        "Asking the article to be normal...",
        "Convincing the page to behave...",
        "Removing 47 'you won't believe' banners...",
        "Translating clickbait into human...",
        "Dusting off rogue toolbars...",
        "Negotiating with mysterious JavaScript...",
        "Petting the loading hamster...",
        "Ironing out weird spacing...",
        "Finding the actual point...",
        "Extracting sentences from chaos...",
        "Turning noise into paragraphs...",
        "Sifting signal from confetti...",
        "Putting the words in a straight line...",
        "Gently deleting floating widgets...",
        "Sweeping out autoplay gremlins...",
        "Making headlines less dramatic...",
        "Removing unsolicited enthusiasm...",
        "Whispering 'calm down' to the DOM...",
        "Loading article, not nonsense...",
        "Defluffing the fluff...",
        "Making this look readable on purpose...",
        "Finding where the article actually starts...",
        "Assembling a distraction-free zone..."
    ]

    var body: some View {
        reflectPresentation {
            ZStack {
                appTheme.background.ignoresSafeArea()

                if viewModel.isLoading {
                    loadingView
                } else if let content = viewModel.content {
                    articleView(content)
                } else if let error = viewModel.error {
                    errorBannerView(error)
                }

                if showQuoteSaved { quoteSavedToast }
            }
            .task {
                switch source {
                case .queued(let link): await viewModel.load(link: link, context: context)
                case .digest(let url, _, _, _): await viewModel.loadURL(url, context: context)
                case .dailyEdition(let url, _, _, _): await viewModel.loadURL(url, context: context)
                }
            }
            .onDisappear {
                viewModel.speechPlayer?.stop()
            }
            .preferredColorScheme(appTheme.colorScheme)
            .sheet(item: $safariURL) { url in
                SafariView(url: url)
                    .ignoresSafeArea()
            }
            .sheet(item: $pendingThreadLink) { pending in
                quickAddSheet(for: pending)
                    .presentationDetents([.height(180)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(appTheme.background)
            }
            .sheet(item: $pendingQuote, onDismiss: {
                clearSelectionToken = UUID()
            }) { quote in
                quoteSheet(for: quote)
                    .presentationDetents([.height(140)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(appTheme.background)
            }
            .fullScreenCover(item: $pendingMessageQuote) { quote in
                MessageComposerView(body: quoteMessageBody(for: quote))
            }
        }
    }

    // MARK: - Reflect presentation (fullScreenCover on iPhone, sheet on iPad)

    @ViewBuilder
    private func reflectPresentation<V: View>(@ViewBuilder content: () -> V) -> some View {
        if sizeClass == .regular {
            content()
                .sheet(item: $pendingEntry) { entry in
                    reflectView(for: entry)
                        .presentationDetents([.medium, .large])
                        .frame(maxWidth: 540)
                        .presentationBackground(appTheme.background)
                }
        } else {
            content()
                .fullScreenCover(item: $pendingEntry) { entry in
                    reflectView(for: entry)
                }
        }
    }

    @ViewBuilder
    private func reflectView(for entry: BrainEntry) -> some View {
        if editionMode {
            MicroReflectView(entry: entry, onComplete: {
                markSourceRead()
                updateReadingDay()
                dismiss()
            })
        } else {
            ReflectView(entry: entry, prompt: viewModel.generatedPrompt, onComplete: {
                markSourceRead()
                updateReadingDay()
                dismiss()
            })
        }
    }

    private func markSourceRead() {
        switch source {
        case .queued(let link):
            viewModel.markAsRead(link: link, context: context)
        case .digest(let url, _, _, let feedID):
            viewModel.markDigestRead(url: url, feedID: feedID, context: context)
        case .dailyEdition(let url, _, _, let feedID):
            viewModel.markDigestRead(url: url, feedID: feedID, context: context)
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(appTheme.accent)
            if viewModel.isJSRendering {
                Text("Extracting content.")
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(appTheme.text.opacity(0.5))
            } else {
                Text(loadingMessages[loadingMessageIndex])
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(appTheme.text.opacity(0.5))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: loadingMessageIndex)
            }
        }
        .task(id: viewModel.isLoading) {
            guard viewModel.isLoading else { return }
            loadingMessageIndex = Int.random(in: 0..<loadingMessages.count)
        }
    }

    private func errorBannerView(_ error: Error) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(appTheme.text.opacity(0.5))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(sourceDomain)
                    .font(AppTheme.sansSerif(12, weight: .medium))
                    .foregroundStyle(appTheme.text.opacity(0.4))

                Spacer()

                Button {
                    UIPasteboard.general.string = sourceURL
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(appTheme.text.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.vertical, 12)
            .background(appTheme.background)

            Rectangle()
                .fill(appTheme.text.opacity(0.08))
                .frame(height: 1)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(appTheme.text.opacity(0.35))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't load this link.")
                        .font(AppTheme.sansSerif(14, weight: .medium))
                        .foregroundStyle(appTheme.heading)

                    Text(friendlyErrorMessage(for: error))
                        .font(AppTheme.sansSerif(13))
                        .foregroundStyle(appTheme.text.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(AppTheme.pagePadding)
            .background(appTheme.text.opacity(0.05))

            HStack(spacing: 24) {
                Button("Try again") {
                    Task {
                        switch source {
                        case .queued(let link): await viewModel.load(link: link, context: context)
                        case .digest(let url, _, _, _): await viewModel.loadURL(url, context: context)
                        case .dailyEdition(let url, _, _, _): await viewModel.loadURL(url, context: context)
                        }
                    }
                }
                .font(AppTheme.sansSerif(14, weight: .medium))
                .foregroundStyle(appTheme.accent)

                if let url = URL(string: sourceURL) {
                    Button("Open in browser") {
                        safariURL = url
                    }
                    .font(AppTheme.sansSerif(14, weight: .medium))
                    .foregroundStyle(appTheme.text.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 20)

            Spacer()
        }
    }

    private func friendlyErrorMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "No connection. Try again when you're online."
            case .timedOut, .cannotConnectToHost, .cannotFindHost:
                return "The server didn't respond. Try again later."
            default:
                return "Something went wrong. Try again later."
            }
        }
        if let fetchError = error as? ContentFetcher.FetchError {
            switch fetchError {
            case .invalidURL:
                return "This doesn't appear to be a valid link."
            case .emptyContent:
                return "This link didn't return readable content. It may be behind a login or paywall."
            case .httpError(let code) where code == 404:
                return "This link no longer exists."
            case .httpError(let code) where code >= 400 && code < 500:
                return "This link isn't publicly accessible. It may require a login."
            case .httpError:
                return "The server returned an error. Try again later."
            }
        }
        if let jsError = error as? JSRenderer.JSRenderError {
            switch jsError {
            case .timeout:
                return "This page took too long to render. It may require a login."
            case .navigationFailed:
                return "This link couldn't be loaded in the reader."
            }
        }
        return "Something went wrong. Try again later."
    }

    private func domainFromURL(_ raw: String) -> String {
        guard let url = URL(string: raw) else { return raw }
        return ContentFetcher.extractDomain(from: url)
    }

    private func articleView(_ content: StrippedContent) -> some View {
        VStack(spacing: 0) {
            if viewModel.isListenMode {
                listenPlayerBar(content)
                    .transition(.opacity)
            } else {
                standardTopBar(content)

                if isTextSizeControlVisible {
                    textSizeControl
                        .padding(.horizontal, AppTheme.pagePadding)
                        .padding(.bottom, 10)
                        .background(appTheme.background)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            if case .queued(let qLink) = source, let rewritten = qLink.rewrittenTitle {
                TitleWithRewriteIndicator(
                    displayTitle: rewritten,
                    originalTitle: qLink.title
                )
                .lineLimit(2)
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 8)
                .background(appTheme.background)
            }

            // Progress indicator
            GeometryReader { geo in
                Rectangle()
                    .fill(appTheme.accent.opacity(0.4))
                    .frame(width: geo.size.width * viewModel.readProgress, height: 1)
                    .animation(.linear(duration: 0.1), value: viewModel.readProgress)
            }
            .frame(height: 1)

            // Article + pull indicator overlay
            ZStack(alignment: .bottom) {
                Color.clear.frame(width: 0, height: 0).onAppear { viewModel.articleDidAppear() }
                ReaderWebView(
                    html: content.body,
                    theme: effectiveReaderTheme,
                    fontSize: CGFloat(readerTextSize),
                    lineSpacing: CGFloat(readerLineSpacing),
                    onScrollProgress: { progress in
                        viewModel.readProgress = progress
                    },
                    onNearBottom: { near in
                        withAnimation(.easeIn(duration: 0.2)) {
                            isNearBottom = near
                        }
                    },
                    onOverScrollDelta: { delta in
                        if delta == 0 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                overScrollDelta = 0
                            }
                        } else {
                            overScrollDelta = delta
                        }
                    },
                    onReflectTrigger: {
                        openReflect(content: content)
                    },
                    onLinkTapped: { urlString in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        pendingThreadLink = PendingThreadLink(urlString: urlString)
                    },
                    onQuoteSelected: { selectedText in
                        guard pendingQuote == nil,
                              pendingEntry == nil,
                              pendingThreadLink == nil,
                              !selectedText.isEmpty else { return }
                        pendingQuote = PendingQuote(
                            text: selectedText,
                            url: sourceURL,
                            title: content.title,
                            domain: content.domain
                        )
                    },
                    onSentencesReady: { sentences in
                        viewModel.sentences = sentences
                    },
                    activeSentenceIndex: viewModel.isListenMode ? viewModel.speechPlayer?.currentIndex : nil,
                    clearSelectionToken: clearSelectionToken
                )

                if isNearBottom {
                    pullIndicator
                        .transition(.opacity)
                }
            }
        }
    }

    private func standardTopBar(_ content: StrippedContent) -> some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(appTheme.text.opacity(0.5))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text(content.domain)
                    .font(AppTheme.sansSerif(12, weight: .medium))
                    .foregroundStyle(appTheme.text.opacity(0.5))

                Text("\(content.estimatedReadingMinutes) min read")
                    .font(AppTheme.sansSerif(10))
                    .foregroundStyle(appTheme.text.opacity(0.3))
            }

            Spacer()

            HStack(spacing: 16) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.startListening(
                            title: content.title,
                            estimatedMinutes: content.estimatedReadingMinutes
                        )
                    }
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 13))
                        .foregroundStyle(appTheme.text.opacity(0.4))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isTextSizeControlVisible.toggle()
                    }
                } label: {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 13))
                        .foregroundStyle(
                            isTextSizeControlVisible
                            ? appTheme.accent
                            : appTheme.text.opacity(0.4)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    safariURL = URL(string: sourceURL)
                } label: {
                    Image(systemName: "globe")
                        .font(.system(size: 13))
                        .foregroundStyle(appTheme.text.opacity(0.4))
                }
                .buttonStyle(.plain)

                Button {
                    UIPasteboard.general.string = sourceURL
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundStyle(appTheme.text.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.vertical, 12)
        .background(appTheme.background)
    }

    @ViewBuilder
    private func listenPlayerBar(_ content: StrippedContent) -> some View {
        let player = viewModel.speechPlayer
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.stopListening()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(appTheme.text.opacity(0.5))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                player?.skipBack()
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 18))
                    .foregroundStyle(appTheme.text.opacity(0.6))
            }
            .buttonStyle(.plain)

            Button {
                player?.togglePlayPause()
            } label: {
                Image(systemName: (player?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(appTheme.accent)
                    .frame(width: 44)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            speedPicker

            Spacer()

            Button {
                viewModel.stopListening()
                openReflect(content: content)
            } label: {
                Text("Done")
                    .font(AppTheme.sansSerif(14, weight: .medium))
                    .foregroundStyle(appTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.vertical, 12)
        .background(appTheme.background)
    }

    @ViewBuilder
    private var speedPicker: some View {
        if let player = viewModel.speechPlayer {
            Menu {
                ForEach(SpeechPlayer.Speed.options, id: \.self) { option in
                    Button {
                        player.speedMultiplier = option
                    } label: {
                        if player.speedMultiplier == option {
                            Label(speedLabel(option), systemImage: "checkmark")
                        } else {
                            Text(speedLabel(option))
                        }
                    }
                }
            } label: {
                Text(speedLabel(player.speedMultiplier))
                    .font(AppTheme.sansSerif(13, weight: .medium))
                    .foregroundStyle(appTheme.text.opacity(0.6))
                    .frame(minWidth: 44)
            }
        }
    }

    private func speedLabel(_ value: Float) -> String {
        let trimmed = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%g", value)
        return "\(trimmed)×"
    }

    private var textSizeControl: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Text")
                    .font(AppTheme.sansSerif(11, weight: .medium))
                    .foregroundStyle(appTheme.text.opacity(0.45))
                    .frame(width: 38, alignment: .leading)

                Button {
                    readerTextSize = max(ReaderTextSize.minValue, readerTextSize - 1)
                } label: {
                    Image(systemName: "textformat.size.smaller")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(appTheme.text.opacity(0.55))
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { readerTextSize },
                        set: { readerTextSize = min(max($0, ReaderTextSize.minValue), ReaderTextSize.maxValue) }
                    ),
                    in: ReaderTextSize.minValue...ReaderTextSize.maxValue,
                    step: 1
                )
                .tint(appTheme.accent)

                Button {
                    readerTextSize = min(ReaderTextSize.maxValue, readerTextSize + 1)
                } label: {
                    Image(systemName: "textformat.size.larger")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(appTheme.text.opacity(0.55))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Text("Lines")
                    .font(AppTheme.sansSerif(11, weight: .medium))
                    .foregroundStyle(appTheme.text.opacity(0.45))
                    .frame(width: 38, alignment: .leading)

                Button {
                    readerLineSpacing = max(ReaderLineSpacing.minValue, (round(readerLineSpacing * 10) - 1) / 10)
                } label: {
                    Image(systemName: "arrow.down.and.line.horizontal.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(appTheme.text.opacity(0.55))
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { readerLineSpacing },
                        set: { readerLineSpacing = min(max($0, ReaderLineSpacing.minValue), ReaderLineSpacing.maxValue) }
                    ),
                    in: ReaderLineSpacing.minValue...ReaderLineSpacing.maxValue,
                    step: 0.1
                )
                .tint(appTheme.accent)

                Button {
                    readerLineSpacing = min(ReaderLineSpacing.maxValue, (round(readerLineSpacing * 10) + 1) / 10)
                } label: {
                    Image(systemName: "arrow.up.and.line.horizontal.and.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(appTheme.text.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var pullIndicator: some View {
        VStack(spacing: 8) {
            Image(systemName: "chevron.up")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(appTheme.accent)
                .offset(y: -min(overScrollDelta / 80 * 10, 10))

            Text("reflect")
                .font(AppTheme.sansSerif(10))
                .foregroundStyle(appTheme.text.opacity(0.5))
                .tracking(2)

            Rectangle()
                .fill(appTheme.accent.opacity(0.45))
                .frame(height: 1)
        }
        .padding(.top, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [.clear, appTheme.background.opacity(0.96)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - Actions

    private func quickAddSheet(for pending: PendingThreadLink) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pending.domain)
                .font(AppTheme.sansSerif(18, weight: .medium))
                .foregroundStyle(appTheme.heading)

            Text(pending.urlString)
                .font(AppTheme.sansSerif(12))
                .foregroundStyle(appTheme.text.opacity(0.4))
                .lineLimit(2)

            Spacer()

            Button {
                addThreadLink(pending)
            } label: {
                Text("Add to queue")
                    .font(AppTheme.sansSerif(15, weight: .medium))
                    .foregroundStyle(appTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(AppTheme.pagePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addThreadLink(_ pending: PendingThreadLink) {
        pendingThreadLink = nil
        Task {
            let urlToAdd = pending.urlString
            let dupeCheck = FetchDescriptor<QueuedLink>(
                predicate: #Predicate { $0.url == urlToAdd }
            )
            let dupes = (try? context.fetch(dupeCheck)) ?? []
            guard dupes.isEmpty else { return }

            var orderFetch = FetchDescriptor<QueuedLink>(
                sortBy: [SortDescriptor(\.sortOrder, order: .reverse)]
            )
            orderFetch.fetchLimit = 1
            let top = (try? context.fetch(orderFetch))?.first
            let nextOrder = (top?.sortOrder ?? -1) + 1

            let newLink = QueuedLink(url: urlToAdd, sortOrder: nextOrder, threadSourceURL: self.sourceURL)
            context.insert(newLink)
            try? context.save()

            if let result = try? await ContentFetcher.fetch(urlString: urlToAdd) {
                newLink.title = result.content.title
                newLink.domain = result.content.domain
                newLink.cachedHTML = result.rawHTML
                newLink.prefetchState = .ready
                try? context.save()
            }
        }
    }

    // MARK: - Quote capture

    private var quoteSavedToast: some View {
        VStack {
            Spacer()
            Text("Kept. Your Brain grows.")
                .font(AppTheme.sansSerif(13, weight: .medium))
                .foregroundStyle(appTheme.background)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(appTheme.accent)
                .clipShape(Capsule())
                .padding(.bottom, 48)
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    private func quoteSheet(for quote: PendingQuote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(quote.text)
                .font(AppTheme.serif(15))
                .foregroundStyle(appTheme.text)
                .lineLimit(3)
                .lineSpacing(2)
                .italic()

            HStack(spacing: 0) {
                Button("Keep this") {
                    saveQuote(quote)
                }
                .font(AppTheme.sansSerif(15, weight: .semibold))
                .foregroundStyle(appTheme.accent)

                Spacer()

                if MFMessageComposeViewController.canSendText() {
                    Button("Send via Messages") {
                        let q = quote
                        pendingQuote = nil
                        Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            pendingMessageQuote = q
                        }
                    }
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(appTheme.text.opacity(0.5))
                }
            }
        }
        .padding(AppTheme.pagePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quoteMessageBody(for quote: PendingQuote) -> String {
        "\"\(quote.text)\"\n\n\(quote.title)\n\(quote.url)"
    }

    private func saveQuote(_ quote: PendingQuote) {
        pendingQuote = nil
        let entry = QuoteEntry(text: quote.text, url: quote.url, title: quote.title, domain: quote.domain)
        context.insert(entry)
        try? context.save()
        withAnimation(.easeIn(duration: 0.2)) { showQuoteSaved = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.3)) { showQuoteSaved = false }
        }
    }

    private func openReflect(content: StrippedContent) {
        let rewrittenTitle: String?
        if case .queued(let link) = source { rewrittenTitle = link.rewrittenTitle } else { rewrittenTitle = nil }
        let displayTitle = rewrittenTitle ?? content.title
        let entry = BrainEntry(url: sourceURL, title: displayTitle, domain: content.domain)
        entry.wordCount = content.estimatedWordCount
        entry.dna = viewModel.generatedDNA
        entry.readingSeconds = viewModel.elapsedReadingSeconds
        entry.estimatedReadSeconds = viewModel.estimatedReadSeconds
        entry.rewrittenTitle = rewrittenTitle
        pendingEntry = entry
    }

    private func updateReadingDay() {
        let logical = StreakEngine.logicalDay()
        let y = logical.year, m = logical.month, d = logical.day
        let fetchDescriptor = FetchDescriptor<ReadingDay>(
            predicate: #Predicate { $0.year == y && $0.month == m && $0.day == d }
        )
        if let existing = try? context.fetch(fetchDescriptor).first {
            existing.linksRead += 1
        } else {
            let day = ReadingDay(year: logical.year, month: logical.month, day: logical.day)
            day.linksRead = 1
            context.insert(day)
        }
        try? context.save()
    }
}

// MARK: - Quote

private struct PendingQuote: Identifiable {
    let id = UUID()
    let text: String
    let url: String
    let title: String
    let domain: String
}

// MARK: - SMS composer

private struct MessageComposerView: UIViewControllerRepresentable {
    let body: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.body = body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            DispatchQueue.main.async {
                controller.dismiss(animated: true)
            }
        }
    }
}

// MARK: - Thread link quick-add

private struct PendingThreadLink: Identifiable {
    let id = UUID()
    let urlString: String
    var domain: String {
        guard let url = URL(string: urlString) else { return urlString }
        return ContentFetcher.extractDomain(from: url)
    }
}

// MARK: - In-app browser

// URL needs to be Identifiable to drive .sheet(item:)
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = UIColor(named: "AccentColor")
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
