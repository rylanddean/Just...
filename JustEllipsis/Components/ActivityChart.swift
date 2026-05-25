import SwiftUI

struct ActivityChart: View {
    let days: [Bool]   // oldest-first; last element = today

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, isRead in
                let isToday = index == days.count - 1
                RoundedRectangle(cornerRadius: 3)
                    .fill(isRead ? appTheme.accent : appTheme.separator)
                    .overlay {
                        if isToday && !isRead {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(appTheme.accent.opacity(0.5), lineWidth: 1.5)
                        }
                    }
                    .frame(width: 10, height: 10)
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ActivityChart(days: [true, true, true, true, true, true, true])
        ActivityChart(days: [false, true, false, true, true, false, false])
        ActivityChart(days: [false, false, false, false, false, false, false])
        ActivityChart(days: [false, false, false, false, false, false, true])
    }
    .padding()
    .background(AppTheme().background)
}
