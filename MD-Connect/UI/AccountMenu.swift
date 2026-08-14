import SwiftUI

/// Die zwei App-Ansichten, die über das Konto-Menü gewechselt werden können.
/// Persistiert über `@AppStorage("appViewMode")`.
enum AppViewMode: String {
    case overview
    case quick
}

/// Gemeinsames Konto-/Aktions-Menü (drei Punkte) für Übersicht und
/// Quick-Ansicht: Charakter wechseln, Server wechseln, Ansicht wechseln,
/// Abmelden. Als Toolbar-Item/Menü, damit es zuverlässig reagiert.
struct AccountMenu: View {
    @Environment(AppState.self) private var appState
    @AppStorage("appViewMode") private var viewMode: AppViewMode = .overview
    @State private var showClearCacheConfirm = false

    var body: some View {
        Menu {
            Button {
                appState.switchCharacter()
            } label: {
                Label("Charakter wechseln", systemImage: "arrow.triangle.2.circlepath")
            }

            Button {
                appState.changeServer()
            } label: {
                Label("Server wechseln", systemImage: "server.rack")
            }

            Button {
                viewMode = (viewMode == .overview) ? .quick : .overview
            } label: {
                Label(
                    viewMode == .overview ? "Schnellansicht" : "Normale Ansicht",
                    systemImage: viewMode == .overview ? "bolt.fill" : "square.grid.2x2.fill"
                )
            }

            Button(role: .destructive) {
                showClearCacheConfirm = true
            } label: {
                Label("Cache löschen", systemImage: "trash")
            }

            Button(role: .destructive) {
                Task { await appState.logout() }
            } label: {
                Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
        .confirmationDialog(
            "Cache löschen?",
            isPresented: $showClearCacheConfirm,
            titleVisibility: .visible
        ) {
            Button("Cache löschen", role: .destructive) {
                ViewedContentCache.shared.clear()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Gesehene Wiki- und Dokument-Inhalte werden aus dem Cache entfernt.")
        }
    }
}

/// Kompakte Status-Zeile (Verbindungs-Punkt + Text), wie sie Übersicht und
/// Quick-Ansicht im Content-Header neben dem Menü verwenden.
struct ConnectionLabel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(appState.isChannelConnected ? Theme.Palette.success : Theme.Palette.warning)
                .frame(width: 9, height: 9)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        appState.isChannelConnected ? "Verbunden" : "Verbindung …"
    }
}

/// Gemeinsamer Content-Header der beiden Start-Ansichten: App-Name + Server-
/// Host links, Verbindungsstatus + optionale Aktionen (z. B. „+"/Archiv) +
/// Konto-Menü rechts — alles in einer Zeile.
struct AppHeader<Actions: View>: View {
    @Environment(AppState.self) private var appState
    private let actions: Actions

    init(@ViewBuilder actions: () -> Actions) {
        self.actions = actions()
    }

    init() where Actions == EmptyView {
        self.actions = EmptyView()
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("MD-Connect")
                    .font(Theme.Typography.headline)
                Text(appState.session.serverURL?.host ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ConnectionLabel()
            actions
            AccountMenu()
        }
        .zIndex(2)
    }
}
