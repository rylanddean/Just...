import SwiftUI

// MARK: - State

enum ShareFeedbackState {
    case success(domain: String)
    case duplicate
    case error(reason: String?)

    var autoDismissDelay: TimeInterval {
        if case .error = self { return 2.0 }
        return 1.2
    }
}

// MARK: - View

struct ShareFeedbackView: View {
    let state: ShareFeedbackState
    let onDismiss: () -> Void

    @State private var appeared = false

    // Brand colours — mirrors AppTheme tokens, defined locally so the
    // extension target doesn't depend on the main app module.
    private static let pageBg  = Color(red: 0.047, green: 0.039, blue: 0.031)   // #0C0A08
    private static let surface = Color(red: 0.086, green: 0.075, blue: 0.063)   // #161310

    var body: some View {
        ZStack {
            Self.pageBg
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            card
                .offset(y: appeared ? 0 : 60)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.75, dampingFraction: 0.78), value: appeared)
                .onTapGesture { onDismiss() }
        }
        .onAppear { appeared = true }
    }

    @ViewBuilder
    private var card: some View {
        VStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 40))
                .foregroundColor(.white)
                .symbolEffect(.bounce, value: appeared)

            VStack(spacing: 6) {
                Text(primaryText)
                    .font(.custom("Georgia", size: 17))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                if let sub = secondaryText {
                    Text(sub)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(28)
        .background(Self.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 32)
    }

    private var iconName: String {
        switch state {
        case .success:   return "checkmark.circle.fill"
        case .duplicate: return "minus.circle.fill"
        case .error:     return "xmark.circle.fill"
        }
    }

    private var primaryText: String {
        switch state {
        case .success(let domain): return domain
        case .duplicate:           return "Already in your queue."
        case .error:               return "Couldn\u{2019}t save this link."
        }
    }

    private var secondaryText: String? {
        switch state {
        case .success:           return "Saved to Just\u{2026}"
        case .duplicate:         return nil
        case .error(let reason): return reason
        }
    }
}
