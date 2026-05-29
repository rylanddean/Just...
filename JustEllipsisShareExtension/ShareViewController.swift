import UIKit
import SwiftUI
import UniformTypeIdentifiers
import MobileCoreServices

final class ShareViewController: UIViewController {

    private var hasCompleted = false

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
            showFeedback(state: .error(reason: nil))
            return
        }

        // Try public.url first (most apps, Safari on iOS 16+)
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, _ in
                var resolved: URL?
                if let u = (item as? URL) ?? (item as? NSURL as URL?), u.scheme?.hasPrefix("http") == true {
                    resolved = u
                } else if let str = item as? String,
                          let u = URL(string: str),
                          u.scheme?.hasPrefix("http") == true {
                    resolved = u
                }
                if let url = resolved {
                    let state = Self.feedbackState(for: AddLinkIntent.addLink(url: url), url: url)
                    DispatchQueue.main.async { self?.showFeedback(state: state) }
                } else {
                    DispatchQueue.main.async { self?.showFeedback(state: .error(reason: "No URL found in this share.")) }
                }
            }
            return
        }

        // Fallback: plain-text that looks like a URL
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, _ in
                if let str = item as? String,
                   let url = URL(string: str.trimmingCharacters(in: .whitespacesAndNewlines)),
                   url.scheme?.hasPrefix("http") == true {
                    let state = Self.feedbackState(for: AddLinkIntent.addLink(url: url), url: url)
                    DispatchQueue.main.async { self?.showFeedback(state: state) }
                } else {
                    DispatchQueue.main.async { self?.showFeedback(state: .error(reason: "No URL found in this share.")) }
                }
            }
            return
        }

        showFeedback(state: .error(reason: "No URL found in this share."))
    }

    // MARK: - Feedback

    private func showFeedback(state: ShareFeedbackState) {
        let host = UIHostingController(rootView: ShareFeedbackView(state: state) { [weak self] in
            self?.complete()
        })
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)

        DispatchQueue.main.asyncAfter(deadline: .now() + state.autoDismissDelay) { [weak self] in
            self?.complete()
        }
    }

    // MARK: - Completion

    private func complete() {
        guard !hasCompleted else { return }
        hasCompleted = true
        extensionContext?.completeRequest(returningItems: nil)
    }

    // MARK: - Helpers

    private nonisolated static func feedbackState(for result: SaveResult, url: URL) -> ShareFeedbackState {
        switch result {
        case .saved:     return .success(domain: domain(from: url))
        case .duplicate: return .duplicate
        }
    }

    private nonisolated static func domain(from url: URL) -> String {
        var host = url.host ?? url.absoluteString
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        return host
    }
}
