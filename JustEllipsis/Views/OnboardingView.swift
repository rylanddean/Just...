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

// MARK: - Steps

private enum OnboardingStep: Int, CaseIterable {
    case brand      // 0 — brand mark
    case problem    // 1 — the problem
    case reader     // 2 — the reader
    case reflect    // 3 — the reflect window
    case brain      // 4 — the Brain
    case interests  // 5 — pick interests (seeding)
    case sources    // 6 — pick sources  (seeding)
    case start      // 7 — get started

    /// Narrative cards that show the top-right skip control (all except the
    /// brand mark and the practical seeding/start steps).
    var showsSkip: Bool {
        switch self {
        case .problem, .reader, .reflect, .brain: return true
        default: return false
        }
    }
}

// MARK: - Root container

struct OnboardingView: View {
    /// Reports whether the user seeded any feeds, so the caller can decide
    /// whether to prompt them to add their first link.
    var onComplete: (_ seededFeeds: Bool) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.appTheme) private var appTheme

    @State private var step: OnboardingStep = .brand
    @State private var selectedInterests: Set<String> = []
    @State private var addedURLs: Set<String> = []

    private let allDirectoryItems: [FeedDirectoryItem] = FeedDirectoryItem.loadAll()

    private var suggestedSources: [FeedDirectoryItem] {
        let interests = OnboardingInterest.all.filter { selectedInterests.contains($0.id) }

        // No interests picked — fall back to a broad sample so the sources
        // step is never empty for users who swipe past the chips.
        guard !interests.isEmpty else {
            return Array(allDirectoryItems.shuffled().prefix(12))
        }

        var result: [FeedDirectoryItem] = []
        var seenURLs = Set<String>()

        for interest in interests {
            let matches = allDirectoryItems
                .filter { interest.categories.contains($0.category) }
                .shuffled()
                .prefix(3)
            for item in matches where seenURLs.insert(item.url).inserted {
                result.append(item)
            }
        }
        return Array(result.prefix(12))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            appTheme.background.ignoresSafeArea()

            TabView(selection: $step) {
                BrandMarkScreen()
                    .tag(OnboardingStep.brand)

                ProblemScreen()
                    .tag(OnboardingStep.problem)

                ReaderScreen()
                    .tag(OnboardingStep.reader)

                ReflectScreen()
                    .tag(OnboardingStep.reflect)

                BrainScreen()
                    .tag(OnboardingStep.brain)

                InterestsStep(
                    selectedInterests: $selectedInterests,
                    onContinue: { advance(to: .sources) }
                )
                .tag(OnboardingStep.interests)

                SourcesStep(
                    sources: suggestedSources,
                    addedURLs: $addedURLs,
                    onContinue: { advance(to: .start) }
                )
                .tag(OnboardingStep.sources)

                StartScreen(
                    seededCount: addedURLs.count,
                    onGetStarted: finish
                )
                .tag(OnboardingStep.start)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if step.showsSkip {
                Button("Skip") { advance(to: .interests) }
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(appTheme.textFaint)
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: step)
        .preferredColorScheme(appTheme.colorScheme)
    }

    private func advance(to target: OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.3)) { step = target }
    }

    private func finish() {
        let chosen = suggestedSources.filter { addedURLs.contains($0.url) }
        for source in chosen {
            let feed = RSSFeed(url: source.url, title: source.name, category: source.category)
            context.insert(feed)
        }
        try? context.save()
        onComplete(!chosen.isEmpty)
    }
}

// MARK: - Screen 1: Brand mark

private struct BrandMarkScreen: View {
    @Environment(\.appTheme) private var appTheme

    @State private var nudge = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                Text("Just…")
                    .font(AppTheme.playfair(56, weight: .bold))
                    .foregroundStyle(appTheme.heading)

                Text("READ. THINK. GROW.")
                    .font(AppTheme.sansSerif(11, weight: .medium))
                    .foregroundStyle(appTheme.textFaint)
                    .kerning(3)
            }
            .offset(y: nudge ? -8 : 0)

            Spacer()

            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(appTheme.textFaint)
                .opacity(nudge ? 0.9 : 0.0)
                .offset(x: nudge ? -6 : 6)
                .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    nudge = true
                }
            }
        }
    }
}

// MARK: - Screen 2: The Problem

private struct ProblemScreen: View {
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        NarrativeScaffold {
            Image(systemName: "hourglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(appTheme.accent.opacity(0.55))
        } headline: {
            "You save links you never read."
        } body: {
            "Just… is different. It's not a read-later app. It's a reading habit. Your queue is for reading now, not someday."
        }
    }
}

// MARK: - Screen 3: The Reader

private struct ReaderScreen: View {
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        NarrativeScaffold {
            Image(systemName: "book")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(appTheme.accent)
        } headline: {
            "Strip. Focus. Read."
        } body: {
            "Every article is stripped to words. No images, no ads, no distractions. Just the text."
        } extra: {
            ReaderMockup()
                .padding(.top, 24)
        }
    }
}

private struct ReaderMockup: View {
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The Art of Paying Attention")
                .font(AppTheme.serif(18, weight: .bold))
                .foregroundStyle(appTheme.heading)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(0..<3, id: \.self) { _ in
                    Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor.")
                        .font(AppTheme.serif(14))
                        .foregroundStyle(appTheme.textFaint)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.cardPadding)
        .background(appTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(appTheme.separator, lineWidth: 1)
        )
    }
}

// MARK: - Screen 4: The Reflect window

private struct ReflectScreen: View {
    @Environment(\.appTheme) private var appTheme

    @State private var showWhy = false

    var body: some View {
        NarrativeScaffold {
            Text("…")
                .font(AppTheme.playfair(48, weight: .bold))
                .foregroundStyle(appTheme.accent)
        } headline: {
            "60 seconds."
        } body: {
            "After each article, a clock starts. One thought. Type it or say it. Research shows this single minute doubles what you remember."
        } extra: {
            Button {
                showWhy = true
            } label: {
                Text("Why this works →")
                    .font(AppTheme.sansSerif(14, weight: .medium))
                    .foregroundStyle(appTheme.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
        }
        .sheet(isPresented: $showWhy) {
            WhyThisWorksSheet()
                .environment(\.appTheme, appTheme)
        }
    }
}

private struct WhyThisWorksSheet: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            appTheme.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Why this works")
                        .font(AppTheme.serif(30, weight: .bold))
                        .foregroundStyle(appTheme.heading)
                        .padding(.top, 8)

                    Text("Reading without reflecting is like exercising without sleeping. The growth happens in the pause.")
                        .font(AppTheme.serif(18))
                        .foregroundStyle(appTheme.text)
                        .lineSpacing(4)

                    researchPoint(
                        "The forgetting curve",
                        "Passive reading without reflection loses most of what you read within hours. The brain discards what it never had to retrieve."
                    )
                    researchPoint(
                        "The testing effect",
                        "Writing or saying one thought after reading forces retrieval — the single most research-backed way to retain what you read. Even one sentence outperforms re-reading the same article."
                    )
                    researchPoint(
                        "The production effect",
                        "Speaking a thought aloud is as effective as writing it. The act of producing the idea, in any form, is what makes it stick."
                    )
                    researchPoint(
                        "The Brain compounds",
                        "Returning to an old entry reactivates and extends the memory. What you keep keeps growing."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 40)
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(appTheme.textFaint)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 8)
                .background(appTheme.background)
            }
        }
        .preferredColorScheme(appTheme.colorScheme)
    }

    private func researchPoint(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(AppTheme.sansSerif(11, weight: .medium))
                .foregroundStyle(appTheme.accent)
                .kerning(1.6)

            Text(body)
                .font(AppTheme.sansSerif(15))
                .foregroundStyle(appTheme.text)
                .lineSpacing(4)
        }
    }
}

// MARK: - Screen 5: The Brain

private struct BrainScreen: View {
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        NarrativeScaffold {
            ZStack {
                Circle()
                    .fill(appTheme.accent.opacity(0.12))
                    .frame(width: 72, height: 72)
                Circle()
                    .stroke(appTheme.accent.opacity(0.5), lineWidth: 2)
                    .frame(width: 56, height: 56)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(appTheme.accent.opacity(0.7))
            }
        } headline: {
            "Your Brain grows."
        } body: {
            "Every article you finish. Every thought you capture. Stored in your Brain. It never shrinks."
        } extra: {
            RankLadder()
                .padding(.top, 28)
        }
    }
}

private struct RankLadder: View {
    @Environment(\.appTheme) private var appTheme

    private let ranks = BrainRank.allCases

    var body: some View {
        OnboardingFlowLayout(spacing: 8) {
            ForEach(Array(ranks.enumerated()), id: \.offset) { index, rank in
                HStack(spacing: 8) {
                    Text(rank.rawValue)
                        .font(AppTheme.sansSerif(13, weight: .medium))
                        .foregroundStyle(appTheme.text)

                    if index < ranks.count - 1 {
                        Circle()
                            .fill(appTheme.accent)
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
    }
}

// MARK: - Narrative scaffold

private struct NarrativeScaffold<Icon: View, Extra: View>: View {
    @Environment(\.appTheme) private var appTheme

    let icon: Icon
    let headline: String
    let body0: String
    let extra: Extra

    init(
        @ViewBuilder icon: () -> Icon,
        headline: () -> String,
        body: () -> String,
        @ViewBuilder extra: () -> Extra
    ) {
        self.icon = icon()
        self.headline = headline()
        self.body0 = body()
        self.extra = extra()
    }

    init(
        @ViewBuilder icon: () -> Icon,
        headline: () -> String,
        body: () -> String
    ) where Extra == EmptyView {
        self.init(icon: icon, headline: headline, body: body, extra: { EmptyView() })
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                icon
                    .padding(.bottom, 4)

                Text(headline)
                    .font(AppTheme.serif(34, weight: .bold))
                    .foregroundStyle(appTheme.heading)
                    .lineSpacing(2)

                Text(body0)
                    .font(AppTheme.sansSerif(16))
                    .foregroundStyle(appTheme.text)
                    .lineSpacing(5)

                extra

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 96)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Primary CTA button

private struct PrimaryButton: View {
    let label: String
    let action: () -> Void

    @Environment(\.appTheme) private var appTheme

    init(_ label: String, action: @escaping () -> Void) {
        self.label = label
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
        .background(appTheme.accent)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Step 5: Interests

private struct InterestsStep: View {
    @Binding var selectedInterests: Set<String>
    let onContinue: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What do you\nread about?")
                            .font(AppTheme.serif(34, weight: .bold))
                            .foregroundStyle(appTheme.heading)
                            .lineSpacing(2)

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
                .padding(.top, 72)
                .padding(.bottom, 32)
            }

            PrimaryButton("Continue", action: onContinue)
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

// MARK: - Step 6: Sources

private struct SourcesStep: View {
    let sources: [FeedDirectoryItem]
    @Binding var addedURLs: Set<String>
    let onContinue: () -> Void

    @Environment(\.appTheme) private var appTheme

    private var addedCount: Int { addedURLs.count }
    private var ctaLabel: String {
        addedCount == 0 ? "Continue" : "Continue (\(addedCount))"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Some writers\nto start with.")
                    .font(AppTheme.serif(34, weight: .bold))
                    .foregroundStyle(appTheme.heading)
                    .lineSpacing(2)

                Text("Add a few. You can always change these later.")
                    .font(AppTheme.sansSerif(14))
                    .foregroundStyle(appTheme.textFaint)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 72)
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

            PrimaryButton(ctaLabel, action: onContinue)
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

// MARK: - Step 7: Start

private struct StartScreen: View {
    let seededCount: Int
    let onGetStarted: () -> Void

    @Environment(\.appTheme) private var appTheme

    private var bodyText: String {
        seededCount == 0
            ? "Share anything from Safari. Or paste a URL."
            : "Your feeds are ready. Add anything else from Safari, or paste a URL."
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 20) {
                Text("Add your\nfirst link.")
                    .font(AppTheme.serif(34, weight: .bold))
                    .foregroundStyle(appTheme.heading)
                    .lineSpacing(2)

                Text(bodyText)
                    .font(AppTheme.sansSerif(16))
                    .foregroundStyle(appTheme.text)
                    .lineSpacing(5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.pagePadding)

            Spacer()

            PrimaryButton("Get started", action: onGetStarted)
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 48)
        }
    }
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
