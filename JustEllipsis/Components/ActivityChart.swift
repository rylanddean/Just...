import SwiftUI

struct ActivityChart: View {
    let days: [Bool]   // oldest-first; last element = today

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, isRead in
                let isToday = index == days.count - 1
                RoundedRectangle(cornerRadius: 3)
                    .fill(isRead ? AppTheme.readerAccent : AppTheme.separator)
                    .overlay {
                        if isToday && !isRead {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(AppTheme.readerAccent.opacity(0.5), lineWidth: 1.5)
                        }
                    }
                    .frame(width: 10, height: 10)
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        // Full week
        ActivityChart(days: [true, true, true, true, true, true, true])
        // Patchy week, today unread (at-risk hollow ring)
        ActivityChart(days: [false, true, false, true, true, false, false])
        // No activity
        ActivityChart(days: [false, false, false, false, false, false, false])
        // Today read
        ActivityChart(days: [false, false, false, false, false, false, true])
    }
    .padding()
    .background(AppTheme.background)
}
