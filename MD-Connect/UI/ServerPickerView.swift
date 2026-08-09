import SwiftUI

/// Lists all configured servers and lets the user switch or remove them.
struct ServerPickerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(removableServers, id: \.self) { server in
                        Button {
                            appState.selectServer(server)
                        } label: {
                            HStack(spacing: Theme.Spacing.md) {
                                Label(server.host ?? server.absoluteString, systemImage: "server.rack")
                                Spacer()
                                if server == appState.session.activeServer {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        let servers = appState.session.servers
                        for index in offsets {
                            appState.removeServer(servers[index])
                        }
                    }
                } header: {
                    Text("Server")
                } footer: {
                    Text("Zum Löschen nach links wischen. Sessions werden pro Server gespeichert.")
                }

                if let demo = demoServerEntry {
                    Section {
                        Button {
                            appState.selectServer(AuthSessionStore.demoServer)
                        } label: {
                            HStack(spacing: Theme.Spacing.md) {
                                Label("Demo-Server (fivenet.app)", systemImage: "sparkles")
                                if demo == appState.session.activeServer {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    } header: {
                        Text("Demo")
                    } footer: {
                        Text("Der offizielle FiveNet-Demo-Server. Leistungsmerkmale und Daten sind Beispiele – eigene Zugangsdaten werden nicht benötigt. Der Demo-Server kann nicht gelöscht werden.")
                    }
                }

                Section {
                    Button {
                        appState.addServer()
                    } label: {
                        Label("Manuell eingeben", systemImage: "plus")
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fertig") {
                        appState.doneChangingServer()
                    }
                }
            }
            .navigationTitle("Server")
        }
    }

    /// Servers that can be removed by swiping (the demo server is exempt).
    private var removableServers: [URL] {
        appState.session.servers.filter { $0 != AuthSessionStore.demoServer }
    }

    /// The demo server if it is part of the session's server list.
    private var demoServerEntry: URL? {
        appState.session.servers.first { $0 == AuthSessionStore.demoServer }
    }
}

#Preview {
    ServerPickerView()
        .environment(AppState())
}