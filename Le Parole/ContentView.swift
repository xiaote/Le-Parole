import SwiftUI

struct ContentView: View {
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady {
                TabView {
                    HomeView()
                        .tabItem { Label("Home", systemImage: "house.fill") }
                    WordBankView()
                        .tabItem { Label("Words", systemImage: "book.fill") }
                    StatsView()
                        .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                }
                .toolbarBackground(Theme.surface, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
            } else {
                SplashView()
            }
        }
        .tint(Theme.primary)
        .task {
            async let minimumDelay = try? await Task.sleep(for: .seconds(2.5))
            async let loadData: () = WordLoader.loadIfNeeded()
            
            _ = await (minimumDelay, loadData)
            WordLoader.ensureSettings()
            
            withAnimation(.easeInOut(duration: 0.5)) {
                isReady = true
            }
        }
    }
}
