import SwiftUI
import SwiftData

struct AdvancedSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appTheme)    private var appTheme
    @Environment(GradingProgressTracker.self)  private var gradingTracker
    @Environment(PipelineProgressTracker.self) private var pipelineTracker

    // Feed scheduling
    @AppStorage("rss.fetchHour")                   private var fetchHour:   Int  = RSSFetchService.defaultFetchHour
    @AppStorage("rss.fetchMinute")                 private var fetchMinute: Int  = RSSFetchService.defaultFetchMinute
    @AppStorage(RSSFetchService.fetch2EnabledKey)  private var fetch2Enabled:  Bool = false
    @AppStorage(RSSFetchService.fetchHour2Key)     private var fetchHour2:  Int  = RSSFetchService.defaultFetchHour2
    @AppStorage(RSSFetchService.fetchMinute2Key)   private var fetchMinute2: Int = RSSFetchService.defaultFetchMinute2
    @AppStorage(RSSFetchService.retentionDaysKey)  private var articleRetentionDays: Int = RSSFetchService.defaultRetentionDays
    @AppStorage("autoArchiveUnreadEnabled")        private var autoArchiveUnreadEnabled: Bool = false
    @AppStorage("autoArchiveUnreadDays")           private var autoArchiveUnreadDays: Int = 7
    @AppStorage("autoArchiveDeadEnabled")          private var autoArchiveDeadEnabled:  Bool = false
    @AppStorage("autoArchiveDeadDays")             private var autoArchiveDeadDays:  Int = 14

    // Reading / grading
    @AppStorage("grading.enabled")  private var gradingEnabled: Bool = false
    @AppStorage("digest.hideNoise") private var hideNoise:      Bool = false

    @Query private var allArticles: [RSSArticle]
    @Query(sort: \DailyEdition.date, order: .reverse) private var editions: [DailyEdition]

    @State private var editionGenerationState: EditionState = .idle
    private enum EditionState: Equatable { case idle, running }

    private enum DialogKind: Identifiable {
        case clearArticles, deduplicateArticles, resetEverything
        var id: Self { self }
    }
    @State private var activeDialog: DialogKind? = nil

    // MARK: - Computed

    private var duplicateCount: Int {
        var seen = Set<String>()
        var dupes = 0
        for a in allArticles { if !seen.insert(a.url).inserted { dupes += 1 } }
        return dupes
    }

    private var gradingProgressLabel: String {
        let total  = allArticles.count
        let graded = allArticles.filter { $0.qualityGrade != nil }.count
        guard total > 0 else { return "" }
        return "\(graded) of \(total) graded (\(Int((Double(graded) / Double(total)) * 100))%)"
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

    // MARK: - Body

    var body: some View {
        ZStack {
            appTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    feedsSection
                    processingSection
                    readingSection
                    dangerSection
                    developerSection
                }
                .padding(AppTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(appTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(
                get: { activeDialog != nil },
                set: { if !$0 { activeDialog = nil } }
            ),
            titleVisibility: .visible,
            presenting: activeDialog
        ) { dialog in
            switch dialog {
            case .clearArticles:
                Button("Clear articles", role: .destructive) { clearAllArticles() }
                Button("Cancel", role: .cancel) { }
            case .deduplicateArticles:
                Button("Remove duplicates", role: .destructive) { removeDuplicateArticles() }
                Button("Cancel", role: .cancel) { }
            case .resetEverything:
                Button("Reset everything", role: .destructive) { resetEverything() }
                Button("Cancel", role: .cancel) { }
            }
        } message: { dialog in
            switch dialog {
            case .clearArticles:
                Text("All \(allArticles.count) fetched articles will be deleted. Your queue, Brain, and streak are unaffected.")
            case .deduplicateArticles:
                Text("\(duplicateCount) duplicate article\(duplicateCount == 1 ? "" : "s") will be removed, keeping the richest copy of each.")
            case .resetEverything:
                Text("Your queue, Brain, streak, and feeds will be deleted. This cannot be undone.")
            }
        }
    }

    // MARK: - Feeds Section

    private var fetchTimeBinding: Binding<Date> {
        Binding(
            get: {
                var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                c.hour = fetchHour; c.minute = fetchMinute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                fetchHour   = c.hour   ?? RSSFetchService.defaultFetchHour
                fetchMinute = c.minute ?? RSSFetchService.defaultFetchMinute
                RSSFetchService.scheduleNextBackgroundTask()
            }
        )
    }

    private var fetchTime2Binding: Binding<Date> {
        Binding(
            get: {
                var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                c.hour = fetchHour2; c.minute = fetchMinute2
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                fetchHour2   = c.hour   ?? RSSFetchService.defaultFetchHour2
                fetchMinute2 = c.minute ?? RSSFetchService.defaultFetchMinute2
                RSSFetchService.scheduleNextBackgroundTask()
            }
        )
    }

    private var feedsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("FEEDS")

            HStack {
                settingLabel("Daily fetch", sub: "When background refresh runs.")
                Spacer()
                DatePicker("", selection: fetchTimeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .tint(appTheme.accent)
            }

            HStack {
                settingLabel("Second fetch", sub: "Run a second refresh later in the day.")
                Spacer()
                if fetch2Enabled {
                    DatePicker("", selection: fetchTime2Binding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(appTheme.accent)
                }
                Toggle("", isOn: $fetch2Enabled)
                    .labelsHidden()
                    .tint(appTheme.accent)
                    .onChange(of: fetch2Enabled) { _, _ in RSSFetchService.scheduleNextBackgroundTask() }
            }

            Divider().background(appTheme.separator)

            HStack {
                settingLabel("Article retention", sub: "How many days of feed articles to keep.")
                Spacer()
                Picker("", selection: $articleRetentionDays) {
                    Text("1 day").tag(1)
                    Text("2 days").tag(2)
                    Text("3 days").tag(3)
                    Text("5 days").tag(5)
                    Text("7 days").tag(7)
                }
                .pickerStyle(.menu)
                .font(AppTheme.sansSerif(14))
                .tint(appTheme.accent)
            }
            .onChange(of: articleRetentionDays) { _, _ in
                clearAllArticles()
                RSSFetchService.fetchInProcess(
                    container: context.container,
                    tracker: gradingTracker,
                    pipelineTracker: pipelineTracker
                )
            }

            Divider().background(appTheme.separator)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    settingLabel(
                        "Auto-archive unread",
                        sub: autoArchiveUnreadEnabled ? "Archive feeds you haven't read in:" : "Off"
                    )
                    Spacer()
                    Toggle("", isOn: $autoArchiveUnreadEnabled)
                        .labelsHidden()
                        .tint(appTheme.accent)
                }
                if autoArchiveUnreadEnabled {
                    Picker("", selection: $autoArchiveUnreadDays) {
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                    }
                    .pickerStyle(.segmented)
                }
            }

            Divider().background(appTheme.separator)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    settingLabel(
                        "Auto-archive dead feeds",
                        sub: autoArchiveDeadEnabled ? "Archive feeds with no new articles in:" : "Off"
                    )
                    Spacer()
                    Toggle("", isOn: $autoArchiveDeadEnabled)
                        .labelsHidden()
                        .tint(appTheme.accent)
                }
                if autoArchiveDeadEnabled {
                    Picker("", selection: $autoArchiveDeadDays) {
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    // MARK: - Processing Section

    private var processingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                sectionHeader("PROCESSING")
                Spacer()
                if IntelligenceService.isAvailable && !pipelineTracker.isRunning {
                    Button("Process now") {
                        RSSFetchService.pipelineInProcess(
                            container: context.container,
                            pipelineTracker: pipelineTracker
                        )
                    }
                    .font(AppTheme.sansSerif(13, weight: .medium))
                    .foregroundStyle(appTheme.accent)
                }
            }

            if !IntelligenceService.isAvailable {
                Text("Requires Apple Intelligence.")
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(appTheme.textFaint)
            } else if pipelineTracker.isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(appTheme.accent)
                    Text("\(pipelineTracker.phase) \(pipelineTracker.current) of \(pipelineTracker.total)…")
                        .font(AppTheme.sansSerif(13))
                        .foregroundStyle(appTheme.textFaint)
                    Spacer()
                }
            } else {
                if let error = pipelineTracker.lastError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.danger)
                        Text(error)
                            .font(AppTheme.sansSerif(13))
                            .foregroundStyle(AppTheme.danger.opacity(0.85))
                        Spacer()
                    }
                }

                VStack(spacing: 8) {
                    if pendingProcessingCount > 0 {
                        statRow("Pending", value: "\(pendingProcessingCount) articles")
                    }
                    if let tagSummary = pipelineTracker.lastTagSummary {
                        statRow("Tags", value: tagSummary)
                    }
                    if let summarySummary = pipelineTracker.lastSummarizeSummary {
                        statRow("Summaries", value: summarySummary)
                    }
                    if let runAt = pipelineTracker.lastRunAt {
                        statRow("Last run", value: lastRunLabel(runAt, duration: pipelineTracker.lastRunDuration))
                    }
                }
            }
        }
    }

    private func lastRunLabel(_ date: Date, duration: TimeInterval?) -> String {
        let timeStr = date.formatted(date: .omitted, time: .shortened)
        let cal = Calendar.current
        let label: String
        if cal.isDateInToday(date) {
            label = "today at \(timeStr)"
        } else if cal.isDateInYesterday(date) {
            label = "yesterday at \(timeStr)"
        } else {
            label = date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        guard let dur = duration, dur >= 1 else { return label }
        let mins = Int(dur / 60)
        let secs = Int(dur) % 60
        let durStr = mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
        return "\(label) · \(durStr)"
    }

    // MARK: - Reading / Grading Section

    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("READING")

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Article grading")
                        .font(AppTheme.sansSerif(15))
                        .foregroundStyle(IntelligenceService.isAvailable ? appTheme.heading : appTheme.textFaint)
                    if !IntelligenceService.isAvailable {
                        Text("Requires Apple Intelligence.")
                            .font(AppTheme.sansSerif(12))
                            .foregroundStyle(appTheme.textFaint)
                    } else if gradingEnabled && !allArticles.isEmpty {
                        Text(gradingProgressLabel)
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
                            RSSFetchService.gradeInProcess(
                                container: context.container,
                                tracker: gradingTracker
                            )
                        }
                    }
            }

            if gradingEnabled && IntelligenceService.isAvailable {
                gradingActionRow
                gradeBreakdown
            }

            Divider().background(appTheme.separator)

            HStack {
                Text("Hide noise from digest")
                    .font(AppTheme.sansSerif(15))
                    .foregroundStyle(gradingEnabled && IntelligenceService.isAvailable ? appTheme.heading : appTheme.textFaint)
                Spacer()
                Toggle("", isOn: $hideNoise)
                    .labelsHidden()
                    .tint(appTheme.accent)
                    .disabled(!gradingEnabled || !IntelligenceService.isAvailable)
            }
        }
    }

    @ViewBuilder
    private var gradingActionRow: some View {
        if gradingTracker.isRunning {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.75)
                    .tint(appTheme.accent)
                Text("Grading…")
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(appTheme.textFaint)
                Spacer()
            }
            .padding(.leading, 16)
        } else if let error = gradingTracker.lastError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.danger)
                Text(error)
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(AppTheme.danger.opacity(0.85))
                Spacer()
                Button("Retry") {
                    gradingTracker.lastError = nil
                    RSSFetchService.gradeInProcess(container: context.container, tracker: gradingTracker)
                }
                .font(AppTheme.sansSerif(13, weight: .medium))
                .foregroundStyle(appTheme.accent)
            }
            .padding(.leading, 16)
        } else {
            let ungradedCount = allArticles.filter { $0.qualityGrade == nil }.count
            if ungradedCount > 0 {
                HStack {
                    Spacer()
                    Button("Grade now") {
                        RSSFetchService.gradeInProcess(container: context.container, tracker: gradingTracker)
                    }
                    .font(AppTheme.sansSerif(13, weight: .medium))
                    .foregroundStyle(appTheme.accent)
                }
                .padding(.leading, 16)
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
        .padding(.leading, 16)
    }

    private func gradeRow(label: String, grade: ArticleQualityGrade, count: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < grade.filledCount ? grade.color : grade.color.opacity(0.2))
                        .frame(width: 5, height: 5)
                }
            }
            .frame(width: 22)
            .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(appTheme.textFaint)
                Text(grade.rationale)
                    .font(AppTheme.sansSerif(11))
                    .foregroundStyle(appTheme.textFaint.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text("\(count)")
                .font(AppTheme.sansSerif(13).monospacedDigit())
                .foregroundStyle(appTheme.textFaint)
                .padding(.top, 1)
        }
    }

    private func ungradedRow(count: Int) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(appTheme.accent.opacity(0.2))
                        .frame(width: 5, height: 5)
                }
            }
            .frame(width: 22)
            Text("Ungraded")
                .font(AppTheme.sansSerif(13))
                .foregroundStyle(appTheme.textFaint)
            Spacer()
            Text("\(count)")
                .font(AppTheme.sansSerif(13).monospacedDigit())
                .foregroundStyle(appTheme.textFaint)
        }
    }

    // MARK: - Danger Section

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("DANGER")

            if duplicateCount > 0 {
                dangerButton("Remove \(duplicateCount) duplicate article\(duplicateCount == 1 ? "" : "s").") {
                    activeDialog = .deduplicateArticles
                }
            }
            dangerButton("Clear all articles.") {
                activeDialog = .clearArticles
            }
            dangerButton("Reset everything.") {
                activeDialog = .resetEverything
            }
        }
    }

    private func dangerButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                Text(label)
                    .font(AppTheme.sansSerif(15, weight: .medium))
                    .foregroundStyle(AppTheme.danger)
                Spacer()
            }
            .frame(height: 48)
            .background(AppTheme.danger.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                    .stroke(AppTheme.danger.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.sansSerif(11, weight: .medium))
            .foregroundStyle(appTheme.textFaint)
            .tracking(2)
    }

    private func settingLabel(_ title: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AppTheme.sansSerif(15))
                .foregroundStyle(appTheme.heading)
            Text(sub)
                .font(AppTheme.sansSerif(12))
                .foregroundStyle(appTheme.textFaint)
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTheme.sansSerif(13))
                .foregroundStyle(appTheme.textFaint)
            Spacer()
            Text(value)
                .font(AppTheme.sansSerif(12).monospacedDigit())
                .foregroundStyle(appTheme.textFaint)
        }
    }

    // MARK: - Actions

    private var dialogTitle: String {
        switch activeDialog {
        case .clearArticles:       "Clear all articles?"
        case .deduplicateArticles: "Remove duplicates?"
        case .resetEverything:     "Reset everything?"
        case nil:                  ""
        }
    }

    private func clearAllArticles() {
        // Batch delete at the SQL level — avoids loading every article into memory.
        try? context.delete(model: RSSArticle.self)
        try? context.save()
    }

    private func removeDuplicateArticles() {
        RSSFetchService.deduplicateInProcess(container: context.container)
    }

    private func resetEverything() {
        try? context.delete(model: QueuedLink.self)
        try? context.delete(model: BrainEntry.self)
        try? context.delete(model: ReadingDay.self)
        try? context.delete(model: RSSFeed.self)
        try? context.delete(model: RSSArticle.self)
        try? context.save()
    }

    // MARK: - Developer Section

    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DEVELOPER")
                .font(AppTheme.sansSerif(11, weight: .medium))
                .foregroundStyle(appTheme.textFaint)
                .tracking(2)

            VStack(alignment: .leading, spacing: 10) {
                if let edition = editions.first(where: { Calendar.current.isDateInToday($0.date) }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Today's edition")
                                .font(AppTheme.sansSerif(14))
                                .foregroundStyle(appTheme.heading)
                            Text("\(edition.totalCount) articles · index \(edition.currentIndex)\(edition.isComplete ? " · complete" : "")")
                                .font(AppTheme.mono(11))
                                .foregroundStyle(appTheme.textFaint)
                        }
                        Spacer()
                    }
                    Divider().background(appTheme.separator)
                }

                Button {
                    generateEditionNow()
                } label: {
                    HStack(spacing: 8) {
                        if editionGenerationState == .running {
                            ProgressView()
                                .tint(appTheme.accent)
                                .scaleEffect(0.8)
                        }
                        Text(editionGenerationState == .running ? "Generating…" : "Generate Edition Now")
                            .font(AppTheme.sansSerif(14, weight: editionGenerationState == .idle ? .medium : .regular))
                            .foregroundStyle(editionGenerationState == .idle ? appTheme.accent : appTheme.textFaint)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .disabled(editionGenerationState == .running)
            }
        }
    }

    private func generateEditionNow() {
        editionGenerationState = .running
        // Clear any existing edition for today so the guard doesn't skip generation.
        for edition in editions where Calendar.current.isDateInToday(edition.date) {
            context.delete(edition)
        }
        try? context.save()

        Task {
            let actor = RSSFetchActor(modelContainer: context.container)
            await actor.generateDailyEditionIfNeeded()
            editionGenerationState = .idle
        }
    }
}
