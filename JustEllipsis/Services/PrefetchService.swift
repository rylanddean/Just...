import Foundation
import SwiftData
import BackgroundTasks

// MARK: - Result (Sendable — crosses actor boundaries)

enum PrefetchResult: Sendable {
    case ready(rawHTML: String, title: String, domain: String)
    case invalid
    case transientFailure
}

// MARK: - Service

struct PrefetchService {

    static let backgroundTaskID = "com.rylandean.justellipsis.prefetch"

    // MARK: - In-process (called on foreground from @MainActor context)

    @MainActor
    static func prefetchInProcess(container: ModelContainer) {
        Task.detached(priority: .background) {
            let actor = PrefetchActor(modelContainer: container)
            await actor.prefetch(max: 2)
        }
    }

    // MARK: - BGAppRefreshTask scheduling

    static func scheduleNextBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Validation (nonisolated — runs on cooperative pool during await)

    static func validate(urlString: String) async -> PrefetchResult {
        guard let url = URL(string: urlString) else { return .invalid }

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 12
        let session = URLSession(configuration: config)

        do {
            var request = URLRequest(url: url)
            request.setValue(ContentFetcher.safariUserAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else { return .transientFailure }
            guard http.statusCode < 400 else { return .invalid }

            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
            guard contentType.lowercased().contains("text/html") else { return .invalid }

            let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            let stripped = try ContentFetcher.strip(html: html, sourceURL: url)
            guard stripped.estimatedWordCount >= 50 else { return .invalid }

            return .ready(rawHTML: html, title: stripped.title, domain: stripped.domain)

        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .timedOut, .networkConnectionLost,
                 .cannotConnectToHost, .cannotFindHost:
                return .transientFailure
            default:
                return .invalid
            }
        } catch {
            return .transientFailure
        }
    }
}

// MARK: - ModelActor (dedicated background SwiftData context)

@ModelActor
actor PrefetchActor {

    func prefetch(max: Int) async {
        let pending = PrefetchState.pending.rawValue
        let retrying = PrefetchState.retrying.rawValue

        let descriptor = FetchDescriptor<QueuedLink>(
            predicate: #Predicate {
                $0.prefetchStateRaw == pending || $0.prefetchStateRaw == retrying
            }
        )
        guard let links = try? modelContext.fetch(descriptor) else { return }

        for link in links.prefix(max) {
            let result = await PrefetchService.validate(urlString: link.url)
            apply(result, to: link)
        }

        try? modelContext.save()
    }

    private func apply(_ result: PrefetchResult, to link: QueuedLink) {
        switch result {
        case .ready(let rawHTML, let title, let domain):
            link.cachedHTML = rawHTML
            link.prefetchStateRaw = PrefetchState.ready.rawValue
            if link.title == nil || link.title!.isEmpty { link.title = title }
            if link.domain == nil || link.domain!.isEmpty { link.domain = domain }
        case .invalid:
            link.prefetchStateRaw = PrefetchState.invalid.rawValue
        case .transientFailure:
            link.prefetchStateRaw = PrefetchState.retrying.rawValue
        }
    }
}
