import SwiftUI
import SwiftData
import CoreData
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.appTheme)     private var appTheme

    // Appearance / reading
    @AppStorage(ReaderTheme.defaultsKey)                 private var themeRaw:              String = "ember"
    @AppStorage("streak.minReadsPerDay")                 private var minReadsPerDay:        Int    = 1
    @AppStorage(JustEllipsisApp.iCloudSyncKey)           private var iCloudSyncEnabled:     Bool   = false
    @AppStorage(NightModeService.startHourKey)           private var nightStartHour:        Int    = NightModeService.defaultStartHour
    @AppStorage(NightModeService.startMinuteKey)         private var nightStartMinute:      Int    = NightModeService.defaultStartMinute
    @AppStorage(NightModeService.overrideKey)            private var nightOverride:         String = "auto"
    @AppStorage("activityRings.enabled")                 private var activityRingsEnabled:  Bool   = false
    @AppStorage("rewrite.enabled")                       private var rewriteEnabled:        Bool   = true

    // Reminders
    @AppStorage(NotificationScheduler.morningEnabledKey) private var morningEnabled:  Bool = false
    @AppStorage(NotificationScheduler.morningHourKey)    private var morningHour:     Int  = NotificationScheduler.defaultMorningHour
    @AppStorage(NotificationScheduler.morningMinuteKey)  private var morningMinute:   Int  = NotificationScheduler.defaultMorningMinute
    @AppStorage(NotificationScheduler.eveningEnabledKey) private var eveningEnabled:  Bool = false
    @AppStorage(NotificationScheduler.eveningHourKey)    private var eveningHour:     Int  = NotificationScheduler.defaultEveningHour
    @AppStorage(NotificationScheduler.eveningMinuteKey)  private var eveningMinute:   Int  = NotificationScheduler.defaultEveningMinute
    @AppStorage(NotificationScheduler.editionEnabledKey) private var editionEnabled:  Bool = false

    // Feeds
    @AppStorage("rss.fetchHour")                        private var fetchHour:               Int  = RSSFetchService.defaultFetchHour
    @AppStorage("rss.fetchMinute")                      private var fetchMinute:             Int  = RSSFetchService.defaultFetchMinute
    @AppStorage(RSSFetchService.fetch2EnabledKey)       private var fetch2Enabled:           Bool = false
    @AppStorage(RSSFetchService.fetchHour2Key)          private var fetchHour2:              Int  = RSSFetchService.defaultFetchHour2
    @AppStorage(RSSFetchService.fetchMinute2Key)        private var fetchMinute2:            Int  = RSSFetchService.defaultFetchMinute2
    @AppStorage(RSSFetchService.retentionDaysKey)       private var articleRetentionDays:    Int  = RSSFetchService.defaultRetentionDays
    @AppStorage("autoArchiveUnreadEnabled")             private var autoArchiveUnreadEnabled: Bool = false
    @AppStorage("autoArchiveUnreadDays")                private var autoArchiveUnreadDays:   Int  = 7
    @AppStorage("autoArchiveDeadEnabled")               private var autoArchiveDeadEnabled:  Bool = false
    @AppStorage("autoArchiveDeadDays")                  private var autoArchiveDeadDays:     Int  = 14

    // Reading / grading
    @AppStorage("grading.enabled")                      private var gradingEnabled: Bool = false
    @AppStorage("digest.hideNoise")                     private var hideNoise:      Bool = false

    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined

    @Environment(HealthKitService.self)          private var healthKit
    @Environment(GradingProgressTracker.self)    private var gradingTracker
    @Environment(PipelineProgressTracker.self)   private var pipelineTracker

    @Query private var allArticles: [RSSArticle]
    @Query(sort: \DailyEdition.date, order: .reverse) private var editions: [DailyEdition]

    private enum DialogKind: Identifiable {
        case clearStreak, forceUpload, forceRestore, clearArticles, deduplicateArticles, resetEverything
        var id: Self { self }
    }

    private enum SyncPhase {
        case idle, syncing, success(String), failure(String)
    }

    private enum EditionState: Equatable { case idle, running }

    @State private var versionTapCount = 0
    @State private var activeDialog: DialogKind? = nil
    @State private var syncPhase: SyncPhase = .idle
    @State private var developerUnlocked = false
    @State private var editionGenerationState: EditionState = .idle

    // MARK: - Computed

    private var selectedTheme: ReaderTheme {
        ReaderTheme(rawValue: themeRaw) ?? .ember
    }

    private var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private var duplicateCount: Int {
        var seen = Set<String>()
        var dupes = 0
        for a in allArticles { if !seen.insert(a.url).inserted { dupes += 1 } }
        return dupes
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                appTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        syncSection
                        streakSection
                        remindersSection
                        readingSection
                        appearanceSection
                        feedsSection
                        dangerSection
                        if developerUnlocked {
                            developerSection
                        }
                        versionFooter
                    }
                    .padding(AppTheme.pagePadding)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(AppTheme.sansSerif(15))
                        .foregroundStyle(appTheme.accent)
                }
            }
            .toolbarBackground(appTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(appTheme.colorScheme)
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(get: { activeDialog != nil },
                                 set: { if !$0 { activeDialog = nil } }),
            titleVisibility: .visible,
            presenting: activeDialog
        ) { dialog in
            switch dialog {
            case .clearStreak:
                Button("Clear streak", role: .destructive) { clearStreak() }
                Button("Cancel", role: .cancel) { }
            case .forceUpload:
                Button("Upload") { Task { await performForceUpload() } }
                Button("Cancel", role: .cancel) { }
            case .forceRestore:
                Button("Restore", role: .destructive) { scheduleCloudRestore() }
                Button("Cancel", role: .cancel) { }
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
            case .clearStreak:
                Text("Your reading streak and daily history will be deleted.")
            case .forceUpload:
                Text("Your local data will be pushed to iCloud. Any differences on other devices will be resolved on their next sync.")
            case .forceRestore:
                Text("Local data will be cleared and replaced from iCloud the next time you open Just….")
            case .clearArticles:
                Text("All \(allArticles.count) fetched articles will be deleted. Your queue, Brain, and streak are unaffected.")
            case .deduplicateArticles:
                Text("\(duplicateCount) duplicate article\(duplicateCount == 1 ? "" : "s") will be removed, keeping the richest copy of each.")
            case .resetEverything:
                Text("Your queue, Brain, streak, and feeds will be deleted. This cannot be undone.")
            }
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("SYNC")

            if iCloudAvailable {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sync with iCloud")
                                .font(AppTheme.sansSerif(15))
                                .foregroundStyle(appTheme.heading)
                            Text("Your queue, Brain, and streak sync across devices on this Apple ID.")
                                .font(AppTheme.sansSerif(12))
                                .foregroundStyle(appTheme.textFaint)
                        }
                        Spacer()
                        Toggle("", isOn: $iCloudSyncEnabled)
                            .labelsHidden()
                            .tint(appTheme.accent)
                    }

                    if iCloudSyncEnabled {
                        Text("Active the next time you open Just…")
                            .font(AppTheme.sansSerif(12))
                            .foregroundStyle(appTheme.accent.opacity(0.7))

                        Divider().background(appTheme.separator)

                        syncActionRow(
                            title: "Upload to iCloud",
                            subtitle: "Push this device's data to iCloud."
                        ) {
                            syncPhase = .idle
                            activeDialog = .forceUpload
                        }

                        syncActionRow(
                            title: "Restore from iCloud",
                            subtitle: "Replace local data from iCloud on next launch."
                        ) {
                            syncPhase = .idle
                            activeDialog = .forceRestore
                        }

                        syncPhaseFeedback
                    }
                }
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("iCloud is off.")
                            .font(AppTheme.sansSerif(15))
                            .foregroundStyle(appTheme.heading)
                        Text("Enable iCloud Drive in Settings to sync.")
                            .font(AppTheme.sansSerif(12))
                            .foregroundStyle(appTheme.textFaint)
                    }
                    Spacer()
                    Button("Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(appTheme.accent)
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSPersistentCloudKitContainer.eventChangedNotification
            ).receive(on: RunLoop.main)
        ) { notification in
            handleCloudKitEvent(notification)
        }
    }

    @ViewBuilder
    private var syncPhaseFeedback: some View {
        switch syncPhase {
        case .idle:
            EmptyView()
        case .syncing:
            HStack(spacing: 8) {
                ProgressView()
                    .tint(appTheme.accent)
                    .scaleEffect(0.75)
                Text("Syncing to iCloud…")
                    .font(AppTheme.sansSerif(12))
                    .foregroundStyle(appTheme.accent.opacity(0.7))
            }
        case .success(let message):
            Text(message)
                .font(AppTheme.sansSerif(12))
                .foregroundStyle(appTheme.accent.opacity(0.7))
        case .failure(let message):
            Text(message)
                .font(AppTheme.sansSerif(12))
                .foregroundStyle(AppTheme.danger.opacity(0.85))
        }
    }

    private func syncActionRow(
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppTheme.sansSerif(14))
                        .foregroundStyle(appTheme.heading)
                    Text(subtitle)
                        .font(AppTheme.sansSerif(12))
                        .foregroundStyle(appTheme.textFaint)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(appTheme.textFaint)
            }
        }
        .buttonStyle(.plain)
        .disabled({ if case .syncing = syncPhase { return true }; return false }())
    }

    // MARK: - Streak

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("STREAK")

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reads per day")
                        .font(AppTheme.sansSerif(15))
                        .foregroundStyle(appTheme.heading)
                    Text("Minimum to count the day.")
                        .font(AppTheme.sansSerif(12))
                        .foregroundStyle(appTheme.textFaint)
                }

                Spacer()

                HStack(spacing: 0) {
                    Button {
                        if minReadsPerDay > 1 { minReadsPerDay -= 1 }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(minReadsPerDay > 1 ? appTheme.accent : appTheme.textFaint)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)

                    Text("\(minReadsPerDay)")
                        .font(AppTheme.sansSerif(17, weight: .semibold))
                        .foregroundStyle(appTheme.heading)
                        .monospacedDigit()
                        .frame(minWidth: 28, alignment: .center)

                    Button {
                        if minReadsPerDay < 5 { minReadsPerDay += 1 }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(minReadsPerDay < 5 ? appTheme.accent : appTheme.textFaint)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                }
                .background(appTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Reminders

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("REMINDERS")

            if notificationAuthStatus == .denied {
                HStack {
                    Text("Notification permission required.")
                        .font(AppTheme.sansSerif(14))
                        .foregroundStyle(appTheme.textFaint)
                    Spacer()
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(appTheme.accent)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Morning nudge")
                                .font(AppTheme.sansSerif(15))
                                .foregroundStyle(appTheme.heading)
                            Text("Reminder to read if your queue isn't empty.")
                                .font(AppTheme.sansSerif(12))
                                .foregroundStyle(appTheme.textFaint)
                        }
                        Spacer()
                        Toggle("", isOn: $morningEnabled)
                            .labelsHidden()
                            .tint(appTheme.accent)
                            .onChange(of: morningEnabled) { _, enabled in
                                if enabled { Task { await requestPermissionIfNeeded() } }
                            }
                    }
                    if morningEnabled {
                        HStack {
                            Text("Time")
                                .font(AppTheme.sansSerif(13))
                                .foregroundStyle(appTheme.textFaint)
                            Spacer()
                            DatePicker("", selection: morningTimeBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .tint(appTheme.accent)
                        }
                    }
                }

                Divider().background(appTheme.separator)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Streak reminder")
                                .font(AppTheme.sansSerif(15))
                                .foregroundStyle(appTheme.heading)
                            Text("Alert in the evening if your streak is still at risk.")
                                .font(AppTheme.sansSerif(12))
                                .foregroundStyle(appTheme.textFaint)
                        }
                        Spacer()
                        Toggle("", isOn: $eveningEnabled)
                            .labelsHidden()
                            .tint(appTheme.accent)
                            .onChange(of: eveningEnabled) { _, enabled in
                                if enabled { Task { await requestPermissionIfNeeded() } }
                            }
                    }
                    if eveningEnabled {
                        HStack {
                            Text("Time")
                                .font(AppTheme.sansSerif(13))
                                .foregroundStyle(appTheme.textFaint)
                            Spacer()
                            DatePicker("", selection: eveningTimeBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .tint(appTheme.accent)
                        }
                    }
                }

                Divider().background(appTheme.separator)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Daily Edition")
                            .font(AppTheme.sansSerif(15))
                            .foregroundStyle(appTheme.heading)
                        Text("Notify when today's edition is ready.")
                            .font(AppTheme.sansSerif(12))
                            .foregroundStyle(appTheme.textFaint)
                    }
                    Spacer()
                    Toggle("", isOn: $editionEnabled)
                        .labelsHidden()
                        .tint(appTheme.accent)
                        .onChange(of: editionEnabled) { _, enabled in
                            if enabled { Task { await requestPermissionIfNeeded() } }
                        }
                }
            }
        }
        .task {
            notificationAuthStatus = await NotificationScheduler.authorizationStatus()
        }
    }

    private func requestPermissionIfNeeded() async {
        guard notificationAuthStatus == .notDetermined else { return }
        _ = await NotificationScheduler.requestPermission()
        notificationAuthStatus = await NotificationScheduler.authorizationStatus()
    }

    // MARK: - Reading (rewrite + rings + hide noise)

    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("READING")

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rewrite clickbait titles")
                        .font(AppTheme.sansSerif(15))
                        .foregroundStyle(
                            IntelligenceService.isAvailable ? appTheme.heading : appTheme.textFaint
                        )
                    Text(
                        IntelligenceService.isAvailable
                            ? "Calm, factual titles replace manipulative ones. Tap ✦ to see the original."
                            : "Requires Apple Intelligence."
                    )
                    .font(AppTheme.sansSerif(12))
                    .foregroundStyle(appTheme.textFaint)
                }
                Spacer()
                Toggle("", isOn: $rewriteEnabled)
                    .labelsHidden()
                    .tint(appTheme.accent)
                    .disabled(!IntelligenceService.isAvailable)
            }

            Divider().background(appTheme.separator)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Activity rings")
                        .font(AppTheme.sansSerif(15))
                        .foregroundStyle(HealthKitService.isAvailable ? appTheme.heading : appTheme.textFaint)
                    Text(
                        HealthKitService.isAvailable
                            ? "Reading counts toward your fitness rings."
                            : "Not available on this device."
                    )
                    .font(AppTheme.sansSerif(12))
                    .foregroundStyle(appTheme.textFaint)
                }
                Spacer()
                Toggle("", isOn: $activityRingsEnabled)
                    .labelsHidden()
                    .tint(appTheme.accent)
                    .disabled(!HealthKitService.isAvailable)
                    .onChange(of: activityRingsEnabled) { _, enabled in
                        guard enabled else { return }
                        Task {
                            _ = await healthKit.requestAuthorization()
                            await healthKit.fetchTodaySummary()
                        }
                    }
            }

            Divider().background(appTheme.separator)

            HStack {
                Text("Hide noise from digest")
                    .font(AppTheme.sansSerif(15))
                    .foregroundStyle(
                        gradingEnabled && IntelligenceService.isAvailable ? appTheme.heading : appTheme.textFaint
                    )
                Spacer()
                Toggle("", isOn: $hideNoise)
                    .labelsHidden()
                    .tint(appTheme.accent)
                    .disabled(!gradingEnabled || !IntelligenceService.isAvailable)
            }
        }
    }

    // MARK: - Appearance (theme + night mode)

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("APPEARANCE")

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(ReaderTheme.pickerCases) { theme in
                    ThemeTile(theme: theme, isSelected: theme == selectedTheme) {
                        handleSelection(theme)
                    }
                }
            }

            Divider().background(appTheme.separator)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Night mode starts at")
                        .font(AppTheme.sansSerif(15))
                        .foregroundStyle(nightOverride == "off" ? appTheme.textFaint : appTheme.heading)
                    Text("Blue light removed to help you sleep.")
                        .font(AppTheme.sansSerif(12))
                        .foregroundStyle(appTheme.textFaint)
                }
                Spacer()
                DatePicker("", selection: nightStartBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .tint(appTheme.accent)
                    .disabled(nightOverride == "off")
                    .opacity(nightOverride == "off" ? 0.4 : 1)
            }

            Picker("", selection: $nightOverride) {
                Text("Auto").tag("auto")
                Text("On").tag("on")
                Text("Off").tag("off")
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Feeds

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

    // MARK: - Danger

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("DANGER")

            if duplicateCount > 0 {
                dangerButton("Remove \(duplicateCount) duplicate article\(duplicateCount == 1 ? "" : "s").") {
                    activeDialog = .deduplicateArticles
                }
            }
            dangerButton("Clear all articles.") { activeDialog = .clearArticles }
            dangerButton("Reset everything.") { activeDialog = .resetEverything }
            dangerButton("Clear streak.") { activeDialog = .clearStreak }
        }
    }

    // MARK: - Developer (unlocked via version tap)

    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("EDITION")

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

    // MARK: - Version footer

    private var versionFooter: some View {
        Button {
            versionTapCount += 1
            if versionTapCount >= 10 {
                developerUnlocked.toggle()
                versionTapCount = 0
            }
        } label: {
            Text("Just… \(appVersion) (\(buildNumber))")
                .font(AppTheme.sansSerif(12))
                .foregroundStyle(developerUnlocked ? appTheme.accent.opacity(0.6) : appTheme.textFaint)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bindings

    private var morningTimeBinding: Binding<Date> {
        Binding(
            get: {
                var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                c.hour = morningHour; c.minute = morningMinute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                morningHour   = c.hour   ?? NotificationScheduler.defaultMorningHour
                morningMinute = c.minute ?? NotificationScheduler.defaultMorningMinute
            }
        )
    }

    private var eveningTimeBinding: Binding<Date> {
        Binding(
            get: {
                var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                c.hour = eveningHour; c.minute = eveningMinute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                eveningHour   = c.hour   ?? NotificationScheduler.defaultEveningHour
                eveningMinute = c.minute ?? NotificationScheduler.defaultEveningMinute
            }
        )
    }

    private var nightStartBinding: Binding<Date> {
        Binding(
            get: {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                comps.hour = nightStartHour; comps.minute = nightStartMinute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                nightStartHour   = comps.hour   ?? NightModeService.defaultStartHour
                nightStartMinute = comps.minute ?? NightModeService.defaultStartMinute
            }
        )
    }

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

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.mono(11))
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

    // MARK: - Dialog title

    private var dialogTitle: String {
        switch activeDialog {
        case .clearStreak:        "Clear streak?"
        case .forceUpload:        "Upload to iCloud?"
        case .forceRestore:       "Restore from iCloud?"
        case .clearArticles:      "Clear all articles?"
        case .deduplicateArticles: "Remove duplicates?"
        case .resetEverything:    "Reset everything?"
        case nil:                 ""
        }
    }

    // MARK: - Actions

    private func performForceUpload() async {
        syncPhase = .syncing
        do {
            try context.save()
        } catch {
            syncPhase = .failure("Could not commit changes.")
            return
        }
        for _ in 0..<24 {
            try? await Task.sleep(for: .milliseconds(500))
            if case .syncing = syncPhase { continue }
            return
        }
        syncPhase = .success("iCloud is up to date.")
    }

    private func scheduleCloudRestore() {
        CloudSyncService.scheduleRestore()
        syncPhase = .success("Restore scheduled. Reopen Just… to complete.")
    }

    private func handleCloudKitEvent(_ notification: Notification) {
        guard case .syncing = syncPhase else { return }
        guard
            let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event,
            event.type == .export,
            event.endDate != nil
        else { return }
        syncPhase = event.succeeded
            ? .success("Synced. iCloud is up to date.")
            : .failure("Sync failed. Check your connection.")
    }

    private func handleSelection(_ theme: ReaderTheme) {
        guard theme != selectedTheme else { return }
        themeRaw = theme.rawValue
    }

    private func clearStreak() {
        let days = (try? context.fetch(FetchDescriptor<ReadingDay>())) ?? []
        days.forEach { context.delete($0) }
        try? context.save()
    }

    private func clearAllArticles() {
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

    private func generateEditionNow() {
        editionGenerationState = .running
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

// MARK: - Theme Tile

private struct ThemeTile: View {
    let theme: ReaderTheme
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                previewArea
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                            .stroke(
                                isSelected ? appTheme.accent : appTheme.separator,
                                lineWidth: isSelected ? 2 : 1
                            )
                    )

                HStack {
                    Text(theme.displayName)
                        .font(AppTheme.sansSerif(12))
                        .foregroundStyle(isSelected ? appTheme.heading : appTheme.textFaint)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(appTheme.accent)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 8)
            }
        }
        .buttonStyle(.plain)
    }

    private var previewArea: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .fill(theme.bg)
                .frame(height: 96)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: theme.headingHex))
                    .frame(width: 52, height: 5)
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.text.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .frame(height: 3)
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.text.opacity(0.55))
                    .frame(width: 44, height: 3)
                Spacer().frame(height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.accent)
                    .frame(width: 36, height: 3)
            }
            .padding(12)
        }
    }
}
