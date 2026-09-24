import SwiftUI

struct SplashView: View {
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.0

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
                    LoadingMark(onGradient: true)

                    Text("Le Parole")
                        .font(.theme(.largeTitle, weight: .bold))
                        .foregroundStyle(.white)
                        .tracking(1.5)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                }
                .scaleEffect(scale)
                .opacity(opacity)

                Spacer()

                LoadingDots(color: .white)
                    .padding(.bottom, 60)
                    .opacity(opacity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}

#Preview {
    SplashView()
}
