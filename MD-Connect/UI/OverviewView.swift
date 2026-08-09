import SwiftUI

/// Main screen after authentication: shows the resolved character and the
/// grid of accessible modules.
struct OverviewView: View {
    @Environment(AppState.self) private var appState

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Spacing.xl),
        GridItem(.flexible(), spacing: Theme.Spacing.xl),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    header

                    if let name = characterName {
                        profileHero(name: name, job: jobLine)
                    }

                    let quick = quickModules
                    if !quick.isEmpty {
                        SectionHeader("Schnellzugriff")
                            .padding(.horizontal, Theme.Spacing.xs)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Spacing.lg) {
                                ForEach(quick) { module in
                                    NavigationLink(value: module) {
                                        QuickAccessTile(module: module)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.xs)
                        }
                    }

                    if appState.character == nil {
                        skeletonGrid
                    } else {
                        SectionHeader("Deine Module")
                            .padding(.horizontal, Theme.Spacing.xs)

                        LazyVGrid(columns: columns, spacing: Theme.Spacing.xl) {
                            ForEach(appState.accessibleModules) { module in
                                NavigationLink(value: module) {
                                    ModuleCard(module: module)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.xl)
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationDestination(for: FiveNetModule.self) { module in
                switch module {
                case .centrum:
                    CentrumView()
                case .livemap:
                    LiveMapView()
                case .wiki:
                    WikiView()
                case .citizens:
                    CitizensListView()
                case .vehicles:
                    VehiclesListView()
                case .documents:
                    DocumentsListView()
                case .jobs:
                    JobsView()
                case .qualifications:
                    QualificationsView()
                case .calendar:
                    CalendarView()
                case .mailer:
                    MailView()
                case .settings:
                    SettingsView()
                }
            }
            .navigationDestination(for: CitizenRoute.self) { route in
                CitizenDetailView(userID: route.userID)
            }
            .navigationDestination(for: UnitRoute.self) { route in
                UnitDetailView(unitID: route.unitID)
            }
            .navigationDestination(for: ColleagueRoute.self) { route in
                ColleagueDetailView(userID: route.userID)
            }
            .navigationDestination(for: ConductRoute.self) { route in
                ConductEntryDetailView(entryID: route.entryID)
            }
            .navigationDestination(for: QualificationRoute.self) { route in
                QualificationDetailView(qualificationID: route.qualificationID)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PendingAlarmBell()
                }
            }
        }
        .fullScreenCover(item: alarmBinding) { alarm in
            DispatchAlarmView(alarm: alarm)
                .environment(appState)
        }
    }

    /// Konten-Menü (drei Punkte) oben rechts: Charakter wechseln, Server
    /// wechseln, Abmelden. Als Toolbar-Item, damit es zuverlässig reagiert.
    private var accountMenu: some View {
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
            Button(role: .destructive) {
                Task { await appState.logout() }
            } label: {
                Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
    }

    /// Verbindungsstatus mit Text direkt neben dem Punkt — als Teil der
    /// Content-Header-Zeile neben „FiveNet", damit Status und Menü in einer
    /// Zeile liegen (kein Kasten in der Navigationsleiste mehr).
    private var connectionLabel: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(appState.isChannelConnected ? Theme.Palette.success : Theme.Palette.warning)
                .frame(width: 9, height: 9)
            Text(appState.isChannelConnected ? "Verbunden" : "Verbindung …")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Binding to the current dispatch alarm, if any. `fullScreenCover(item:)`
    /// dismisses it by setting the binding to `nil`.
    private var alarmBinding: Binding<DispatchAlarm?> {
        Binding(
            get: { appState.activeAlarm },
            set: { newValue in
                if newValue == nil {
                    appState.dismissAlarm()
                }
            }
        )
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("MD-Connect")
                    .font(Theme.Typography.headline)
                Text(appState.session.serverURL?.host ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            connectionLabel
            accountMenu
        }
        .zIndex(2)
    }

    /// Schnellzugriff-Module in festgelegter Reihenfolge, gefiltert auf die
    /// tatsächlich zugänglichen.
    private var quickModules: [FiveNetModule] {
        FiveNetModule.quickAccessOrder.filter { appState.accessibleModules.contains($0) }
    }

    /// Profilkarte mit Avatar-Tile, Begrüßung und aktueller Funktion.
    private func profileHero(name: String, job: String?) -> some View {
        HStack(spacing: Theme.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 68, height: 68)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("WILLKOMMEN")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.8))
                Text(name)
                    .font(Theme.Typography.title2)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let job, !job.isEmpty {
                    Text(job)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Theme.Palette.accent, Color(red: 0.10, green: 0.29, blue: 0.69)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 140, height: 140)
                .offset(x: 40, y: -60)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: 100, height: 100)
                .offset(x: -30, y: 50)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .shadow(color: Theme.Palette.accent.opacity(0.25), radius: 14, y: 6)
    }

    private var skeletonGrid: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.xl) {
            ForEach(0..<6, id: \.self) { _ in
                SkeletonBlock()
            }
        }
    }

    private var characterName: String? {
        guard let character = appState.character else { return nil }
        let name = [character.firstname, character.lastname]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? nil : name
    }

    private var jobLine: String? {
        guard let character = appState.character else { return nil }
        var parts: [String] = []
        if !character.jobLabel.isEmpty { parts.append(character.jobLabel) }
        if !character.jobGradeLabel.isEmpty { parts.append(character.jobGradeLabel) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Kompakte Schnellzugriffs-Kachel für den horizontalen Bereich der Startseite:
/// Verlaufs-Icon-Kachel + Titel.
private struct QuickAccessTile: View {
    let module: FiveNetModule

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(LinearGradient(colors: module.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: module.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)
            .shadow(color: module.tint.opacity(0.35), radius: 6, y: 3)

            Text(module.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(width: 68)
    }
}

private struct ModuleCard: View {
    let module: FiveNetModule

    var body: some View {
        HStack(spacing: Theme.Spacing.xl) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(LinearGradient(colors: module.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: module.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(module.title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(.primary)
                Text(module.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }
}

#Preview {
    OverviewView()
        .environment(AppState())
}
