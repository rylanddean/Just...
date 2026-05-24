import SwiftUI

struct VoiceInputButton: View {
    @Binding var isListening: Bool
    let onToggle: () -> Void

    @State private var wavePhase: Double = 0

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                Circle()
                    .fill(isListening ? AppTheme.readerAccent.opacity(0.15) : AppTheme.surface)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Circle()
                            .stroke(
                                isListening ? AppTheme.readerAccent : AppTheme.separator,
                                lineWidth: 1.5
                            )
                    }

                if isListening {
                    // Animated waveform bars
                    HStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppTheme.readerAccent)
                                .frame(width: 3, height: barHeight(for: i))
                                .animation(
                                    .easeInOut(duration: 0.5)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(i) * 0.1),
                                    value: isListening
                                )
                        }
                    }
                } else {
                    Image(systemName: "mic")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(AppTheme.textFaint)
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            wavePhase = 1
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [10, 18, 14, 8]
        return isListening ? heights[index] : 12
    }
}

#Preview {
    HStack(spacing: 24) {
        VoiceInputButton(isListening: .constant(false)) {}
        VoiceInputButton(isListening: .constant(true)) {}
    }
    .padding()
    .background(AppTheme.background)
}
