import SafariServices
import os.log

private let log = Logger(
    subsystem: "com.rylandean.justellipsis.mac.safari-extension",
    category: "handler"
)

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
            Task {
                let result = await CloudKitLinkWriter.save(url: url, title: title)
                log.debug("save result: \(result)")
                reply(result, to: context)
            }

        case "check":
            let url = message["url"] as? String ?? ""
            Task {
                let isDupe = await CloudKitLinkWriter.isDuplicate(url: url)
                reply(isDupe ? "duplicate" : "clear", to: context)
            }

        default:
            context.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    private func reply(_ result: String, to context: NSExtensionContext) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["result": result]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
