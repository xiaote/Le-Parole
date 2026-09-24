import SwiftUI

struct WordBankView: View {
    let appActivity: AppActivity
    @State private var vm = WordBankViewModel()
    @State private var isSelecting = false
    @State private var selectedIDs = Set<Int64>()
    @State private var showingAddWord = false
    @State private var selectedWord: UserWord? = nil
    @State private var wordToDelete: UserWord? = nil

    private let selectAnimation = Animation.spring(response: 0.3, dampingFraction: 0.85)

    private var selectedCount: Int { selectedIDs.count }
    private var showBottomBar: Bool { isSelecting && selectedCount > 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        filterBar
                            .padding(.bottom, 8)

                        Divider()
                            .overlay(Theme.border)
                            .padding(.horizontal, 20)

                        if vm.userWords.isEmpty && !vm.isLoadingMore {
                            ContentUnavailableView(
                                vm.searchText.isEmpty ? "No words here" : "No results",
                                systemImage: vm.searchText.isEmpty ? "text.book.closed" : "magnifyingglass",
                                description: Text(vm.searchText.isEmpty ? "Add a word or choose another category." : "Try a different word or category.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 320)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(vm.userWords) { userWord in
                                    wordRow(userWord)
                                        .onAppear {
                                            vm.loadMoreIfNeeded(after: userWord.id)
                                        }
                                }

                                if vm.hasMoreResults && vm.isLoadingMore {
                                    ProgressView()
                                        .padding(.vertical, 16)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showBottomBar {
                    bottomBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(selectAnimation, value: showBottomBar)
            .searchable(text: $vm.searchText, prompt: "Search Italian or English")
            .navigationTitle("Words")
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .sheet(isPresented: $showingAddWord) { WordFormView(mode: .add) }
            .sheet(item: $selectedWord) { word in
                if word.word.isUserCreated {
                    WordFormView(mode: .edit(word))
                } else {
                    WordDetailView(userWord: word)
                }
            }
            .alert(
                "Delete \"\(wordToDelete?.word.italian ?? "")\"?",
                isPresented: Binding(get: { wordToDelete != nil }, set: { if !$0 { wordToDelete = nil } })
            ) {
                Button("Delete", role: .destructive) {
                    if let word = wordToDelete?.word {
                        vm.deleteWord(word)
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
                    if isSelecting && !vm.showingSkipped {
                        Button("Select loaded") {
                            withAnimation(selectAnimation) {
                                selectedIDs = Set(vm.userWords.compactMap { $0.id })
                            }
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
        .onAppear {
            if !appActivity.isStudySessionActive {
                vm.setObserving(true)
            }
        }
        .onDisappear {
            vm.setObserving(false)
        }
        .onChange(of: appActivity.isStudySessionActive) { _, isStudying in
            vm.setObserving(!isStudying)
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: vm.selectedLevel == nil && !vm.showingSkipped) {
                    selectFilter(level: nil)
                }
                ForEach(Word.cefrLevels + vm.customLevels, id: \.self) { level in
                    FilterChip(title: level, isSelected: vm.selectedLevel == level) {
                        selectFilter(level: level)
                    }
                }
                FilterChip(title: "Skipped", isSelected: vm.showingSkipped, color: Color(.systemGray)) {
                    selectFilter(level: nil, skipped: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private func selectFilter(level: String?, skipped: Bool = false) {
        selectedIDs.removeAll()
        vm.setFilter(level: level, skipped: skipped)
    }

    private func wordRow(_ userWord: UserWord) -> some View {
        let rowID = userWord.id ?? 0
        let isSelected = selectedIDs.contains(rowID)

        return WordRow(userWord: userWord, isSelecting: isSelecting, isSelected: isSelected)
            .contentShape(Rectangle())
            .padding(.vertical, 8)
            .onTapGesture {
                if isSelecting {
                    withAnimation(selectAnimation) {
                        if selectedIDs.contains(rowID) {
                            selectedIDs.remove(rowID)
                        } else {
                            selectedIDs.insert(rowID)
                        }
                    }
                } else {
                    selectedWord = userWord
                }
            }
            .contextMenu {
                if userWord.word.isUserCreated {
                    Button(role: .destructive) {
                        wordToDelete = userWord
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .overlay(alignment: .bottom) {
                Divider()
                    .overlay(Theme.border)
            }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                if vm.showingSkipped {
                    Button {
                        vm.applyStage(.new, to: selectedIDs)
                        withAnimation(selectAnimation) {
                            selectedIDs.removeAll()
                            isSelecting = false
                        }
                    } label: {
                        Label("Restore \(selectedCount)", systemImage: "arrow.uturn.left")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button {
                        vm.applyStage(.skipped, to: selectedIDs)
                        withAnimation(selectAnimation) {
                            selectedIDs.removeAll()
                            isSelecting = false
                        }
                    } label: {
                        Label("Skip \(selectedCount)", systemImage: "slash.circle")
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: .secondary))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(Theme.surface)
    }
}

private struct FilterChip: View {
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
                .background(isSelected ? color : Theme.chipBackground)
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? .clear : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct WordRow: View {
    let userWord: UserWord
    var isSelecting: Bool = false
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Theme.primary : Color(.systemGray3))
                .font(.theme(.title3))
                .frame(width: isSelecting ? 22 : 0)
                .opacity(isSelecting ? 1 : 0)
                .clipped()
                .animation(.easeOut(duration: 0.2), value: isSelecting)

            VStack(alignment: .leading, spacing: 2) {
                Text(userWord.word.italian)
                    .font(Theme.wordList)
                Text(userWord.word.english)
                    .font(.theme(.subheadline))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                LevelChip(level: userWord.word.level)
                Image(systemName: userWord.stage.iconName)
                    .foregroundStyle(userWord.stage.color)
            }
        }
        .padding(.vertical, 4)
    }
}
