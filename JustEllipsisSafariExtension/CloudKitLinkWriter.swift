import CloudKit
import Foundation
import os.log

private let ckLog = Logger(
    subsystem: "com.rylandean.justellipsis.mac.safari-extension",
    category: "cloudkit"
)

enum CloudKitLinkWriter {

    private static let containerID = "iCloud.com.rylandean.justellipsis"
    static let recordType = "JE_PendingLink"

    // Returns "success", "duplicate", or "error".
    static func save(url: String, title: String?) async -> String {
        guard
            !url.isEmpty,
            let parsed = URL(string: url),
            parsed.scheme == "https" || parsed.scheme == "http"
        else {
            ckLog.error("save: invalid URL '\(url)'")
            return "error"
        }

        // Quick iCloud availability check — surfaced as a clear log line.
        guard FileManager.default.ubiquityIdentityToken != nil else {
            ckLog.error("save: iCloud not available (not signed in?)")
            return "error"
        }

        let container = CKContainer(identifier: containerID)
        let db = container.privateCloudDatabase

        // Verify container access before trying to write.
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                ckLog.error("save: CloudKit account status = \(String(describing: status))")
                return "error"
            }
        } catch {
            ckLog.error("save: accountStatus error: \(error)")
            return "error"
        }

        if await isDuplicate(url: url, db: db) {
            ckLog.info("save: duplicate — '\(url)'")
            return "duplicate"
        }

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
            ckLog.info("save: success — '\(url)'")
            return "success"
        } catch {
            ckLog.error("save: CKDatabase.save failed: \(error)")
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
        do {
            let (results, _) = try await db.records(matching: query, desiredKeys: ["url"])
            return !results.isEmpty
        } catch {
            ckLog.error("isDuplicate: query failed: \(error) — treating as not duplicate")
            return false
        }
    }
}
