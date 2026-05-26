import SwiftUI

struct ArticleGradeIndicator: View {
    let articleID: UUID
    let grade: ArticleQualityGrade?

    @Environment(GradingProgressTracker.self) private var tracker
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        if tracker.activeIDs.contains(articleID) {
            ProgressView()
                .scaleEffect(0.55)
                .tint(appTheme.textFaint)
                .frame(width: 22, height: 10)
        } else if let grade {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < grade.filledCount ? grade.color : grade.color.opacity(0.25))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }
}
