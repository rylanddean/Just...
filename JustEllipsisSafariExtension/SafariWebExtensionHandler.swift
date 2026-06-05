import SafariServices
import os.log

private let log = Logger(
    subsystem: "com.rylandean.justellipsis.mac.safari-extension",
    category: "handler"
)

// NSExtensionContext is thread-safe Obj-C; @unchecked Sendable delegates that contract to the caller.
private struct ExtCtx: @unchecked Sendable {
    let ctx: NSExtensionContext
}

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        guard
            let item = context.inputItems.first as? NSExtensionItem,
            let userInfo = item.userInfo as? [String: Any],
            let message = userInfo[SFExtensionMessageKey] as? [String: Any],
            let action = message["action"] as? String
        else {
            context.completeRequest(returningItems: [], completionHandler: nil)
            return
        }

        switch action {
        case "save":
            let url   = message["url"]   as? String ?? ""
            let title = message["title"] as? String
            Self.runSave(url: url, title: title, box: ExtCtx(ctx: context))

        case "check":
            let url = message["url"] as? String ?? ""
            Self.runCheck(url: url, box: ExtCtx(ctx: context))

        default:
            context.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    // Static helpers keep Task closures free of non-Sendable captures,
    // which lets Swift 6's region-based isolation checker reason about them.
    private static func runSave(url: String, title: String?, box: ExtCtx) {
        Task.detached {
            let result = await CloudKitLinkWriter.save(url: url, title: title)
            log.debug("save result: \(result)")
            complete(result, box: box)
        }
    }

    private static func runCheck(url: String, box: ExtCtx) {
        Task.detached {
            let isDupe = await CloudKitLinkWriter.isDuplicate(url: url)
            complete(isDupe ? "duplicate" : "clear", box: box)
        }
    }

    private static func complete(_ result: String, box: ExtCtx) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["result": result]]
        box.ctx.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
