import SwiftUI

struct SplashView: View {
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.0
    @State private var pulse: Bool = false
    @State private var isAnimatingLoader = false

    var body: some View {
        ZStack {
            // Sleek primary accent gradient
            LinearGradient(
                stops: [
                    .init(color: Theme.primaryLight, location: 0.00),
                    .init(color: Theme.primary, location: 0.50),
                    .init(color: Theme.primaryDark, location: 1.00),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Sleek new logo concept (Abstract Chat/Language)
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.15))
                            .frame(width: 120, height: 120)
                            .scaleEffect(pulse ? 1.05 : 0.95)
                            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)
                        
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 52, weight: .regular))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    }

                    Text("Le Parole")
                        .font(.theme(.largeTitle, weight: .bold))
                        .foregroundStyle(.white)
                        .tracking(1.5)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                }
                .scaleEffect(scale)
                .opacity(opacity)

                Spacer()

                // Custom Sleek Loader
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .scaleEffect(isAnimatingLoader ? 1 : 0.5)
                            .opacity(isAnimatingLoader ? 1 : 0.3)
                            .animation(
                                .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(0.2 * Double(index)),
                                value: isAnimatingLoader
                            )
                    }
                }
                .padding(.bottom, 60)
                .opacity(opacity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                scale = 1.0
                opacity = 1.0
            }
            pulse = true
            isAnimatingLoader = true
        }
    }
}

#Preview {
    SplashView()
}
