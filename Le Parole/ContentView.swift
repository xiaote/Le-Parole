import SwiftUI

struct ContentView: View {
    @State private var isReady = false
    @State private var appActivity = AppActivity()

    var body: some View {
        Group {
            if isReady {
                TabView {
                    HomeView(appActivity: appActivity)
                        .tabItem { Label("Home", systemImage: "house.fill") }
                    WordBankView(appActivity: appActivity)
                        .tabItem { Label("Words", systemImage: "book.fill") }
                    StatsView(appActivity: appActivity)
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
            let catalogueAlreadyAvailable = await WordLoader.hasCatalogue()
            async let loadData: Void = {
                await WordLoader.loadIfNeeded()
                await WordLoader.ensureSettings()
            }()

            // Existing installs already have a usable local catalogue. Do not
            // hold their entire UI behind a background refresh or decorative
            // splash delay. A genuinely new install still waits for its first
            // atomic import so it cannot start an empty study session.
            if !catalogueAlreadyAvailable {
                await loadData
            }
            withAnimation(.easeInOut(duration: 0.5)) {
                isReady = true
            }

            if catalogueAlreadyAvailable {
                await loadData
            }
        }
    }
}
