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
                        Text("New words per day")
                        Spacer()
                        Text("\(vm.dailyGoal)")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(vm.dailyGoal) },
                            set: { vm.dailyGoal = Int($0) }
                        ),
                        in: 5...50,
                        step: 5
                    )
                } header: {
                    Text("Daily Goal")
                } footer: {
                    Text("Sets how many new words are introduced each day. New bundled words are selected by Italian usage frequency; your own additions come first. Review cards for words already in progress are always included.")
                }

                Section {
                    Stepper(value: Binding(
                        get: { vm.extraConjugationCards },
                        set: { vm.extraConjugationCards = $0 }
                    ), in: 0...20) {
                        HStack {
                            Text("Extra Conjugation Cards")
                            Spacer()
                            Text("\(vm.extraConjugationCards)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Conjugation Level")
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
                    Text("Practice Settings")
                } footer: {
                    Text("Controls how many extra conjugation cards are drawn from verbs you already know during review sessions, and what tenses you are tested on.")
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
                    Text("AI Settings")
                } footer: {
                    Text("Paste your free Google Gemini API key to power dynamic conjugation flashcards with flawless grammar.")
                }

                Section {
                    Toggle("Auto-Play Pronunciation", isOn: Binding(
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
                            Text(backupUrlToExport == nil ? "Generate Backup File" : "Regenerate Backup File")
                        }
                    }
                    
                    if let exportUrl = backupUrlToExport {
                        ShareLink(item: exportUrl) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Save Backup to Files")
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    
                    Button(role: .destructive) {
                        isImporting = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.doc")
                            Text("Restore from Backup")
                        }
                    }
                } header: {
                    Text("Data Backup")
                } footer: {
                    Text("Manually export your progress to a file, or restore from a previously saved backup file. Restoring will overwrite all current progress and instantly close the app to apply changes.")
                }
            }
            .navigationTitle("Settings")
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
