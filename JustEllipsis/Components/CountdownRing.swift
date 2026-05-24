import SwiftUI

struct CountdownRing: View {
    let total: Int
    let remaining: Int
    let isPaused: Bool

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(remaining) / Double(total)
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(AppTheme.separator, lineWidth: 3)

            // Active arc
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    isPaused ? AppTheme.readerAccent.opacity(0.4) : AppTheme.readerAccent,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: remaining)

            // Seconds label
            Text(isPaused ? "…" : "\(remaining)")
                .font(AppTheme.sansSerif(16, weight: .medium))
                .foregroundStyle(fraction < 0.2 ? AppTheme.danger : AppTheme.textFaint)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: isPaused)
        }
        .frame(width: 52, height: 52)
    }
}

#Preview {
    HStack(spacing: 24) {
        CountdownRing(total: 60, remaining: 60, isPaused: false)
        CountdownRing(total: 60, remaining: 30, isPaused: false)
        CountdownRing(total: 60, remaining: 8, isPaused: false)
        CountdownRing(total: 60, remaining: 30, isPaused: true)
    }
    .padding()
    .background(AppTheme.background)
}
