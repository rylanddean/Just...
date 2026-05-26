import SwiftUI

struct BrainOrb: View {
    let rank: BrainRank
    let entryCount: Int
    let progress: Double

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(appTheme.separator, lineWidth: 2)
                    .frame(width: 56, height: 56)

                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(
                        orbColor,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: clampedProgress)

                Text("\(entryCount)")
                    .font(AppTheme.sansSerif(15, weight: .semibold))
                    .foregroundStyle(appTheme.heading)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text("CURRENT RANK")
                        .font(AppTheme.sansSerif(10, weight: .medium))
                        .foregroundStyle(appTheme.textFaint)
                        .kerning(1.6)
                    Text(rank.rawValue.uppercased())
                        .font(AppTheme.sansSerif(10, weight: .medium))
                        .foregroundStyle(orbColor)
                        .kerning(1.2)
                }

                HStack(spacing: 8) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(appTheme.separator)
                            Capsule()
                                .fill(orbColor)
                                .frame(width: max(6, proxy.size.width * clampedProgress))
                        }
                    }
                    .frame(height: 6)

                    Text("\(Int(clampedProgress * 100))%")
                        .font(AppTheme.sansSerif(11, weight: .medium))
                        .foregroundStyle(appTheme.textFaint)
                        .monospacedDigit()
                }

                Text(entryCount == 1 ? "1 entry logged" : "\(entryCount) entries logged")
                    .font(AppTheme.sansSerif(12))
                    .foregroundStyle(appTheme.textFaint)
            }
        }
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
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
