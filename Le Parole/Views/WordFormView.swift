import SwiftUI
import Translation

/// Add or edit a user-created word.
struct WordFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: WordFormViewModel
    @State private var showingDeleteAlert = false

    init(mode: WordFormViewModel.Mode) {
        _vm = State(initialValue: WordFormViewModel(mode: mode))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. ciao", text: $vm.italian)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if vm.isDuplicate {
                        Label("This word is already in your word bank", systemImage: "exclamationmark.circle.fill")
                            .font(.theme(.caption))
                            .foregroundStyle(.red)
                    }
                    if vm.isConjugated {
                        Label("Please add the infinitive form of this verb instead.", systemImage: "exclamationmark.triangle.fill")
                            .font(.theme(.caption))
                            .foregroundStyle(Theme.playfulAccent)
                    }
                } header: {
                    Text("Italian word")
                }

                Section {
                    HStack {
                        TextField("Translation", text: $vm.english)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if vm.isTranslating {
                            ProgressView().scaleEffect(0.75)
                        }
                    }
                } header: {
                    Text("English translation")
                } footer: {
                    Text("Auto-filled — edit as needed.")
                }

                Section {
                    ForEach(vm.alternatives.indices, id: \.self) { i in
                        HStack {
                            TextField("Alternative translation", text: $vm.alternatives[i])
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            Button { vm.alternatives.remove(at: i) } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button { vm.alternatives.append("") } label: {
                        Label("Add alternative", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Alternative translations")
                } footer: {
                    Text("Other accepted English answers for this word.")
                }

                Section {
                    Picker("Category", selection: $vm.selectedCategory) {
                        ForEach(vm.allCategories, id: \.self) { level in
                            Text(level).tag(level)
                        }
                        Text("New category…").tag(WordFormViewModel.newCategoryTag)
                    }
                    if vm.selectedCategory == WordFormViewModel.newCategoryTag {
                        TextField("e.g. Food, Travel…", text: $vm.newCategoryName)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Category")
                } footer: {
                    if vm.isAssessingLevel {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.75)
                            Text("Assessing level…")
                        }
                        .font(.theme(.caption))
                        .foregroundStyle(.secondary)
                    }
                }

                if vm.editingWord != nil {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Text("Delete word")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle(vm.editingWord == nil ? "Add Word" : "Edit Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.editingWord == nil ? "Add" : "Save") {
                        vm.save()
                        dismiss()
                    }
                    .disabled(!vm.canSave)
                }
            }
        }
        .alert("Delete \"\(vm.editingWord?.italian ?? "")\"?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                vm.delete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This word and all its progress will be permanently deleted.")
        }
        .task { await vm.load() }
        .onDisappear { vm.cancelPendingWork() }
        .translationTask(vm.translationConfig) { session in
            let response = try? await session.translate(vm.trimmedItalian)
            vm.applyTranslation(response?.targetText)
        }
    }
}
