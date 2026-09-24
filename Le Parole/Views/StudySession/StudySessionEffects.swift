import SwiftUI

struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 12
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let unitProgress = animatableData.truncatingRemainder(dividingBy: 1.0)
        let progress = unitProgress == 0 && animatableData > 0 ? 1.0 : unitProgress
        let damping = max(0, 1.0 - progress)
        let translation = travel * damping * sin(progress * .pi * 2 * shakesPerUnit)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

struct FlipEffect: AnimatableModifier {
    var angle: Double
    var isBack: Bool
    var perspective: CGFloat = 0.25

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let normalized = angle.truncatingRemainder(dividingBy: 360)
        let positiveAngle = normalized < 0 ? normalized + 360 : normalized
        let isFrontVisible = positiveAngle < 90 || positiveAngle > 270

        let shouldShow = isBack ? !isFrontVisible : isFrontVisible
        let rotationAngle = isBack ? angle - 180 : angle

        content
            .rotation3DEffect(
                .degrees(rotationAngle),
                axis: (x: 0, y: 1, z: 0),
                perspective: perspective
            )
            .opacity(shouldShow ? 1 : 0)
            .allowsHitTesting(shouldShow)
    }
}
