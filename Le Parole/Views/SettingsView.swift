import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var vm = SettingsViewModel()
    @State private var isApiKeyVisible = false
    @State private var isImporting = false
    @State private var backupUrlToExport: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Reviews per day")
                        Spacer()
                        Text("\(vm.dailyPracticeGoal)")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(vm.dailyPracticeGoal) },
                            set: { vm.dailyPracticeGoal = Int($0) }
                        ),
                        in: 10...500,
                        step: 10
                    )
                } header: {
                    Text("Daily practice")
                } footer: {
                    Text("Sets the daily progress target on Home. Each answered practice card counts toward this goal.")
                }

                Section {
                    HStack {
                        Text("New words per day")
                        Spacer()
                        Text("\(vm.newWordsPerDay)")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(vm.newWordsPerDay) },
                            set: { vm.newWordsPerDay = Int($0) }
                        ),
                        in: 5...50,
                        step: 5
                    )
                } header: {
                    Text("New-word pacing")
                } footer: {
                    Text("Limits how many new words are introduced each day. Reviews are always included in practice.")
                }

                Section {
                    HStack {
                        Text("Conjugation level")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { vm.conjugationLevel },
                            set: { vm.conjugationLevel = $0 }
                        )) {
                            Text("1 (Present)").tag(1)
                            Text("2 (Past)").tag(2)
                            Text("3 (Future/Command)").tag(3)
                            Text("4 (Conditional)").tag(4)
                            Text("5 (Subjunctive)").tag(5)
                        }
                    }
                } header: {
                    Text("Practice")
                } footer: {
                    Text("Controls which tenses appear when a due verb is reviewed as a conjugation card.")
                }

                Section {
                    HStack {
                        if isApiKeyVisible {
                            TextField("Gemini API Key", text: Binding(
                                get: { vm.geminiApiKey },
                                set: { vm.geminiApiKey = $0 }
                            ))
                        } else {
                            SecureField("Gemini API Key", text: Binding(
                                get: { vm.geminiApiKey },
                                set: { vm.geminiApiKey = $0 }
                            ))
                        }
                        
                        Button {
                            isApiKeyVisible.toggle()
                        } label: {
                            Image(systemName: isApiKeyVisible ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                } header: {
                    Text("AI")
                } footer: {
                    Text("Paste your free Google Gemini API key to power dynamic conjugation flashcards with flawless grammar.")
                }

                Section {
                    Toggle("Auto-play pronunciation", isOn: Binding(
                        get: { vm.autoPlayPronunciation },
                        set: { vm.autoPlayPronunciation = $0 }
                    ))
                } header: {
                    Text("Audio")
                } footer: {
                    Text("Automatically plays the Italian pronunciation when a flashcard is revealed.")
                }
                
                Section {
                    Button {
                        do {
                            backupUrlToExport = try DatabaseService.shared.exportDatabase()
                        } catch {
                            print("Export failed: \(error)")
                        }
                    } label: {
                        HStack {
                            Image(systemName: "archivebox")
                            Text(backupUrlToExport == nil ? "Generate backup file" : "Regenerate backup file")
                        }
                    }
                    
                    if let exportUrl = backupUrlToExport {
                        ShareLink(item: exportUrl) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Save backup to Files")
                                    .font(.theme(.body, weight: .semibold))
                            }
                        }
                    }
                    
                    Button(role: .destructive) {
                        isImporting = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.doc")
                            Text("Restore from backup")
                        }
                    }
                } header: {
                    Text("Data backup")
                } footer: {
                    Text("Manually export your progress to a file, or restore from a previously saved backup file. Restoring will overwrite all current progress and instantly close the app to apply changes.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Settings")
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let fileUrl = urls.first else { return }
                    do {
                        try DatabaseService.shared.importDatabase(from: fileUrl)
                        // Give the system daemon time to process the stopAccessingSecurityScopedResource IPC message
                        // before force killing the app, otherwise the file stays locked as a ghost process.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            exit(0)
                        }
                    } catch {
                        print("Failed to restore: \(error)")
                    }
                case .failure(let error):
                    print("Import error: \(error)")
                }
            }
        }
    }
}
