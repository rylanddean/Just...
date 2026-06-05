import CloudKit
import Foundation

enum CloudKitLinkWriter {

    private static let containerID = "iCloud.com.rylandean.justellipsis"
    static let recordType = "JE_PendingLink"

    // Returns "success", "duplicate", or "error".
    static func save(url: String, title: String?) async -> String {
        guard
            !url.isEmpty,
            let parsed = URL(string: url),
            parsed.scheme == "https" || parsed.scheme == "http"
        else { return "error" }

        let db = CKContainer(identifier: containerID).privateCloudDatabase

        if await isDuplicate(url: url, db: db) { return "duplicate" }

        let record = CKRecord(recordType: recordType)
        record["url"]     = url as CKRecordValue
        record["addedAt"] = Date() as CKRecordValue
        if let t = title, !t.isEmpty { record["title"] = t as CKRecordValue }
        if let host = parsed.host {
            let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            record["domain"] = domain as CKRecordValue
        }

        do {
            try await db.save(record)
            return "success"
        } catch {
            return "error"
        }
    }

    static func isDuplicate(url: String) async -> Bool {
        let db = CKContainer(identifier: containerID).privateCloudDatabase
        return await isDuplicate(url: url, db: db)
    }

    // Shared helper — reuses an already-opened db reference so callers can
    // avoid constructing a second container instance in save().
    private static func isDuplicate(url: String, db: CKDatabase) async -> Bool {
        let pred  = NSPredicate(format: "url == %@", url)
        let query = CKQuery(recordType: recordType, predicate: pred)
        guard let (results, _) = try? await db.records(matching: query, desiredKeys: ["url"]) else {
            return false
        }
        return !results.isEmpty
    }
}
