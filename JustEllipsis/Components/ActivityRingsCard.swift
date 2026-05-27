import SwiftUI

// MARK: - Card

struct ActivityRingsCard: View {
    let summary: HealthKitService.ActivitySummaryData
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Reading goal met. How's the body doing?")
                    .font(AppTheme.sansSerif(14, weight: .medium))
                    .foregroundStyle(appTheme.heading)
                Text("Your activity rings for today.")
                    .font(AppTheme.sansSerif(12))
                    .foregroundStyle(appTheme.textFaint)
            }

            HStack(spacing: 20) {
                ActivityRingsView(
                    moveProgress:     min(summary.moveProgress, 1),
                    exerciseProgress: min(summary.exerciseProgress, 1),
                    standProgress:    min(summary.standProgress, 1)
                )

                VStack(alignment: .leading, spacing: 10) {
                    ringRow(
                        label: "MOVE",
                        value: "\(Int(summary.moveCalories)) / \(Int(summary.moveGoal)) cal",
                        color: .activityMove
                    )
                    ringRow(
                        label: "EXERCISE",
                        value: "\(Int(summary.exerciseMins)) / \(Int(summary.exerciseGoal)) min",
                        color: .activityExercise
                    )
                    ringRow(
                        label: "STAND",
                        value: "\(Int(summary.standHours)) / \(Int(summary.standGoal)) hrs",
                        color: .activityStand
                    )
                }

                Spacer(minLength: 0)
            }
        }
        .padding(AppTheme.cardPadding)
        .background(appTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private func ringRow(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(AppTheme.sansSerif(10, weight: .medium))
                .foregroundStyle(color)
                .tracking(1.5)
            Spacer(minLength: 8)
            Text(value)
                .font(AppTheme.sansSerif(12))
                .foregroundStyle(color.opacity(0.7))
                .monospacedDigit()
        }
    }
}

// MARK: - Rings

private struct ActivityRingsView: View {
    let moveProgress:     Double
    let exerciseProgress: Double
    let standProgress:    Double

    private let outerSize: CGFloat = 76
    private let ringWidth: CGFloat = 8
    private let ringGap:   CGFloat = 3

    private var midSize:   CGFloat { outerSize - (ringWidth + ringGap) * 2 }
    private var innerSize: CGFloat { midSize   - (ringWidth + ringGap) * 2 }

    var body: some View {
        ZStack {
            ring(progress: moveProgress,     color: .activityMove,     size: outerSize)
            ring(progress: exerciseProgress, color: .activityExercise, size: midSize)
            ring(progress: standProgress,    color: .activityStand,    size: innerSize)
        }
        .frame(width: outerSize, height: outerSize)
    }

    private func ring(progress: Double, color: Color, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: ringWidth)
                .frame(width: size, height: size)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Colour tokens

private extension Color {
    // Standard Apple Activity ring colours
    static let activityMove     = Color(red: 1.00, green: 0.22, blue: 0.37)  // #FF375F
    static let activityExercise = Color(red: 0.19, green: 0.82, blue: 0.35)  // #30D158
    static let activityStand    = Color(red: 0.20, green: 0.68, blue: 0.90)  // #32ADE6
}
