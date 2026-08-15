import SwiftUI

/// Berufe module: job overview, colleagues, activity, timeclock and conduct
/// register. Mirrors the web navigation (`/jobs/*`).
struct JobsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            JobOverviewView()
                .tabItem {
                    Label("Übersicht", systemImage: "house")
                }

            ColleaguesListView()
                .tabItem {
                    Label("Kollegen", systemImage: "person.2")
                }

            JobActivityFeedView()
                .tabItem {
                    Label("Aktivität", systemImage: "list.bullet")
                }

            JobTimeclockTabsView()
                .tabItem {
                    Label("Stempeluhr", systemImage: "clock.badge.checkmark")
                }

            JobConductListView(userID: nil)
                .tabItem {
                    Label("Führungsregister", systemImage: "list.clipboard")
                }
        }
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .pendingAlarmBell()
        .moduleNavTitle(.jobs)
        .navConnectionDot()
    }
}

/// Navigation route for a colleague detail, using a distinct type so the
/// `navigationDestination` does not conflict with other Int32-based routes.
struct ColleagueRoute: Hashable {
    let userID: Int32
}

/// Navigation route for a single conduct register entry detail.
struct ConductRoute: Hashable {
    let entryID: Int64
}

#Preview {
    NavigationStack {
        JobsView()
            .environment(AppState())
    }
}
