import SwiftUI

/// The pulsing book mark shown while the app or a study session is loading.
struct LoadingMark: View {
    /// White mark sized for the splash gradient; otherwise the smaller, primary-tinted in-app variant.
    var onGradient = false

    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(onGradient ? Color.white.opacity(0.15) : Theme.primary.opacity(0.1))
                .frame(width: onGradient ? 120 : 100, height: onGradient ? 120 : 100)
                .scaleEffect(pulse ? 1.05 : 0.95)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)

            Image(systemName: "book.closed.fill")
                .font(.system(size: onGradient ? 52 : 42, weight: .regular))
                .foregroundStyle(onGradient ? Color.white : Theme.primary)
                .shadow(color: .black.opacity(onGradient ? 0.15 : 0), radius: 8, x: 0, y: 4)
        }
        .onAppear { pulse = true }
    }
}

/// Three dots pulsing in sequence.
struct LoadingDots: View {
    let color: Color

    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isAnimating ? 1 : 0.5)
                    .opacity(isAnimating ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(0.2 * Double(index)),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
    }
}
