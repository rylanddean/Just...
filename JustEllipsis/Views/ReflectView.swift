import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.rylandean.justellipsis", category: "Reflect")

struct ReflectView: View {
    let entry: BrainEntry
    let link: QueuedLink
    var theme: ReaderTheme = .ember
    var onComplete: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ReflectViewModel()
    @State private var voiceRecognizer = VoiceRecognizer()
    @State private var reflectionMode: ReflectionMode = .typed
    @State private var placeholder: String = IntelligenceService.randomFallbackPrompt()
    @FocusState private var textFocused: Bool

    private var secondsSpent: Int { 60 - viewModel.secondsRemaining }
    private var isPaused: Bool { textFocused || voiceRecognizer.isListening }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.top, 16)
                    .padding(.bottom, 24)

                articleTitle

                Spacer(minLength: 0)

                inputArea
                    .padding(.horizontal, AppTheme.pagePadding)

                Spacer(minLength: 0)

                bottomBar
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.bottom, 32)
            }
        }
        .onAppear {
            logger.debug("ReflectView appeared")
            viewModel.startCountdown()
        }
        .onChange(of: textFocused) { _, focused in
            if focused { viewModel.pauseCountdown() } else { viewModel.resumeCountdown() }
        }
        .onChange(of: voiceRecognizer.isListening) { _, listening in
            if listening { viewModel.pauseCountdown() } else { viewModel.resumeCountdown() }
            if listening { viewModel.text = "" }
        }
        .onChange(of: voiceRecognizer.transcript) { _, t in
            if voiceRecognizer.isListening { viewModel.text = t }
        }
        .onChange(of: viewModel.secondsRemaining) { _, rem in
            if rem == 0 {
                logger.debug("timer expired — triggering auto-save")
                if viewModel.save(entry: entry, mode: reflectionMode, secondsSpent: secondsSpent, context: context) {
                    logger.debug("auto-save succeeded — calling dismiss()")
                    dismiss()
                    logger.debug("calling onComplete() from timer path")
                    onComplete()
                    logger.debug("onComplete() returned")
                }
            }
        }
        .preferredColorScheme(theme.colorScheme)
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack {
            CountdownRing(
                total: 60,
                remaining: viewModel.secondsRemaining,
                isPaused: isPaused,
                accent: theme.accent
            )

            Spacer()

            if voiceRecognizer.isAvailable {
                VoiceInputButton(isListening: $voiceRecognizer.isListening, accent: theme.accent) {
                    if voiceRecognizer.isListening {
                        voiceRecognizer.stopListening()
                        reflectionMode = .typed
                        textFocused = true
                    } else {
                        textFocused = false
                        reflectionMode = .voice
                        Task {
                            if await voiceRecognizer.requestPermission() {
                                try? voiceRecognizer.startListening()
                            }
                        }
                    }
                }
            }
        }
    }

    private var articleTitle: some View {
        Text(entry.title)
            .font(AppTheme.sansSerif(13))
            .foregroundStyle(theme.text.opacity(0.5))
            .lineLimit(1)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.bottom, 20)
    }

    private var inputArea: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.text.isEmpty {
                Text(placeholder)
                    .font(AppTheme.serif(20))
                    .foregroundStyle(theme.text.opacity(0.35))
                    .allowsHitTesting(false)
                    .padding(.top, 8)
                    .padding(.leading, 4)
            }

            TextEditor(text: $viewModel.text)
                .font(AppTheme.serif(20))
                .foregroundStyle(theme.text)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .tint(theme.accent)
                .focused($textFocused)
                .frame(minHeight: 120)
        }
    }

    private var bottomBar: some View {
        HStack {
            Button("Save") {
                let trimmed = viewModel.text.trimmingCharacters(in: .whitespaces)
                logger.debug("Save tapped — text='\(trimmed)', isSaved=\(viewModel.isSaved)")
                voiceRecognizer.stopListening()
                if viewModel.save(
                    entry: entry,
                    mode: reflectionMode,
                    secondsSpent: secondsSpent,
                    context: context
                ) {
                    logger.debug("save() returned true — calling dismiss()")
                    dismiss()
                    logger.debug("calling onComplete()")
                    onComplete()
                    logger.debug("onComplete() returned")
                } else {
                    logger.warning("save() returned false — button tap did nothing")
                }
            }
            .font(AppTheme.sansSerif(15, weight: .semibold))
            .foregroundStyle(theme.isLight ? .white : theme.bg)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(
                viewModel.text.trimmingCharacters(in: .whitespaces).isEmpty
                    ? theme.accent.opacity(0.3)
                    : theme.accent
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .disabled(viewModel.text.trimmingCharacters(in: .whitespaces).isEmpty)

            Spacer().frame(width: 16)

            Button("Skip") {
                logger.debug("Skip tapped")
                voiceRecognizer.stopListening()
                if viewModel.skip(entry: entry, context: context) {
                    logger.debug("skip() returned true — calling dismiss()")
                    dismiss()
                    onComplete()
                }
            }
            .font(AppTheme.sansSerif(13))
            .foregroundStyle(theme.text.opacity(0.5))
        }
    }
}
