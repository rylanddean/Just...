import Foundation

struct FeedURLNormaliser {
    static func normalise(_ raw: String) -> URL? {
        var string = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !string.hasPrefix("http") { string = "https://\(string)" }
        guard var components = URLComponents(string: string) else { return nil }

        if let host = components.host, host.hasSuffix(".substack.com") {
            let path = components.path
            if path.isEmpty || path == "/" {
                components.path = "/feed"
            }
        }

        return components.url
    }
}
