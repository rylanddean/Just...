import SwiftUI
import SwiftData

struct MicroReflectView: View {
    let entry: BrainEntry
    var onComplete: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme
    @Query private var brainEntries: [BrainEntry]
    @State private var viewModel = ReflectViewModel()
    @State private var hasText = false
    @FocusState private var textFocused: Bool

    var body: some View {
        ZStack {
            appTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text(entry.title)
                        .font(AppTheme.sansSerif(13))
                        .foregroundStyle(appTheme.text.opacity(0.5))
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 24)
                .padding(.bottom, 20)

                Spacer(minLength: 0)

                inputArea
                    .padding(.horizontal, AppTheme.pagePadding)

                Spacer(minLength: 0)

                bottomBar
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(appTheme.colorScheme)
    }

    private var inputArea: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.text.isEmpty {
                Text("One thought before the next.")
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
                .onChange(of: viewModel.text) { _, new in
                    hasText = !new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button("Next →") {
                let prev = brainEntries.count
                viewModel.save(entry: entry, context: context)
                NotificationScheduler.checkAndFireRankUp(previousCount: prev, context: context)
                dismiss()
                onComplete()
            }
            .font(AppTheme.sansSerif(15, weight: .medium))
            .foregroundStyle(hasText ? appTheme.accent : appTheme.accent.opacity(0.3))
            .disabled(!hasText)

            Spacer()

            Button("Skip →") {
                let prev = brainEntries.count
                viewModel.skip(entry: entry, context: context)
                NotificationScheduler.checkAndFireRankUp(previousCount: prev, context: context)
                dismiss()
                onComplete()
            }
            .font(AppTheme.sansSerif(14))
            .foregroundStyle(appTheme.text.opacity(0.5))
        }
    }
}
