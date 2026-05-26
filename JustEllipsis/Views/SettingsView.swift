import SwiftUI
import SwiftData
import CoreData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.appTheme) private var appTheme
    @Environment(GradingProgressTracker.self) private var gradingTracker
    @AppStorage(ReaderTheme.defaultsKey) private var themeRaw: String = "ember"
    @AppStorage("streak.minReadsPerDay") private var minReadsPerDay: Int = 1
    @AppStorage(JustEllipsisApp.iCloudSyncKey) private var iCloudSyncEnabled: Bool = false
    @AppStorage("rss.fetchHour")   private var fetchHour:   Int = RSSFetchService.defaultFetchHour
    @AppStorage("rss.fetchMinute") private var fetchMinute: Int = RSSFetchService.defaultFetchMinute
    @AppStorage("grading.enabled") private var gradingEnabled: Bool = false
    @AppStorage("digest.hideNoise") private var hideNoise: Bool = false

    // MARK: - Dialog state

    private enum DialogKind: Identifiable {
        case clearStreak, resetEverything, forceUpload, forceRestore
        var id: Self { self }
    }

    private enum SyncPhase {
        case idle, syncing, success(String), failure(String)
    }

    @State private var versionTapCount = 0
    @State private var activeDialog: DialogKind? = nil
    @State private var syncPhase: SyncPhase = .idle

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

    var body: some View {
        NavigationStack {
            ZStack {
                appTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        syncSection
                        streakSection
                        feedsSection
                        readingSection
                        themeSection
                        dangerSection
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
            case .resetEverything:
                Button("Reset everything", role: .destructive) { resetEverything() }
                Button("Cancel", role: .cancel) { }
            case .forceUpload:
                Button("Upload") { Task { await performForceUpload() } }
                Button("Cancel", role: .cancel) { }
            case .forceRestore:
                Button("Restore", role: .destructive) { scheduleCloudRestore() }
                Button("Cancel", role: .cancel) { }
            }
        } message: { dialog in
            switch dialog {
            case .clearStreak:
                Text("Your reading streak and daily history will be deleted.")
            case .resetEverything:
                Text("Your queue, Brain, streak, and feeds will be deleted. This cannot be undone.")
            case .forceUpload:
                Text("Your local data will be pushed to iCloud. Any differences on other devices will be resolved on their next sync.")
            case .forceRestore:
                Text("Local data will be cleared and replaced from iCloud the next time you open Just….")
            }
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SYNC")
                .font(AppTheme.sansSerif(11, weight: .medium))
                .foregroundStyle(appTheme.textFaint)
                .tracking(2)

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

    // MARK: - Streak Section

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("STREAK")
                .font(AppTheme.sansSerif(11, weight: .medium))
                .foregroundStyle(appTheme.textFaint)
                .tracking(2)

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

    // MARK: - Feeds Section

    /// A Date binding that maps hour/minute AppStorage ints to/from a Date for DatePicker.
    private var fetchTimeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                comps.hour   = fetchHour
                comps.minute = fetchMinute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { date in
                let comps  = Calendar.current.dateComponents([.hour, .minute], from: date)
                fetchHour   = comps.hour   ?? RSSFetchService.defaultFetchHour
                fetchMinute = comps.minute ?? RSSFetchService.defaultFetchMinute
                RSSFetchService.scheduleNextBackgroundTask()
            }
        )
    }

    private var feedsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FEEDS")
                .font(AppTheme.sansSerif(11, weight: .medium))
                .foregroundStyle(appTheme.textFaint)
                .tracking(2)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Daily fetch")
                        .font(AppTheme.sansSerif(15))
                        .foregroundStyle(appTheme.heading)
                    Text("When background refresh runs.")
                        .font(AppTheme.sansSerif(12))
                        .foregroundStyle(appTheme.textFaint)
                }

                Spacer()

                DatePicker("", selection: fetchTimeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .tint(appTheme.accent)
            }
        }
    }

    // MARK: - Reading Section

    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("READING")
                .font(AppTheme.sansSerif(11, weight: .medium))
                .foregroundStyle(appTheme.textFaint)
                .tracking(2)

            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Article grading")
                            .font(AppTheme.sansSerif(15))
                            .foregroundStyle(IntelligenceService.isAvailable ? appTheme.heading : appTheme.textFaint)
                        if !IntelligenceService.isAvailable {
                            Text("Requires Apple Intelligence.")
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

                HStack {
                    Text("Hide noise from digest")
                        .font(AppTheme.sansSerif(15))
                        .foregroundStyle(gradingEnabled && IntelligenceService.isAvailable ? appTheme.heading : appTheme.textFaint)
                        .padding(.leading, 16)
                    Spacer()
                    Toggle("", isOn: $hideNoise)
                        .labelsHidden()
                        .tint(appTheme.accent)
                        .disabled(!gradingEnabled || !IntelligenceService.isAvailable)
                }
            }
        }
    }

    // MARK: - Theme Section

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("APPEARANCE")
                .font(AppTheme.sansSerif(11, weight: .medium))
                .foregroundStyle(appTheme.textFaint)
                .tracking(2)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(ReaderTheme.allCases) { theme in
                    ThemeTile(theme: theme, isSelected: theme == selectedTheme) {
                        handleSelection(theme)
                    }
                }
            }

        }
    }

    // MARK: - Danger Section

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DANGER")
                .font(AppTheme.sansSerif(11, weight: .medium))
                .foregroundStyle(appTheme.textFaint)
                .tracking(2)

            Button {
                activeDialog = .resetEverything
            } label: {
                HStack {
                    Spacer()
                    Text("Reset everything.")
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
    }

    // MARK: - Version Footer

    private var versionFooter: some View {
        Button {
            versionTapCount += 1
            if versionTapCount >= 10 {
                activeDialog = .clearStreak
                versionTapCount = 0
            }
        } label: {
            Text("Just… \(appVersion) (\(buildNumber))")
                .font(AppTheme.sansSerif(12))
                .foregroundStyle(appTheme.textFaint)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var dialogTitle: String {
        switch activeDialog {
        case .clearStreak:    "Clear streak?"
        case .resetEverything: "Reset everything?"
        case .forceUpload:    "Upload to iCloud?"
        case .forceRestore:   "Restore from iCloud?"
        case nil:             ""
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
        // Poll for a CloudKit export event (delivered via handleCloudKitEvent).
        // If none fires within ~12 s, the store was already in sync.
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

        if event.succeeded {
            syncPhase = .success("Synced. iCloud is up to date.")
        } else {
            syncPhase = .failure("Sync failed. Check your connection.")
        }
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

    private func resetEverything() {
        let links = (try? context.fetch(FetchDescriptor<QueuedLink>())) ?? []
        links.forEach { context.delete($0) }
        let entries = (try? context.fetch(FetchDescriptor<BrainEntry>())) ?? []
        entries.forEach { context.delete($0) }
        let days = (try? context.fetch(FetchDescriptor<ReadingDay>())) ?? []
        days.forEach { context.delete($0) }
        let feeds = (try? context.fetch(FetchDescriptor<RSSFeed>())) ?? []
        feeds.forEach { context.delete($0) }
        let articles = (try? context.fetch(FetchDescriptor<RSSArticle>())) ?? []
        articles.forEach { context.delete($0) }
        try? context.save()
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
                // Simulated heading
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: theme.headingHex))
                    .frame(width: 52, height: 5)

                // Body line 1
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.text.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .frame(height: 3)

                // Body line 2
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.text.opacity(0.55))
                    .frame(width: 44, height: 3)

                Spacer().frame(height: 4)

                // Accent line (simulates a link)
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.accent)
                    .frame(width: 36, height: 3)
            }
            .padding(12)
        }
    }
}
