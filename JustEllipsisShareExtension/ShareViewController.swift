import UIKit
import UniformTypeIdentifiers
import MobileCoreServices

final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.047, green: 0.039, blue: 0.031, alpha: 1)
        extractAndSave()
    }

    // MARK: - Extraction

    private func extractAndSave() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments
        else {
            complete()
            return
        }

        // Try public.url first (most apps, Safari on iOS 16+)
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                let url = (item as? URL) ?? (item as? NSURL as URL?)
                if let url, url.scheme?.hasPrefix("http") == true {
                    AddLinkIntent.addLink(url: url)
                    self?.complete()
                    return
                }
                // Value came back as a string (some apps do this)
                if let str = item as? String, let url = URL(string: str), url.scheme?.hasPrefix("http") == true {
                    AddLinkIntent.addLink(url: url)
                }
                self?.complete()
            }
            return
        }

        // Fallback: plain-text that looks like a URL
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, _ in
                if let str = item as? String,
                   let url = URL(string: str.trimmingCharacters(in: .whitespacesAndNewlines)),
                   url.scheme?.hasPrefix("http") == true {
                    AddLinkIntent.addLink(url: url)
                }
                self?.complete()
            }
            return
        }

        complete()
    }

    // MARK: - Completion

    private func complete() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
