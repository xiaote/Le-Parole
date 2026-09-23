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
                            } else if let card = vm.currentCard {
                                QuizCardView(card: card, vm: vm)
                                    .id(card.id)
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
                        VStack(spacing: 2) {
                            Text(vm.isTestMode ? "Test Mode" : "Study Session")
                                .font(.theme(.headline, weight: .semibold))
                            Text("\(vm.currentIndex + 1) of \(vm.totalCardCount)")
                                .font(.theme(.caption2, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
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

private struct PreparingSessionView: View {
    @State private var pulse = false
    @State private var isAnimatingLoader = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Sleek Logo Concept
            ZStack {
                Circle()
                    .fill(Theme.primary.opacity(0.1))
                    .frame(width: 100, height: 100)
                    .scaleEffect(pulse ? 1.05 : 0.95)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)
                
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(Theme.primary)
            }
            
            Text("Preparing session…")
                .font(.theme(.title3, weight: .semibold))
                .foregroundStyle(.secondary)
            
            // Custom Sleek Loader
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Theme.primary)
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
            .padding(.top, 16)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            pulse = true
            isAnimatingLoader = true
        }
    }
}
