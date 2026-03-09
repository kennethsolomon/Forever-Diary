import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            AnalyticsView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar.fill")
                }

            CalendarBrowserView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(Color("accentSlate"))
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            DiaryEntry.self,
            CheckInTemplate.self,
            CheckInValue.self,
            PhotoAsset.self
        ], inMemory: true)
}
