import SwiftUI
import SwiftData

struct ReflectView: View {
    let entry: BrainEntry
    var prompt: String? = nil
    var onComplete: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme
    @State private var viewModel = ReflectViewModel()
    @State private var placeholder: String = ""
    @FocusState private var textFocused: Bool
    @Query private var brainEntries: [BrainEntry]

    private var resolvedPrompt: String {
        let isRush = entry.estimatedReadSeconds > 0
            && entry.readingSeconds < Int(Double(entry.estimatedReadSeconds) * 0.2)
        if isRush { return "Anything catch your eye?" }
        return prompt ?? IntelligenceService.randomFallbackPrompt()
    }

    var body: some View {
        ZStack {
            appTheme.background.ignoresSafeArea()

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
            placeholder = resolvedPrompt
            viewModel.startCountdown()
        }
        .preferredColorScheme(appTheme.colorScheme)
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack {
            CountdownRing(
                total: 60,
                remaining: viewModel.secondsRemaining
            )

            Spacer()
        }
    }

    private var articleTitle: some View {
        Text(entry.title)
            .font(AppTheme.sansSerif(13))
            .foregroundStyle(appTheme.text.opacity(0.5))
            .lineLimit(1)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.bottom, 20)
    }

    private var inputArea: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.text.isEmpty {
                Text(placeholder)
                    .font(AppTheme.serif(20))
                    .foregroundStyle(appTheme.text.opacity(0.35))
                    .allowsHitTesting(false)
                    .padding(.top, 8)
                    .padding(.leading, 4)
            }

            TextEditor(text: $viewModel.text)
                .font(AppTheme.serif(20))
                .foregroundStyle(appTheme.text)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .tint(appTheme.accent)
                .focused($textFocused)
                .frame(minHeight: 120)
        }
    }

    private var bottomBar: some View {
        let hasText = !viewModel.text.trimmingCharacters(in: .whitespaces).isEmpty
        let saveEnabled = viewModel.canSave && hasText

        return HStack {
            Button {
                let prevCount = brainEntries.count
                if viewModel.save(entry: entry, context: context) {
                    NotificationScheduler.checkAndFireRankUp(previousCount: prevCount, context: context)
                    dismiss()
                    onComplete()
                }
            } label: {
                Text("Save")
                    .font(AppTheme.sansSerif(15, weight: .semibold))
                    .foregroundStyle(appTheme.isLight ? .white : appTheme.background)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
            }
            .background(saveEnabled ? appTheme.accent : appTheme.accent.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .disabled(!saveEnabled)

            Spacer().frame(width: 16)

            Button("Skip") {
                let prevCount = brainEntries.count
                if viewModel.skip(entry: entry, context: context) {
                    NotificationScheduler.checkAndFireRankUp(previousCount: prevCount, context: context)
                    dismiss()
                    onComplete()
                }
            }
            .font(AppTheme.sansSerif(13))
            .foregroundStyle(appTheme.text.opacity(0.5))
        }
    }
}
