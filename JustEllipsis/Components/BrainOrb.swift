import SwiftUI

struct BrainOrb: View {
    let rank: BrainRank
    let entryCount: Int
    let progress: Double    // 0.0–1.0

    @Environment(\.appTheme) private var appTheme
    @State private var pulse: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [orbColor.opacity(0.25), .clear],
                            center: .center,
                            startRadius: 30,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .scaleEffect(pulse ? 1.08 : 1.0)
                    .animation(
                        .easeInOut(duration: 3).repeatForever(autoreverses: true),
                        value: pulse
                    )

                // Progress ring
                Circle()
                    .stroke(appTheme.separator, lineWidth: 2)
                    .frame(width: 108, height: 108)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        orbColor,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 108, height: 108)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: progress)

                // Core orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [orbColor.opacity(0.3), orbColor.opacity(0.08)],
                            center: .center,
                            startRadius: 10,
                            endRadius: 48
                        )
                    )
                    .frame(width: 96, height: 96)
                    .overlay {
                        Circle().stroke(orbColor.opacity(0.35), lineWidth: 1)
                    }

                // Entry count
                VStack(spacing: 2) {
                    Text("\(entryCount)")
                        .font(AppTheme.sansSerif(28, weight: .semibold))
                        .foregroundStyle(appTheme.heading)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text(entryCount == 1 ? "entry" : "entries")
                        .font(AppTheme.sansSerif(10))
                        .foregroundStyle(appTheme.textFaint)
                }
            }

            // Rank title
            Text(rank.rawValue)
                .font(AppTheme.sansSerif(18, weight: .semibold))
                .foregroundStyle(orbColor)
                .tracking(1.5)
                .textCase(.uppercase)
        }
        .onAppear { pulse = true }
    }

    private var orbColor: Color {
        switch rank {
        case .curious:  return Color(hex: "#7EB8C9")
        case .reader:   return Color(hex: "#78B87A")
        case .thinker:  return Color.white
        case .scholar:  return Color(hex: "#C49A6C")
        case .polymath: return Color(hex: "#D4ADDB")
        case .luminary: return Color(hex: "#F5ECD7")
        }
    }
}

#Preview {
    ZStack {
        AppTheme().background.ignoresSafeArea()
        BrainOrb(rank: .thinker, entryCount: 142, progress: 0.42)
    }
}
