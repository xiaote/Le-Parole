import SwiftUI

struct StudySessionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: StudySessionViewModel?

    let dailyNewLimit: Int
    let isTestMode: Bool
    let isExtraSession: Bool

    init(dailyNewLimit: Int = 20, isTestMode: Bool = false, isExtraSession: Bool = false) {
        self.dailyNewLimit = dailyNewLimit
        self.isTestMode = isTestMode
        self.isExtraSession = isExtraSession
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                Group {
                    if let vm = viewModel {
                        ZStack {
                            if vm.isComplete {
                                SessionCompleteView(stats: vm.stats, isTestMode: vm.isTestMode) { dismiss() }
                            } else if let presentation = vm.presentation {
                                // Not keyed by card: the view carries its
                                // text field, and the keyboard, across cards.
                                QuizCardView(presentation: presentation, vm: vm)
                            } else if vm.isLoadingMoreCards {
                                ProgressView("Loading more cards…")
                                    .font(.theme(.subheadline))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        PreparingSessionView()
                    }
                }
            }
            .toolbar {
                if let vm = viewModel, !vm.isComplete {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("End Session") {
                            if vm.currentIndex > 0 {
                                vm.endSession()
                            } else {
                                dismiss()
                            }
                        }
                    }

                    ToolbarItem(placement: .principal) {
                        SessionProgressTitle(vm: vm)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
        }
        .task {
            if viewModel == nil {
                let vm = StudySessionViewModel()
                await vm.initialize(dailyNewLimit: dailyNewLimit, isTestMode: isTestMode, isExtraSession: isExtraSession)
                viewModel = vm
            }
        }
        .onDisappear {
            viewModel?.cancelSessionWork()
            SpeechService.shared.stop()
        }
    }
}

/// Separate view so queue-length changes (e.g. a familiarity confirmation
/// inserted while a card flips) re-render only the title, not the card.
private struct SessionProgressTitle: View {
    let vm: StudySessionViewModel

    var body: some View {
        VStack(spacing: 2) {
            Text(vm.isTestMode ? "Test Mode" : "Study Session")
                .font(.theme(.headline, weight: .semibold))
            Text("\(vm.currentIndex + 1) of \(vm.totalCardCount)")
                .font(.theme(.caption2, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct PreparingSessionView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            LoadingMark()

            Text("Preparing session…")
                .font(.theme(.title3, weight: .semibold))
                .foregroundStyle(.secondary)

            LoadingDots(color: Theme.primary)
                .padding(.top, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
