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
            // Returns at once when a catalogue exists (any refresh continues in
            // the background); a new install waits for its first import so it
            // cannot start an empty study session.
            await WordLoader.prepare()
            withAnimation(.easeInOut(duration: 0.5)) {
                isReady = true
            }
        }
    }
}
