@preconcurrency import HealthKit
import Observation

@Observable
@MainActor
final class HealthKitService {

    struct ActivitySummaryData: Sendable {
        let moveCalories:  Double
        let moveGoal:      Double
        let exerciseMins:  Double
        let exerciseGoal:  Double
        let standHours:    Double
        let standGoal:     Double

        var moveProgress:     Double { moveGoal     > 0 ? moveCalories / moveGoal     : 0 }
        var exerciseProgress: Double { exerciseGoal > 0 ? exerciseMins / exerciseGoal : 0 }
        var standProgress:    Double { standGoal    > 0 ? standHours   / standGoal    : 0 }
    }

    var summary: ActivitySummaryData? = nil

    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Presents the system authorization sheet for activity summary read access.
    /// Returns true if the sheet appeared without error; HealthKit does not report
    /// whether the user allowed or denied, so we use graceful degradation.
    func requestAuthorization() async -> Bool {
        guard Self.isAvailable else { return false }
        do {
            try await store.requestAuthorization(
                toShare: [],
                read: [HKObjectType.activitySummaryType()]
            )
            return true
        } catch {
            return false
        }
    }

    func fetchTodaySummary() async {
        guard Self.isAvailable else { return }
        let comps     = Calendar.current.dateComponents([.calendar, .year, .month, .day], from: Date())
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: comps, end: comps)
        let store     = store  // local capture avoids @MainActor crossing in callback

        summary = await withCheckedContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                guard let s = summaries?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: ActivitySummaryData(
                    moveCalories: s.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                    moveGoal:     s.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                    exerciseMins: s.appleExerciseTime.doubleValue(for: .minute()),
                    exerciseGoal: s.appleExerciseTimeGoal.doubleValue(for: .minute()),
                    standHours:   s.appleStandHours.doubleValue(for: .count()),
                    standGoal:    s.appleStandHoursGoal.doubleValue(for: .count())
                ))
            }
            store.execute(query)
        }
    }
}
