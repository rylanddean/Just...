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
}
