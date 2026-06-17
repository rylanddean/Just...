import Foundation
import SwiftData
import CloudKit
import os.log

private let receiverLog = Logger(
    subsystem: "com.rylandean.justellipsis",
    category: "MacLinkReceiver"
)

// Promotes JE_PendingLink records written by the Mac Safari extension into
// the local SwiftData store. Called on every foreground — no-op when there
// are no pending records. Deletes the CloudKit records after promotion so
// each link is processed exactly once.
@MainActor
final class MacLinkReceiver {

    private static let containerID = "iCloud.com.rylandean.justellipsis"
    nonisolated static let recordType = "JE_PendingLink"

    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func checkAndPromote() {
        Task { await promote() }
    }

    func checkAndPromoteAsync() async {
        await promote()
    }

    // MARK: - Promotion

    private func promote() async {
        receiverLog.info("promote: checking for pending Mac links")

        let container = CKContainer(identifier: Self.containerID)
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                receiverLog.error("promote: CloudKit account status = \(String(describing: status))")
                return
            }
        } catch {
            receiverLog.error("promote: accountStatus error: \(error)")
            return
        }

        let db = container.privateCloudDatabase
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))

        let results: [(CKRecord.ID, Result<CKRecord, Error>)]
        do {
            (results, _) = try await db.records(matching: query)
        } catch {
            receiverLog.error("promote: query failed: \(error)")
            return
        }

        receiverLog.info("promote: found \(results.count) pending record(s)")
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

        do {
            try ctx.save()
            receiverLog.info("promote: inserted \(toDelete.count) link(s) into SwiftData")
        } catch {
            receiverLog.error("promote: SwiftData save failed: \(error)")
        }

        guard !toDelete.isEmpty else { return }
        let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: toDelete)
        op.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                receiverLog.info("promote: deleted \(toDelete.count) CloudKit record(s)")
            case .failure(let error):
                receiverLog.error("promote: CloudKit delete failed: \(error)")
            }
        }
        db.add(op)
    }
}
