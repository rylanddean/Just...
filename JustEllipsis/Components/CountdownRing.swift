import SwiftUI

struct CountdownRing: View {
    let total: Int
    let remaining: Int

    @Environment(\.appTheme) private var appTheme

    private var isDone: Bool { remaining == 0 }

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(remaining) / Double(total)
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(appTheme.separator, lineWidth: 3)

            // Active arc — full amber when done, draining while counting
            Circle()
                .trim(from: 0, to: isDone ? 1 : fraction)
                .stroke(
                    appTheme.accent,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: remaining)

            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(appTheme.accent)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("\(remaining)")
                    .font(AppTheme.sansSerif(16, weight: .medium))
                    .foregroundStyle(fraction < 0.2 ? AppTheme.danger : appTheme.textFaint)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .frame(width: 52, height: 52)
        .animation(.easeInOut(duration: 0.3), value: isDone)
    }
}

#Preview {
    HStack(spacing: 24) {
        CountdownRing(total: 60, remaining: 60)
        CountdownRing(total: 60, remaining: 30)
        CountdownRing(total: 60, remaining: 8)
        CountdownRing(total: 60, remaining: 0)
    }
    .padding()
    .background(AppTheme().background)
}
