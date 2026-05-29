import SwiftUI

struct ActivityHeatmapView: View {
    let entries: [BrainEntry]
    @Environment(\.appTheme) private var appTheme
    @State private var cardWidth: CGFloat = 300
    @State private var cachedWeeks: [[DayData?]] = []
    @State private var cachedMaxReflections: Int = 3
    @State private var cachedEntryCount: Int = -1
    @State private var cachedDate: Int = -1      // day-of-year sentinel for midnight invalidation

    // MARK: - Layout

    private let dayAbbrevs = ["M", "T", "W", "T", "F", "S", "S"]
    private let labelWidth: CGFloat = 10
    private let labelGap: CGFloat = 4
    private let gap: CGFloat = 3
    private let minCellSize: CGFloat = 16
    private let maxWeeks: Int = 16

    private var numWeeks: Int {
        let available = cardWidth - labelWidth - labelGap
        return min(maxWeeks, max(5, Int(available / (minCellSize + gap))))
    }

    private var cellSize: CGFloat {
        let available = cardWidth - labelWidth - labelGap
        let n = numWeeks
        return (available - CGFloat(n - 1) * gap) / CGFloat(n)
    }

    // MARK: - Data

    private struct DayData {
        let date: Date
        let reflections: Int
        let reads: Int
        let isFuture: Bool
    }

    // MARK: - Colors

    private func cellColor(for day: DayData?) -> Color {
        guard let day else { return .clear }
        guard !day.isFuture else { return .clear }
        guard day.reflections > 0 else {
            return day.reads > 0 ? appTheme.accent.opacity(0.1) : appTheme.separator.opacity(0.3)
        }
        let ratio = Double(day.reflections) / Double(cachedMaxReflections)
        return appTheme.accent.opacity(0.3 + min(ratio, 1.0) * 0.7)
    }

    // MARK: - Build

    private func buildWeeks() -> (weeks: [[DayData?]], maxReflections: Int) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let weekdayToday = cal.component(.weekday, from: today)
        let daysFromMon = weekdayToday == 1 ? 6 : weekdayToday - 2
        guard let thisMonday = cal.date(byAdding: .day, value: -daysFromMon, to: today),
              let weekStart = cal.date(byAdding: .weekOfYear, value: -(numWeeks - 1), to: thisMonday)
        else { return ([], 3) }

        // Build lookup in a single pass over entries.
        var lookup: [Date: (reflections: Int, reads: Int)] = [:]
        for entry in entries {
            let day = cal.startOfDay(for: entry.readAt)
            let hasReflection = !(entry.reflection ?? "").isEmpty
            var (r, rd) = lookup[day] ?? (0, 0)
            rd += 1
            if hasReflection { r += 1 }
            lookup[day] = (r, rd)
        }

        var maxR = 3
        let weeks: [[DayData?]] = (0..<numWeeks).map { w in
            (0..<7).map { d -> DayData? in
                guard let date = cal.date(byAdding: .day, value: w * 7 + d, to: weekStart) else { return nil }
                let isFuture = date > today
                let (r, rd) = lookup[date] ?? (0, 0)
                if r > maxR { maxR = r }
                return DayData(date: date, reflections: r, reads: rd, isFuture: isFuture)
            }
        }

        return (weeks, maxR)
    }

    private func refreshCacheIfNeeded() {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        guard cachedEntryCount != entries.count || cachedDate != dayOfYear else { return }
        cachedEntryCount = entries.count
        cachedDate = dayOfYear
        let result = buildWeeks()
        cachedWeeks = result.weeks
        cachedMaxReflections = result.maxReflections
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let cs = cellSize
            let computedWeeks = cachedWeeks

            HStack(alignment: .top, spacing: labelGap) {
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(i % 2 == 0 ? dayAbbrevs[i] : "")
                            .font(.system(size: 8))
                            .foregroundStyle(appTheme.textFaint)
                            .frame(width: labelWidth, height: cs, alignment: .leading)
                    }
                }

                HStack(alignment: .top, spacing: gap) {
                    ForEach(0..<computedWeeks.count, id: \.self) { col in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { row in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(cellColor(for: computedWeeks[col][row]))
                                    .frame(width: cs, height: cs)
                            }
                        }
                    }
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: HeatmapWidthKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(HeatmapWidthKey.self) { newWidth in
                if abs(newWidth - cardWidth) > 1 {
                    cardWidth = newWidth
                    let result = buildWeeks()
                    cachedWeeks = result.weeks
                    cachedMaxReflections = result.maxReflections
                }
            }

            HStack(spacing: 4) {
                Text("Less")
                    .font(.system(size: 9))
                    .foregroundStyle(appTheme.textFaint)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(legendColor(level: level))
                        .frame(width: 10, height: 10)
                }
                Text("More")
                    .font(.system(size: 9))
                    .foregroundStyle(appTheme.textFaint)
            }
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .onAppear { refreshCacheIfNeeded() }
        .onChange(of: entries.count) { _, _ in refreshCacheIfNeeded() }
    }

    private func legendColor(level: Int) -> Color {
        guard level > 0 else { return appTheme.separator.opacity(0.35) }
        return appTheme.accent.opacity(0.3 + Double(level) / 4.0 * 0.7)
    }
}

private struct HeatmapWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 300
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
