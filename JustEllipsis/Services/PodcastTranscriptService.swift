import Foundation

struct PodcastTranscriptService: Sendable {

    // Fetch raw transcript bytes and decode to a string.
    static func fetch(url: URL, format: TranscriptFormat) async -> String? {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        guard let (data, _) = try? await URLSession(configuration: config).data(from: url) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    // Remove timing metadata, cue numbers, and speaker labels; return clean prose lines.
    static func strip(rawTranscript: String, format: TranscriptFormat) -> String {
        switch format {
        case .vtt, .srt: return stripTimedText(rawTranscript)
        case .html:       return stripHTMLTranscript(rawTranscript)
        case .json:       return stripJSONTranscript(rawTranscript)
        }
    }

    // MARK: - Private

    private static func stripTimedText(_ raw: String) -> String {
        let lines = raw.components(separatedBy: .newlines)
        var output: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip WEBVTT header and NOTE/STYLE blocks
            if trimmed.hasPrefix("WEBVTT") || trimmed.hasPrefix("NOTE") || trimmed.hasPrefix("STYLE") { continue }

            // Skip timestamp lines (contain "-->")
            if trimmed.contains("-->") { continue }

            // Skip bare cue numbers (SRT index lines)
            if trimmed.allSatisfy({ $0.isNumber }) { continue }

            // Skip VTT positioning tags like "align:start position:0%"
            if trimmed.contains("align:") || trimmed.contains("position:") { continue }

            // Strip inline VTT tags: <00:00:01.000>, <v Speaker>, </v>, <c>, etc.
            let cleaned = trimmed
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            if !cleaned.isEmpty {
                output.append(cleaned)
            }
        }

        // Collapse runs of identical adjacent lines (duplicate caption frames)
        var deduped: [String] = []
        for line in output {
            if deduped.last != line { deduped.append(line) }
        }

        return deduped.joined(separator: " ")
    }

    private static func stripHTMLTranscript(_ raw: String) -> String {
        raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+",   with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripJSONTranscript(_ raw: String) -> String {
        // Most Whisper-output JSON has a "text" key at the root or in "segments[].text"
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // Fall back to naive text extraction
            return raw
                .replacingOccurrences(of: "\"", with: " ")
                .replacingOccurrences(of: "[{\\[\\]}:,]", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Top-level "text" key
        if let text = json["text"] as? String { return text }

        // "segments" array with "text" entries
        if let segments = json["segments"] as? [[String: Any]] {
            return segments.compactMap { $0["text"] as? String }.joined(separator: " ")
        }

        // "results.transcripts[].transcript" (AWS Transcribe)
        if let results = json["results"] as? [String: Any],
           let transcripts = results["transcripts"] as? [[String: Any]] {
            return transcripts.compactMap { $0["transcript"] as? String }.joined(separator: " ")
        }

        return ""
    }
}
