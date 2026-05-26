import Foundation

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
}
