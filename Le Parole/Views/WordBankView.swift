import SwiftUI
import GRDB

struct WordBankView: View {
    @State private var vm = WordBankViewModel()
    @State private var selectedLevel: String? = nil
    @State private var searchText = ""
    @State private var showingSkipped = false
    @State private var isSelecting = false
    @State private var selectedIDs = Set<Int64>()
    @State private var showingAddWord = false
    @State private var selectedWord: UserWord? = nil
    @State private var wordToDelete: UserWord? = nil

    private let builtInLevels = ["A1", "A2", "B1", "B2", "C1", "C2"]
    private let selectAnimation = Animation.spring(response: 0.3, dampingFraction: 0.85)



    private var selectedCount: Int { selectedIDs.count }
    private var showBottomBar: Bool { isSelecting && selectedCount > 0 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        LevelChip(title: "All", isSelected: selectedLevel == nil && !showingSkipped) {
                            selectedLevel = nil
                            showingSkipped = false
                            selectedIDs.removeAll()
                            vm.selectedLevel = nil
                            vm.showingSkipped = false
                        }
                        ForEach(builtInLevels, id: \.self) { level in
                            LevelChip(title: level, isSelected: selectedLevel == level && !showingSkipped) {
                                selectedLevel = level
                                showingSkipped = false
                                selectedIDs.removeAll()
                                vm.selectedLevel = level
                                vm.showingSkipped = false
                            }
                        }
                        ForEach(vm.customLevels, id: \.self) { level in
                            LevelChip(title: level, isSelected: selectedLevel == level && !showingSkipped, color: Theme.primaryDark) {
                                selectedLevel = level
                                showingSkipped = false
                                selectedIDs.removeAll()
                                vm.selectedLevel = level
                                vm.showingSkipped = false
                            }
                        }
                        LevelChip(title: "Skipped", isSelected: showingSkipped, color: Color(.systemGray)) {
                            showingSkipped = true
                            selectedLevel = nil
                            selectedIDs.removeAll()
                            vm.showingSkipped = true
                            vm.selectedLevel = nil
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                Divider()

                List(vm.userWords) { uw in
                    let rowId = uw.id ?? 0
                    let isSelected = selectedIDs.contains(rowId)
                    WordRow(userWord: uw, isSelecting: isSelecting, isSelected: isSelected)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelecting {
                                withAnimation(selectAnimation) {
                                    if selectedIDs.contains(rowId) { selectedIDs.remove(rowId) }
                                    else { selectedIDs.insert(rowId) }
                                }
                            } else {
                                selectedWord = uw
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if uw.word.isUserCreated {
                                Button(role: .destructive) {
                                    wordToDelete = uw
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                }
                .listStyle(.plain)

                if showBottomBar {
                    bottomBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(selectAnimation, value: showBottomBar)
            .searchable(text: $searchText, prompt: "Search Italian or English")
            .onChange(of: searchText) { _, newValue in
                vm.searchText = newValue
            }
            .navigationTitle("Word Bank")
            .sheet(isPresented: $showingAddWord) { AddWordView() }
            .sheet(item: $selectedWord) { word in
                if word.word.isUserCreated {
                    EditWordView(userWord: word)
                } else {
                    WordDetailView(userWord: word)
                }
            }
            .alert(
                "Delete \"\(wordToDelete?.word.italian ?? "")\"?",
                isPresented: Binding(get: { wordToDelete != nil }, set: { if !$0 { wordToDelete = nil } })
            ) {
                Button("Delete", role: .destructive) {
                    if let w = wordToDelete {
                        let word = w.word
                        Task.detached {
                            try? DatabaseService.shared.db.write { db in try word.delete(db) }
                        }
                    }
                    wordToDelete = nil
                }
                Button("Cancel", role: .cancel) { wordToDelete = nil }
            } message: {
                Text("This word and all its progress will be permanently deleted.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isSelecting {
                        Button("Done") {
                            withAnimation(selectAnimation) {
                                isSelecting = false
                                selectedIDs.removeAll()
                            }
                        }
                    } else {
                        HStack(spacing: 4) {
                            Button { showingAddWord = true } label: {
                                Image(systemName: "plus")
                                    .frame(width: 36, height: 36)
                            }
                            Button {
                                withAnimation(selectAnimation) { isSelecting = true }
                            } label: {
                                Image(systemName: "checkmark.circle")
                                    .frame(width: 36, height: 36)
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if isSelecting && !showingSkipped {
                        Button("Select All") {
                            withAnimation(selectAnimation) {
                                selectedIDs = Set(vm.userWords.compactMap { $0.id })
                            }
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                if showingSkipped {
                    Button {
                        vm.applyStage(.new, to: selectedIDs)
                        withAnimation(selectAnimation) {
                            selectedIDs.removeAll()
                            isSelecting = false
                        }
                    } label: {
                        Label("Restore \(selectedCount)", systemImage: "arrow.uturn.left")
                            .font(.theme(.body, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.primary.opacity(0.12))
                            .foregroundStyle(Theme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                } else {
                    Button {
                        vm.applyStage(.skipped, to: selectedIDs)
                        withAnimation(selectAnimation) {
                            selectedIDs.removeAll()
                            isSelecting = false
                        }
                    } label: {
                        Label("Skip \(selectedCount)", systemImage: "slash.circle")
                            .font(.theme(.body, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray5))
                            .foregroundStyle(Color.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial)
    }
}

private struct LevelChip: View {
    let title: String
    let isSelected: Bool
    var color: Color = Theme.primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.theme(.subheadline, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? color : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct WordRow: View {
    let userWord: UserWord
    var isSelecting: Bool = false
    var isSelected: Bool = false

    private var stageColor: Color {
        switch userWord.stage {
        case .new:         Color(.systemGray3)
        case .skipped:     Color(.systemGray)
        case .recognition: Theme.primaryLight
        case .production:  Theme.primary
        case .mastered:    Theme.primaryDark
        }
    }

    private var stageIcon: String {
        switch userWord.stage {
        case .new:         "circle"
        case .skipped:     "slash.circle"
        case .recognition: "eye"
        case .production:  "pencil"
        case .mastered:    "checkmark.seal.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Theme.primary : Color(.systemGray3))
                .font(.title3)
                .frame(width: isSelecting ? 22 : 0)
                .opacity(isSelecting ? 1 : 0)
                .clipped()
                .animation(.easeOut(duration: 0.2), value: isSelecting)

            VStack(alignment: .leading, spacing: 2) {
                Text(userWord.word.italian)
                    .font(.theme(.body, weight: .bold))
                Text(userWord.word.english)
                    .font(.theme(.subheadline))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Text(userWord.word.level)
                    .font(.theme(.caption, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
                Image(systemName: stageIcon)
                    .foregroundStyle(stageColor)
            }
        }
        .padding(.vertical, 4)
    }
}
