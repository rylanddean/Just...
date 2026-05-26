import Foundation
import SwiftUI

enum ArticleQualityGrade: String, Codable {
    case strong
    case worthIt
    case noise
}

extension ArticleQualityGrade {
    var filledCount: Int {
        switch self {
        case .strong:  return 3
        case .worthIt: return 2
        case .noise:   return 1
        }
    }

    var color: Color {
        switch self {
        case .strong:  return .green
        case .worthIt: return .yellow
        case .noise:   return .red
        }
    }

    var rationale: String {
        switch self {
        case .strong:  return "Original argument or insight that earns undivided attention. Genuinely distinctive — most articles don't qualify."
        case .worthIt: return "Informative and competently written, but not essential. Covers ground that exists elsewhere."
        case .noise:   return "Aggregated takes, listicles, press releases, promotional content, or too brief to be substantive."
        }
    }
}
