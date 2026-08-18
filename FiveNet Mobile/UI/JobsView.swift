import SwiftUI

/// Berufe module: job overview, colleagues, activity, timeclock and conduct
/// register. Mirrors the web navigation (`/jobs/*`).
struct JobsView: View {
    @Environment(AppState.self) private var appState

    @State private var selection: QuickAccessTab?

    @State private var showCreateGroupSheet = false

    init(initialTab: QuickAccessTab? = nil) {
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selection) {
            JobOverviewView()
                .tabItem {
                    Label("Übersicht", systemImage: "house")
                }
                .tag(QuickAccessTab.jobsOverview)

            ColleaguesListView()
                .tabItem {
                    Label("Kollegen", systemImage: "person.2")
                }
                .tag(QuickAccessTab.jobsColleagues)

            JobGroupsListView(isPresentingCreateSheet: $showCreateGroupSheet)
                .tabItem {
                    Label("Gruppen", systemImage: "person.3")
                }
                .tag(QuickAccessTab.jobsGroups)

            JobActivityFeedView()
                .tabItem {
                    Label("Aktivität", systemImage: "list.bullet")
                }
                .tag(QuickAccessTab.jobsActivity)

            JobTimeclockTabsView()
                .tabItem {
                    Label("Stempeluhr", systemImage: "clock.badge.checkmark")
                }
                .tag(QuickAccessTab.jobsTimeclock)

            JobConductListView(userID: nil)
                .tabItem {
                    Label("Führungsregister", systemImage: "list.clipboard")
                }
                .tag(QuickAccessTab.jobsConduct)
        }
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .pendingAlarmBell()
        .moduleNavTitle(.jobs)
        .navConnectionDot()
        .toolbar {
            if selection == .jobsGroups {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateGroupSheet = true
                    } label: {
                        Label("Neue Gruppe", systemImage: "plus")
                    }
                }
            }
        }
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
