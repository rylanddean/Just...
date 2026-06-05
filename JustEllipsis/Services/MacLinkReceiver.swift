import Foundation
import SwiftData
import CloudKit

// Promotes JE_PendingLink records written by the Mac Safari extension into
// the local SwiftData store. Called on every foreground — no-op when there
// are no pending records. Deletes the CloudKit records after promotion so
// each link is processed exactly once.
@MainActor
final class MacLinkReceiver {

    private static let containerID = "iCloud.com.rylandean.justellipsis"
    static let recordType = "JE_PendingLink"

    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func checkAndPromote() {
        Task { await promote() }
    }

    // MARK: - Promotion

    private func promote() async {
        guard FileManager.default.ubiquityIdentityToken != nil else { return }

        let db = CKContainer(identifier: Self.containerID).privateCloudDatabase
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))

        guard let (results, _) = try? await db.records(matching: query) else { return }
        guard !results.isEmpty else { return }

        let ctx = ModelContext(modelContainer)
        var toDelete: [CKRecord.ID] = []

        for (_, outcome) in results {
            guard let record = try? outcome.get() else { continue }
            let url = record["url"] as? String ?? ""
            guard !url.isEmpty else {
                toDelete.append(record.recordID)
                continue
            }

            let existing = (try? ctx.fetch(FetchDescriptor<QueuedLink>(
                predicate: #Predicate { $0.url == url }
            ))) ?? []

            if existing.isEmpty {
                let all = (try? ctx.fetch(FetchDescriptor<QueuedLink>(
                    sortBy: [SortDescriptor(\QueuedLink.sortOrder, order: .reverse)]
                ))) ?? []
                let nextOrder = (all.first?.sortOrder ?? -1) + 1

                let link = QueuedLink(
                    url: url,
                    sortOrder: nextOrder,
                    title: record["title"] as? String,
                    domain: record["domain"] as? String
                )
                ctx.insert(link)
            }

            toDelete.append(record.recordID)
        }

        try? ctx.save()

        guard !toDelete.isEmpty else { return }
        let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: toDelete)
        db.add(op)
    }
}
