import SwiftUI

struct HomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var vm = HomeViewModel()
    @State private var showingSession = false
    @State private var showingExtraSession = false
    @State private var showingMistakes = false
    @State private var showingInProgress = false
    @State private var showingTestSession = false
    @State private var showingMastered = false

    private var sessionAction: String {
        vm.hasWork ? "Start practice" : (vm.canLearnMore ? "Keep learning" : "All caught up")
    }

    private var dashboardColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        PracticeCard(
                            title: sessionAction,
                            completedToday: vm.reviewAttemptsToday,
                            dailyTarget: vm.dailyPracticeGoal,
                            isEnabled: vm.hasWork || vm.canLearnMore
                        ) {
                            if vm.hasWork {
                                showingSession = true
                            } else if vm.canLearnMore {
                                showingExtraSession = true
                            }
                        }

                        LazyVGrid(columns: dashboardColumns, spacing: 12) {
                            DashboardTile(
                                title: "Mastered",
                                value: vm.mastered.formatted(),
                                detail: "words",
                                tint: Theme.mastered,
                                isEnabled: vm.mastered > 0
                            ) {
                                showingMastered = true
                            }

                            DashboardTile(
                                title: "In progress",
                                value: vm.inProgress.formatted(),
                                detail: "words",
                                tint: Theme.primary,
                                isEnabled: vm.inProgress > 0
                            ) {
                                showingInProgress = true
                            }

                            if !vm.mistakesToday.isEmpty {
                                DashboardTile(
                                    title: "Mistakes",
                                    value: vm.mistakesToday.count.formatted(),
                                    detail: "errors",
                                    tint: Theme.playfulAccent
                                ) {
                                    showingMistakes = true
                                }
                            }

                            if vm.testQueueCount > 0 {
                                DashboardTile(
                                    title: "Test out",
                                    value: vm.testQueueCount.formatted(),
                                    detail: "words ready",
                                    tint: Theme.primary
                                ) {
                                    showingTestSession = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .refreshable {
                await vm.refresh()
            }
            .navigationTitle("Today")
            .fullScreenCover(isPresented: $showingSession) {
                StudySessionView(dailyNewLimit: vm.newWordPacing)
            }
            .fullScreenCover(isPresented: $showingExtraSession) {
                StudySessionView(dailyNewLimit: vm.extraSessionDailyLimit)
            }
            .fullScreenCover(isPresented: $showingTestSession) {
                StudySessionView(dailyNewLimit: Int.max, isTestMode: true)
            }
            .sheet(isPresented: $showingMistakes) {
                MistakesReviewView(words: vm.mistakesToday.map { MistakeItem(userWord: $0, cardType: .production, context: nil) })
            }
            .sheet(isPresented: $showingInProgress) {
                InProgressView(words: vm.getInProgressWords())
            }
            .sheet(isPresented: $showingMastered) {
                MasteredWordsView(words: vm.getMasteredWords())
            }
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
        }
    }
}

private struct PracticeCard: View {
    let title: String
    let completedToday: Int
    let dailyTarget: Int
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 12) {
                    Text(title)
                        .font(.theme(.title3, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    CardAccessory(
                        systemImage: isEnabled ? "arrow.right" : "checkmark",
                        tint: Theme.primary,
                        isFilled: true
                    )
                }

                HStack(alignment: .center, spacing: 20) {
                    DailyGoalRing(completed: completedToday, target: dailyTarget)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(completedToday.formatted()) of \(dailyTarget.formatted())")
                            .font(.theme(.title2, weight: .bold))
                            .foregroundStyle(Theme.primary)
                            .monospacedDigit()
                            .lineLimit(1)

                        Text("reviews completed today")
                            .font(.theme(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
            .primaryDashboardCard()
        }
        .buttonStyle(DashboardCardButtonStyle())
        .disabled(!isEnabled)
        .accessibilityHint(isEnabled ? "Starts a study session" : "No practice is currently available")
    }

}

private struct DailyGoalRing: View {
    let completed: Int
    let target: Int

    private var progress: Double {
        min(max(Double(completed) / Double(max(target, 1)), 0), 1)
    }

    private var isComplete: Bool {
        target > 0 && completed >= target
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.primary.opacity(0.16), lineWidth: 10)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Theme.primary,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if isComplete {
                Image(systemName: "checkmark")
                    .font(.theme(.headline, weight: .bold))
                    .foregroundStyle(Theme.primary)
            } else {
                Text(completed.formatted())
                    .font(.theme(.headline, weight: .bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(12)
            }
        }
        .frame(width: 88, height: 88)
        .animation(.easeOut(duration: 0.45), value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily practice goal: \(completed) of \(target) reviews completed")
    }
}

private struct DashboardTile: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text(title)
                        .font(.theme(.headline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Spacer(minLength: 4)

                    CardAccessory(systemImage: "chevron.right", tint: .secondary)
                        .opacity(isEnabled ? 1 : 0.35)
                }

                Spacer(minLength: 16)

                Text(value)
                    .font(.theme(.title2, weight: .bold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(detail)
                    .font(.theme(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 146, alignment: .leading)
            .themeCard()
        }
        .buttonStyle(DashboardCardButtonStyle())
        .disabled(!isEnabled)
    }
}

private struct CardAccessory: View {
    let systemImage: String
    let tint: Color
    var isFilled = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.theme(.subheadline, weight: .semibold))
            .foregroundStyle(isFilled ? Color.white : tint)
            .frame(width: 32, height: 32)
            .background(isFilled ? tint : Theme.chipBackground)
            .clipShape(Circle())
    }
}

private extension View {
    func primaryDashboardCard() -> some View {
        background {
            ZStack {
                Theme.surface
                LinearGradient(
                    colors: [Theme.primary.opacity(0.18), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .stroke(Theme.primary.opacity(0.32), lineWidth: 1)
        }
        .shadow(color: Theme.cardShadow, radius: 14, y: 7)
    }
}

private struct DashboardCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
