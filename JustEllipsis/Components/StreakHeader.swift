import SwiftUI

struct StreakHeader: View {
    let streak: Int
    let isAtRisk: Bool
    let recentActivity: [Bool]

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(streak > 0 ? "\(streak)" : "—")
                .font(AppTheme.sansSerif(42, weight: .semibold))
                .foregroundStyle(isAtRisk && streak > 0 ? AppTheme.danger : appTheme.heading)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.4), value: streak)

            VStack(alignment: .leading, spacing: 2) {
                Text("day streak")
                    .font(AppTheme.sansSerif(13))
                    .foregroundStyle(appTheme.textFaint)

                if isAtRisk && streak > 0 {
                    Text("read today to keep it")
                        .font(AppTheme.sansSerif(11))
                        .foregroundStyle(AppTheme.danger.opacity(0.8))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isAtRisk)

            Spacer()

            ActivityChart(days: recentActivity)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

#Preview {
    VStack {
        StreakHeader(streak: 14, isAtRisk: false,
                    recentActivity: [true, true, true, true, true, true, true])
        StreakHeader(streak: 7, isAtRisk: true,
                    recentActivity: [false, true, true, false, true, true, false])
        StreakHeader(streak: 0, isAtRisk: false,
                    recentActivity: [false, false, false, false, false, false, false])
    }
    .background(AppTheme().background)
}
