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

/// Stacks the two sides of a flip card, centred, and takes the size of one of
/// them: the prompt until the card is revealed, then the answer. The hidden
/// answer side therefore never pads the card before it is needed, and the
/// card resizes in the same transaction as the flip.
struct FlipCardLayout: Layout {
    var showsBack: Bool

    private func sizingIndex(_ subviews: Subviews) -> Int {
        showsBack ? subviews.count - 1 : 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        return subviews[sizingIndex(subviews)].sizeThatFits(proposal)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: proposal)
        }
    }
}
