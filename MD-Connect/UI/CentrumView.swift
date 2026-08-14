import SwiftUI

/// Leitstelle module: dispatches (Einsätze), units (Einheiten), activity and
/// archive. When the current character is not signed on as a dispatcher, a
/// "Leitstelle übernehmen" tab is shown first; it disappears automatically once
/// the user is a dispatcher.
struct CentrumView: View {
    @Environment(AppState.self) private var appState

    @State private var showCreateDispatchSheet = false
    @State private var showLeaveDutyUnitConfirm = false

    private var isDispatcher: Bool {
        appState.isDispatcher
    }

    var body: some View {
        TabView {
            if !isDispatcher {
                TakeControlView()
                    .tabItem {
                        Label("Übernehmen", systemImage: "location.fill")
                    }
            }

            DispatchListView()
                .tabItem {
                    Label("Einsätze", systemImage: "exclamationmark.triangle")
                }
            UnitListView()
                .tabItem {
                    Label("Einheiten", systemImage: "building.2")
                }
            ActivityFeedView()
                .tabItem {
                    Label("Aktivität", systemImage: "list.bullet")
                }
            ArchiveView()
                .tabItem {
                    Label("Archiv", systemImage: "archivebox")
                }
        }
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .pendingAlarmBell()
        .moduleNavTitle(.centrum)
        .navConnectionDot()
        .navigationDestination(for: CentrumRoute.self) { route in
            switch route {
            case .dispatch(let id):
                DispatchDetailView(dispatchID: id)
            case .unit(let id):
                UnitDetailView(unitID: id)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showCreateDispatchSheet = true
                } label: {
                    Label("Einsatz erstellen", systemImage: "plus")
                }
                if appState.isDispatcher {
                    Button(role: .destructive) {
                        showLeaveDutyUnitConfirm = true
                    } label: {
                        Label("Leitstellen-Einheit verlassen", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .tint(Theme.Palette.danger)
                }
            }
        }
        .confirmationDialog(
            "Leitstelle verlassen?",
            isPresented: $showLeaveDutyUnitConfirm,
            titleVisibility: .visible
        ) {
            Button("Leitstelle verlassen", role: .destructive) {
                Task { await appState.leaveDutyUnit() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Du verlässt die Leitstelle: deine Einheit wird verlassen und du wirst als Leitstelle abgemeldet. Du kannst jederzeit wieder übernehmen.")
        }
        .sheet(isPresented: $showCreateDispatchSheet) {
            CreateDispatchSheet()
                .environment(appState)
        }
        .task {
            await appState.startCentrumStream()
        }
        .task {
            await appState.loadCentrum()
        }
        .alert("Leitstellen-Fehler", isPresented: Binding(
            get: { appState.centrumError != nil },
            set: { if !$0 { appState.clearCentrumError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.centrumError ?? "")
        }
    }
}

#Preview {
    NavigationStack {
        CentrumView()
            .environment(AppState())
    }
}
