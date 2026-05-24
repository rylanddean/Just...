import SwiftUI
import SwiftData

struct AddLinkView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \QueuedLink.sortOrder, order: .reverse) private var existingLinks: [QueuedLink]

    @State private var urlText: String = ""
    @State private var isValidating: Bool = false
    @State private var error: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste a link")
                        .font(AppTheme.sansSerif(13))
                        .foregroundStyle(AppTheme.textFaint)

                    HStack(spacing: 10) {
                        TextField("https://…", text: $urlText)
                            .font(AppTheme.sansSerif(15))
                            .foregroundStyle(AppTheme.heading)
                            .tint(AppTheme.accent)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .focused($isFocused)
                            .submitLabel(.go)
                            .onSubmit { addLink() }

                        if !urlText.isEmpty {
                            Button {
                                urlText = ""
                                error = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AppTheme.textFaint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(error != nil ? AppTheme.danger.opacity(0.6) : AppTheme.separator)
                    }

                    if let error {
                        Text(error)
                            .font(AppTheme.sansSerif(12))
                            .foregroundStyle(AppTheme.danger)
                            .transition(.opacity)
                    }
                }

                Button(action: addLink) {
                    HStack {
                        Spacer()
                        if isValidating {
                            ProgressView()
                                .tint(AppTheme.background)
                        } else {
                            Text("Add to queue")
                                .font(AppTheme.sansSerif(15, weight: .semibold))
                                .foregroundStyle(AppTheme.background)
                        }
                        Spacer()
                    }
                    .frame(height: 48)
                    .background(AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isValidating)
                .opacity(urlText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(AppTheme.pagePadding)
            .background(AppTheme.background)
            .navigationTitle("Add link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.textFaint)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium])
        .presentationBackground(AppTheme.background)
    }

    // MARK: - Actions

    private func addLink() {
        let raw = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        var urlString = raw
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }

        guard URL(string: urlString) != nil else {
            withAnimation { error = "That doesn't look like a valid URL." }
            return
        }

        isValidating = true
        let nextOrder = (existingLinks.first?.sortOrder ?? -1) + 1
        let link = QueuedLink(url: urlString, sortOrder: nextOrder)
        context.insert(link)

        // Prefetch metadata — capture only the URL string so we don't send
        // the @Model object across the actor boundary.
        let capturedURL = urlString
        Task {
            if let result = try? await ContentFetcher.fetch(urlString: capturedURL) {
                link.title = result.content.title
                link.domain = result.content.domain
                link.cachedHTML = result.rawHTML
                try? context.save()
            }
            isValidating = false
            dismiss()
        }
    }
}
