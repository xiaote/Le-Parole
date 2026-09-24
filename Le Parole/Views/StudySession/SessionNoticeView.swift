import SwiftUI
import UIKit

struct SessionNotice: Equatable, Sendable {
    enum Tone: Sendable {
        case success
        case encouragement
        case refresh
    }

    let icon: String
    let title: String
    let detail: String?
    let tone: Tone

    static func make(for outcome: ReviewOutcome) -> SessionNotice? {
        switch outcome {
        case .stageChanged(let oldStage, let newStage):
            stageChanged(from: oldStage, to: newStage)
        case .lapseRecovered(let feedback):
            SessionNotice(
                icon: "checkmark.circle.fill",
                title: "Back on track",
                detail: feedback.detail,
                tone: .success
            )
        case .reviewScheduled(let feedback):
            reviewScheduled(feedback)
        case .none:
            nil
        }
    }

    static func stageChanged(from oldStage: WordStage, to newStage: WordStage) -> SessionNotice? {
        switch (oldStage, newStage) {
        case (_, .mastered):
            return SessionNotice(
                icon: "sparkles",
                title: "Mastered!",
                detail: nil,
                tone: .success
            )
        case (.mastered, .production):
            return SessionNotice(
                icon: "arrow.clockwise.circle.fill",
                title: "Quick refresh",
                detail: "Review tomorrow",
                tone: .refresh
            )
        case (_, .production):
            return SessionNotice(
                icon: "arrow.up.right.circle.fill",
                title: "Moving up!",
                detail: nil,
                tone: .success
            )
        case (_, .recognition):
            return SessionNotice(
                icon: "arrow.clockwise.circle.fill",
                title: "Practice tomorrow",
                detail: nil,
                tone: .encouragement
            )
        case (_, .new), (_, .skipped):
            return nil
        }
    }

    static func reviewScheduled(_ feedback: ReviewScheduleFeedback) -> SessionNotice {
        SessionNotice(
            icon: "checkmark.seal.fill",
            title: feedback.title,
            detail: feedback.detail,
            tone: .success
        )
    }

    var tint: Color {
        switch tone {
        case .success: Theme.mastered
        case .encouragement: Theme.primary
        case .refresh: Theme.playfulAccent
        }
    }

    var haptic: UINotificationFeedbackGenerator.FeedbackType? {
        switch tone {
        case .success: .success
        case .encouragement, .refresh: nil
        }
    }

    var accessibilityLabel: String {
        [title, detail].compactMap { $0 }.joined(separator: ". ")
    }
}

struct SessionNoticeView: View {
    let notice: SessionNotice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: notice.icon)
                .font(.theme(.title3, weight: .bold))
                .foregroundStyle(notice.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.theme(.headline, weight: .bold))
                    .foregroundStyle(notice.tint)

                if let detail = notice.detail {
                    Text(detail)
                        .font(.theme(.subheadline, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        .clipShape(Capsule())
        .shadow(color: Theme.cardShadow, radius: 15, y: 5)
        .compositingGroup()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 24)
        .padding(.horizontal, 20)
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.88).combined(with: .opacity).combined(with: .offset(y: -6)),
                removal: .scale(scale: 0.95).combined(with: .opacity)
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(notice.accessibilityLabel)
        .zIndex(100)
    }
}
