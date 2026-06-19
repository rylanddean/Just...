import SwiftUI
import SwiftData

struct ProcessingSheet: View {
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.appTheme)     private var appTheme
    @Environment(GradingProgressTracker.self)  private var gradingTracker
    @Environment(PipelineProgressTracker.self) private var pipelineTracker

    @AppStorage("grading.enabled") private var gradingEnabled: Bool = false

    @Query private var allArticles: [RSSArticle]

    var body: some View {
        NavigationStack {
            ZStack {
                appTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        articlesSection
                        Divider().background(appTheme.separator)
                        qualitySection
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Intelligence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                        .font(AppTheme.sansSerif(15, weight: .medium))
                        .foregroundStyle(appTheme.accent)
                }
            }
            .toolbarBackground(appTheme.background, for: .navigationBar)
            .toolbarColorScheme(appTheme.colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
        .preferredColorScheme(appTheme.colorScheme)
    }

    // MARK: - Your articles

    private var articlesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("YOUR ARTICLES")

            Text("Just… uses Apple Intelligence to sort your digest by topic and build summaries. This runs in the background after each fetch.")
                .font(AppTheme.sansSerif(13))
                .foregroundStyle(appTheme.textFaint)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 2)

            articlesStatus
        }
    }

    @ViewBuilder
    private var articlesStatus: some View {
        if !IntelligenceService.isAvailable {
            Text("Requires Apple Intelligence on this device.")
                .font(AppTheme.sansSerif(13))
                .foregroundStyle(appTheme.textFaint)
        } else if pipelineTracker.isRunning {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.75)
                    .tint(appTheme.accent)
                Text("Reading your articles… \(pipelineTracker.current) of \(pipelineTracker.total)")
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(appTheme.textFaint)
                Spacer()
            }
        } else if let error = pipelineTracker.lastError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.danger)
                Text(error)
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(AppTheme.danger.opacity(0.85))
                Spacer()
                Button("Try again") {
                    RSSFetchService.pipelineInProcess(
                        container: context.container,
                        pipelineTracker: pipelineTracker
                    )
                }
                .font(AppTheme.sansSerif(13, weight: .medium))
                .foregroundStyle(appTheme.accent)
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    if pendingProcessingCount > 0 {
                        Text("\(pendingProcessingCount) \(pendingProcessingCount == 1 ? "article" : "articles") not yet read.")
                            .font(AppTheme.sansSerif(13))
                            .foregroundStyle(appTheme.textFaint)
                    } else if let runAt = pipelineTracker.lastRunAt {
                        Text("All read.")
                            .font(AppTheme.sansSerif(13))
                            .foregroundStyle(appTheme.textFaint)
                        Text("Updated \(lastRunLabel(runAt))")
                            .font(AppTheme.mono(11))
                            .foregroundStyle(appTheme.textFaint.opacity(0.6))
                    }
                }
                Spacer()
                if pendingProcessingCount > 0 {
                    Button("Read now") {
                        RSSFetchService.pipelineInProcess(
                            container: context.container,
                            pipelineTracker: pipelineTracker
                        )
                    }
                    .font(AppTheme.sansSerif(13, weight: .medium))
                    .foregroundStyle(appTheme.accent)
                }
            }
        }
    }

    // MARK: - Quality filter

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("QUALITY FILTER")

            Text("Rates each article so you can hide low-quality content from your digest. Enable Hide noise in the filter to use it.")
                .font(AppTheme.sansSerif(13))
                .foregroundStyle(appTheme.textFaint)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 2)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Filter by quality")
                        .font(AppTheme.sansSerif(15))
                        .foregroundStyle(IntelligenceService.isAvailable ? appTheme.heading : appTheme.textFaint)
                    if !IntelligenceService.isAvailable {
                        Text("Requires Apple Intelligence on this device.")
                            .font(AppTheme.sansSerif(12))
                            .foregroundStyle(appTheme.textFaint)
                    } else if gradingEnabled && gradedCount > 0 {
                        Text("\(gradedCount) of \(allArticles.count) rated")
                            .font(AppTheme.sansSerif(12))
                            .foregroundStyle(appTheme.textFaint)
                    }
                }
                Spacer()
                Toggle("", isOn: $gradingEnabled)
                    .labelsHidden()
                    .tint(appTheme.accent)
                    .disabled(!IntelligenceService.isAvailable)
                    .onChange(of: gradingEnabled) { _, enabled in
                        if enabled {
                            RSSFetchService.gradeInProcess(container: context.container, tracker: gradingTracker)
                        }
                    }
            }

            if gradingEnabled && IntelligenceService.isAvailable {
                qualityActionRow
                    .padding(.top, 4)
                gradeBreakdown
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var qualityActionRow: some View {
        if gradingTracker.isRunning {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.75)
                    .tint(appTheme.accent)
                Text("Rating your articles…")
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(appTheme.textFaint)
                Spacer()
            }
        } else if let error = gradingTracker.lastError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.danger)
                Text(error)
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(AppTheme.danger.opacity(0.85))
                Spacer()
                Button("Try again") {
                    gradingTracker.lastError = nil
                    RSSFetchService.gradeInProcess(container: context.container, tracker: gradingTracker)
                }
                .font(AppTheme.sansSerif(13, weight: .medium))
                .foregroundStyle(appTheme.accent)
            }
        } else {
            let ungradedCount = allArticles.filter { $0.qualityGrade == nil }.count
            if ungradedCount > 0 {
                HStack {
                    Text("\(ungradedCount) \(ungradedCount == 1 ? "article" : "articles") not yet rated.")
                        .font(AppTheme.sansSerif(13))
                        .foregroundStyle(appTheme.textFaint)
                    Spacer()
                    Button("Rate now") {
                        RSSFetchService.gradeInProcess(container: context.container, tracker: gradingTracker)
                    }
                    .font(AppTheme.sansSerif(13, weight: .medium))
                    .foregroundStyle(appTheme.accent)
                }
            }
        }
    }

    private var gradeBreakdown: some View {
        VStack(spacing: 6) {
            gradeRow(label: "Strong",   grade: .strong,  count: gradeCounts.strong)
            gradeRow(label: "Worth it", grade: .worthIt, count: gradeCounts.worthIt)
            gradeRow(label: "Noise",    grade: .noise,   count: gradeCounts.noise)
            ungradedRow(count: gradeCounts.ungraded)
        }
    }

    private func gradeRow(label: String, grade: ArticleQualityGrade, count: Int) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < grade.filledCount ? grade.color : grade.color.opacity(0.15))
                        .frame(width: 5, height: 5)
                }
            }
            .frame(width: 22)
            Text(label)
                .font(AppTheme.sansSerif(13))
                .foregroundStyle(appTheme.textFaint)
            Spacer()
            Text("\(count)")
                .font(AppTheme.sansSerif(13).monospacedDigit())
                .foregroundStyle(appTheme.textFaint)
        }
    }

    private func ungradedRow(count: Int) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(appTheme.textFaint.opacity(0.2))
                        .frame(width: 5, height: 5)
                }
            }
            .frame(width: 22)
            Text("Not yet rated")
                .font(AppTheme.sansSerif(13))
                .foregroundStyle(appTheme.textFaint)
            Spacer()
            Text("\(count)")
                .font(AppTheme.sansSerif(13).monospacedDigit())
                .foregroundStyle(appTheme.textFaint)
        }
    }

    // MARK: - Helpers

    private var gradedCount: Int {
        allArticles.filter { $0.qualityGrade != nil }.count
    }

    private var gradeCounts: (strong: Int, worthIt: Int, noise: Int, ungraded: Int) {
        var s = 0, w = 0, n = 0, u = 0
        for a in allArticles {
            switch a.qualityGrade {
            case .strong:  s += 1
            case .worthIt: w += 1
            case .noise:   n += 1
            case nil:      u += 1
            }
        }
        return (s, w, n, u)
    }

    private var pendingProcessingCount: Int {
        allArticles.filter { a in
            a.topics.isEmpty || (a.feedDescription != nil && a.summary == nil)
        }.count
    }

    private func sectionHeader(_ label: String) -> some View {
        Text(label)
            .font(AppTheme.mono(11))
            .foregroundStyle(appTheme.textFaint)
            .tracking(2)
    }

    private func lastRunLabel(_ date: Date) -> String {
        let timeStr = date.formatted(date: .omitted, time: .shortened)
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "today at \(timeStr)" }
        if cal.isDateInYesterday(date) { return "yesterday at \(timeStr)" }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
