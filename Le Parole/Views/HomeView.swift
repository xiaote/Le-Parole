import SwiftUI

struct HomeView: View {
    @State private var vm = HomeViewModel()
    @State private var showingSession = false
    @State private var showingExtraSession = false
    @State private var showingMistakes = false
    @State private var showingInProgress = false
    @State private var showingTestSession = false
    @State private var showingMastered = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        Button {
                            if vm.mastered > 0 { showingMastered = true }
                        } label: {
                            StatCard(title: "Mastered", value: vm.mastered, icon: "checkmark.seal.fill", color: Theme.primary)
                        }
                        .buttonStyle(.plain)
                        
                        InProgressCard(count: vm.inProgress) {
                            if vm.inProgress > 0 { showingInProgress = true }
                        }
                        
                        StatCard(title: "Due Today", value: vm.dueToday, icon: "clock.fill", color: Theme.primary)
                        
                        MistakesCard(count: vm.mistakesToday.count) {
                            if !vm.mistakesToday.isEmpty { showingMistakes = true }
                        }
                    }
                    .padding(.horizontal)

                    Button {
                        if vm.hasWork { showingSession = true }
                        else if vm.canLearnMore { showingExtraSession = true }
                    } label: {
                        Group {
                            if vm.hasWork {
                                Label("Start Today's Session", systemImage: "play.fill")
                            } else if vm.canLearnMore {
                                Label("Continue Learning", systemImage: "arrow.right.circle.fill")
                            } else {
                                Label("All Caught Up!", systemImage: "checkmark.circle.fill")
                            }
                        }
                        .font(.theme(.body, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(vm.hasWork || vm.canLearnMore ? Theme.primary : Color(.systemGray4))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: (vm.hasWork || vm.canLearnMore) ? Theme.primary.opacity(0.3) : .clear, radius: 8, y: 4)
                    }
                    .disabled(!vm.hasWork && !vm.canLearnMore)
                    .padding(.horizontal)

                    if vm.testQueueCount > 0 {
                        Button {
                            showingTestSession = true
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .font(.title2)
                                        .foregroundStyle(Theme.primary)
                                    Text("Test Out of Words")
                                        .font(.theme(.headline, weight: .bold))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(vm.testQueueCount)")
                                        .font(.theme(.subheadline, weight: .bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Theme.primary.opacity(0.15))
                                        .foregroundStyle(Theme.primary)
                                        .clipShape(Capsule())
                                }
                                Text("Bypass words you already know by translating them in one shot to master them instantly.")
                                    .font(.theme(.subheadline))
                                    .multilineTextAlignment(.leading)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.primary.opacity(0.3), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .refreshable {
                await vm.refresh()
            }
            .navigationTitle("Le Parole")
            .fullScreenCover(isPresented: $showingSession) {
                StudySessionView(dailyNewLimit: vm.dailyGoal)
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
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: Int
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
            Text("\(value)")
                .font(.theme(.title, weight: .bold))
            Text(title)
                .font(.theme(.caption))
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

private struct InProgressCard: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(count > 0 ? Theme.primary : Color.secondary)
                    .font(.title3)
                Text("\(count)")
                    .font(.theme(.title, weight: .bold))
                Text("In Progress")
                    .font(.theme(.caption))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
    }
}

private struct MistakesCard: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundStyle(count > 0 ? Theme.primary : Color.secondary)
                    .font(.title3)
                Text("\(count)")
                    .font(.theme(.title, weight: .bold))
                Text("Missed Today")
                    .font(.theme(.caption))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
    }
}
