import SwiftUI
import SwiftData

// MARK: - Interest model

struct OnboardingInterest: Identifiable {
    let id: String
    let label: String
    let categories: [String]

    static let all: [OnboardingInterest] = [
        OnboardingInterest(id: "tech",     label: "Technology",  categories: ["Technology", "AI & Machine Learning"]),
        OnboardingInterest(id: "science",  label: "Science",     categories: ["Science", "Environment & Climate"]),
        OnboardingInterest(id: "business", label: "Business",    categories: ["Business & Startups", "Finance"]),
        OnboardingInterest(id: "design",   label: "Design",      categories: ["Design"]),
        OnboardingInterest(id: "culture",  label: "Culture",     categories: ["Culture", "Long-form"]),
        OnboardingInterest(id: "health",   label: "Health",      categories: ["Health", "Mental Health"]),
        OnboardingInterest(id: "ideas",    label: "Ideas",       categories: ["Philosophy", "History"]),
        OnboardingInterest(id: "writing",  label: "Writing",     categories: ["Writing & Craft"]),
        OnboardingInterest(id: "sport",    label: "Sport",       categories: ["Sports"]),
        OnboardingInterest(id: "food",     label: "Food",        categories: ["Food & Drink"]),
    ]
}

// MARK: - Root container

struct OnboardingView: View {
    var onComplete: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.appTheme) private var appTheme

    @State private var step: Int = 0
    @State private var isForward: Bool = true
    @State private var selectedInterests: Set<String> = []
    @State private var addedURLs: Set<String> = []

    private let allDirectoryItems: [FeedDirectoryItem] = FeedDirectoryItem.loadAll()

    private var suggestedSources: [FeedDirectoryItem] {
        let interests = OnboardingInterest.all.filter { selectedInterests.contains($0.id) }
        var result: [FeedDirectoryItem] = []
        var seenURLs = Set<String>()

        for interest in interests {
            let matches = allDirectoryItems
                .filter { interest.categories.contains($0.category) }
                .shuffled()
                .prefix(3)
            for item in matches {
                if seenURLs.insert(item.url).inserted {
                    result.append(item)
                }
            }
        }
        return Array(result.prefix(12))
    }

    var body: some View {
        ZStack(alignment: .top) {
            appTheme.background.ignoresSafeArea()

            stepContent
                .id(step)
                .transition(isForward
                    ? .asymmetric(
                        insertion: .opacity.combined(with: .offset(x: 48, y: 0)),
                        removal: .opacity.combined(with: .offset(x: -48, y: 0))
                      )
                    : .asymmetric(
                        insertion: .opacity.combined(with: .offset(x: -48, y: 0)),
                        removal: .opacity.combined(with: .offset(x: 48, y: 0))
                      )
                )
        }
        .animation(.easeOut(duration: 0.25), value: step)
        .preferredColorScheme(appTheme.colorScheme)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            WelcomeStep(onNext: goForward)
        case 1:
            LoopStep(onNext: goForward, onBack: goBack)
        case 2:
            InterestsStep(
                selectedInterests: $selectedInterests,
                onNext: goForward,
                onBack: goBack
            )
        case 3:
            SourcesStep(
                sources: suggestedSources,
                addedURLs: $addedURLs,
                onComplete: finish,
                onBack: goBack
            )
        default:
            EmptyView()
        }
    }

    // MARK: - Navigation

    private func goForward() {
        isForward = true
        withAnimation(.easeOut(duration: 0.25)) { step += 1 }
    }

    private func goBack() {
        isForward = false
        withAnimation(.easeOut(duration: 0.25)) { step -= 1 }
    }

    private func finish() {
        for source in suggestedSources where addedURLs.contains(source.url) {
            let feed = RSSFeed(url: source.url, title: source.name, category: source.category)
            context.insert(feed)
        }
        try? context.save()
        onComplete()
    }
}

// MARK: - Step indicator

private struct StepDots: View {
    let total: Int
    let current: Int

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < current ? appTheme.accent : (i == current ? appTheme.accent : appTheme.separator))
                    .frame(width: i == current ? 20 : 6, height: 6)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: current)
            }
        }
    }
}

// MARK: - Back button

private struct BackButton: View {
    let action: () -> Void
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(appTheme.textFaint)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Primary CTA button

private struct PrimaryButton: View {
    let label: String
    let disabled: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var appTheme

    init(_ label: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(AppTheme.sansSerif(16, weight: .semibold))
                .foregroundStyle(appTheme.isLight ? .white : appTheme.background)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .background(disabled ? appTheme.accent.opacity(0.3) : appTheme.accent)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .disabled(disabled)
        .animation(.easeInOut(duration: 0.2), value: disabled)
    }
}

// MARK: - Step 0: Welcome

private struct WelcomeStep: View {
    let onNext: () -> Void
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image("JustLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .padding(16)
                    .background(Color(hex: "#1A1208"))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                Text("READ. THINK. GROW.")
                    .font(AppTheme.sansSerif(11, weight: .medium))
                    .foregroundStyle(appTheme.textFaint)
                    .kerning(3)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                pitchLine("A few links a day.")
                pitchLine("Read it stripped clean.")
                pitchLine("Write one thought.")
                pitchLine("Keep it forever.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.pagePadding)

            Spacer()

            VStack(spacing: 16) {
                PrimaryButton("Get started", action: onNext)

                Text("Not a read-later app. A reading habit.")
                    .font(AppTheme.sansSerif(12))
                    .foregroundStyle(appTheme.textFaint)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.bottom, 48)
        }
    }

    private func pitchLine(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.sansSerif(18, weight: .medium))
            .foregroundStyle(appTheme.text)
    }
}

// MARK: - Step 1: How it works

private struct LoopStep: View {
    let onNext: () -> Void
    let onBack: () -> Void
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        VStack(spacing: 0) {
            topNav(step: 1, onBack: onBack)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 48) {
                    Text("How it\nworks.")
                        .font(AppTheme.serif(36, weight: .bold))
                        .foregroundStyle(appTheme.heading)
                        .lineSpacing(4)

                    VStack(alignment: .leading, spacing: 32) {
                        loopRow(
                            number: "1",
                            title: "Add a link.",
                            body: "Paste any URL, or pick from writers you follow."
                        )
                        loopRow(
                            number: "2",
                            title: "Read it.",
                            body: "Stripped of ads, images, and clutter. Just words."
                        )
                        loopRow(
                            number: "3",
                            title: "Write one thought.",
                            body: "60 seconds. Anything that stuck. One word is enough."
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Every reflection grows your Brain.")
                            .font(AppTheme.serif(18))
                            .foregroundStyle(appTheme.text)
                            .lineSpacing(3)

                        Text("A personal knowledge base that's yours forever. It never shrinks.")
                            .font(AppTheme.sansSerif(14))
                            .foregroundStyle(appTheme.textFaint)
                            .lineSpacing(3)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 32)
            }

            PrimaryButton("Continue", action: onNext)
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 48)
        }
    }

    private func loopRow(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 20) {
            Text(number)
                .font(AppTheme.sansSerif(13, weight: .semibold))
                .foregroundStyle(appTheme.accent)
                .monospacedDigit()
                .frame(width: 20)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(AppTheme.sansSerif(17, weight: .semibold))
                    .foregroundStyle(appTheme.heading)

                Text(body)
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(appTheme.textFaint)
                    .lineSpacing(3)
            }
        }
    }
}

// MARK: - Step 2: Interests

private struct InterestsStep: View {
    @Binding var selectedInterests: Set<String>
    let onNext: () -> Void
    let onBack: () -> Void

    @Environment(\.appTheme) private var appTheme

    private var canContinue: Bool { !selectedInterests.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            topNav(step: 2, onBack: onBack)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What do you\nread about?")
                            .font(AppTheme.serif(36, weight: .bold))
                            .foregroundStyle(appTheme.heading)
                            .lineSpacing(4)

                        Text("Pick a few. We'll suggest some writers to start with.")
                            .font(AppTheme.sansSerif(14))
                            .foregroundStyle(appTheme.textFaint)
                    }

                    InterestChipGrid(
                        interests: OnboardingInterest.all,
                        selected: $selectedInterests
                    )
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 32)
            }

            PrimaryButton("Continue", disabled: !canContinue, action: onNext)
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 48)
        }
    }
}

private struct InterestChipGrid: View {
    let interests: [OnboardingInterest]
    @Binding var selected: Set<String>
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        OnboardingFlowLayout(spacing: 8) {
            ForEach(interests) { interest in
                let isSelected = selected.contains(interest.id)
                Button {
                    if isSelected {
                        selected.remove(interest.id)
                    } else {
                        selected.insert(interest.id)
                    }
                } label: {
                    Text(interest.label)
                        .font(AppTheme.sansSerif(14, weight: .medium))
                        .foregroundStyle(
                            isSelected
                                ? (appTheme.isLight ? .white : appTheme.background)
                                : appTheme.text
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            isSelected ? appTheme.accent : appTheme.surface,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().stroke(
                                isSelected ? appTheme.accent : appTheme.separator,
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: isSelected)
            }
        }
    }
}

// MARK: - Step 3: Sources

private struct SourcesStep: View {
    let sources: [FeedDirectoryItem]
    @Binding var addedURLs: Set<String>
    let onComplete: () -> Void
    let onBack: () -> Void

    @Environment(\.appTheme) private var appTheme

    private var addedCount: Int { addedURLs.count }
    private var ctaLabel: String {
        addedCount == 0 ? "Start reading" : "Start reading (\(addedCount))"
    }

    var body: some View {
        VStack(spacing: 0) {
            topNav(step: 3, onBack: onBack)

            VStack(alignment: .leading, spacing: 6) {
                Text("Here are some\nwriters to start with.")
                    .font(AppTheme.serif(36, weight: .bold))
                    .foregroundStyle(appTheme.heading)
                    .lineSpacing(4)

                Text("Add a few. You can always change these later.")
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(appTheme.textFaint)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.bottom, 20)

            Divider()
                .background(appTheme.separator)

            if sources.isEmpty {
                Spacer()
                Text("Nothing to suggest. You can add your own in Feeds.")
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(appTheme.textFaint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(sources) { source in
                            SourceRow(
                                item: source,
                                isAdded: addedURLs.contains(source.url)
                            ) {
                                if addedURLs.contains(source.url) {
                                    addedURLs.remove(source.url)
                                } else {
                                    addedURLs.insert(source.url)
                                }
                            }

                            if source.id != sources.last?.id {
                                Divider()
                                    .background(appTheme.separator)
                                    .padding(.leading, AppTheme.pagePadding)
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
            }

            Divider()
                .background(appTheme.separator)

            PrimaryButton(ctaLabel, action: onComplete)
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 16)
                .padding(.bottom, 48)
        }
    }
}

private struct SourceRow: View {
    let item: FeedDirectoryItem
    let isAdded: Bool
    let onToggle: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(AppTheme.sansSerif(15, weight: .semibold))
                    .foregroundStyle(appTheme.heading)
                    .lineLimit(1)

                Text(item.description)
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(appTheme.textFaint)
                    .lineLimit(2)
                    .lineSpacing(2)
            }

            Spacer()

            Button(action: onToggle) {
                if isAdded {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(appTheme.accent)
                        .frame(width: 32, height: 32)
                        .background(appTheme.accent.opacity(0.12))
                        .clipShape(Circle())
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(appTheme.heading)
                        .frame(width: 32, height: 32)
                        .background(appTheme.surface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(appTheme.separator, lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.15), value: isAdded)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.vertical, 14)
    }
}

// MARK: - Shared helpers

@MainActor
private func topNav(step: Int, onBack: @escaping () -> Void) -> some View {
    HStack {
        BackButton(action: onBack)
        Spacer()
        StepDots(total: 3, current: step - 1)
        Spacer()
        // Mirror the back button width for optical centering
        Color.clear.frame(width: 44, height: 44)
    }
    .padding(.horizontal, 8)
    .padding(.top, 8)
    .padding(.bottom, 16)
}

// MARK: - Flow layout (reused from BrainDietPanel, isolated here)

private struct OnboardingFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > width && x > 0 { y += lineH + spacing; x = 0; lineH = 0 }
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
        return CGSize(width: width, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        var line: [(Subviews.Element, CGPoint)] = []
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX {
                line.forEach { $0.0.place(at: $0.1, proposal: .unspecified) }
                line = []; y += lineH + spacing; x = bounds.minX; lineH = 0
            }
            line.append((sv, CGPoint(x: x, y: y)))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
        line.forEach { $0.0.place(at: $0.1, proposal: .unspecified) }
    }
}
