import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "house.fill")
                }

            BooksListView()
                .tabItem {
                    Label("Books", systemImage: "books.vertical.fill")
                }

            SessionsView()
                .tabItem {
                    Label("Sessions", systemImage: "timer")
                }

            PipelineView()
                .tabItem {
                    Label("Pipeline", systemImage: "chart.bar.fill")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
        }
    }
}
