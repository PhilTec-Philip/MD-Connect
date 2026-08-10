import SwiftUI

/// Effiziente Start-Ansicht ("Quick-Ansicht"): Alle nötigen Infos und
/// Aktionen direkt im Overview, ohne Menü-Navigation — Einsätze erstellen
/// via „+“ in der Toolbar, offene Einsätze, die eigene Einheit samt Status
/// sowie der eigene Einsatz samt Status-Aktionen inline. Umschaltbar über das
/// Konto-Menü („Ansicht wechseln").
struct QuickView: View {
    @Environment(AppState.self) private var appState

    private enum QuickRoute: Hashable {
        case module(FiveNetModule)
        case unit(Int64)
        case dispatch(Int64)
        case dispatches
        case archive
        case units
    }

    private static let closedStatuses: Set<Resources_Centrum_Dispatches_StatusDispatch> = [
        .completed, .cancelled, .archived, .deleted,
    ]

    private static let shownStatuses: [Resources_Centrum_Dispatches_StatusDispatch] = [
        .new, .unassigned, .updated, .unitAssigned, .unitUnassigned,
        .unitAccepted, .unitDeclined, .enRoute, .onScene, .needAssistance,
    ]

    @State private var route: QuickRoute?
    @State private var showCreateDispatchSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    AppHeader {
                        Button {
                            showCreateDispatchSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Theme.Palette.accent)
                                .accessibilityLabel("Einsatz erstellen")
                        }
                        .buttonStyle(.plain)

                        Button {
                            route = .archive
                        } label: {
                            Image(systemName: "archivebox")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Theme.Palette.accent)
                                .accessibilityLabel("Einsatz-Archiv")
                        }
                        .buttonStyle(.plain)
                    }

                    unitSection
                    ownDispatchSection
                    openDispatchesSection
                    moduleStrip
                }
                .padding(Theme.Spacing.xl)
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationDestination(item: $route) { route in
                switch route {
                case .module(let module):
                    moduleRootView(module)
                case .unit(let id):
                    UnitDetailView(unitID: id)
                case .dispatch(let id):
                    DispatchDetailView(dispatchID: id)
                case .dispatches:
                    QuickDispatchesView()
                case .archive:
                    QuickArchiveView()
                case .units:
                    QuickUnitsView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PendingAlarmBell()
                }
            }
            .sheet(isPresented: $showCreateDispatchSheet) {
                CreateDispatchSheet()
                    .environment(appState)
            }
            .task {
                await appState.loadCentrum()
                await appState.startCentrumStream()
            }
            .refreshable {
                await appState.loadCentrum()
            }
        }
        .fullScreenCover(item: alarmBinding) { alarm in
            DispatchAlarmView(alarm: alarm)
                .environment(appState)
        }
    }

    // MARK: - Deine Einheit

    private var unitSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader("Deine Einheit")
                .padding(.horizontal, Theme.Spacing.xs)

            if let unit = appState.ownUnit {
                unitCard(unit)
                unitStatusActions(unit)
            } else if appState.ownUnitID != nil {
                SectionCard {
                    Text("Einheit wird geladen …")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                SectionCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text("Du bist keiner Einheit zugewiesen.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            route = .units
                        } label: {
                            Label("Einheiten ansehen & beitreten", systemImage: "person.2.badge.plus")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.sm)
                                .background(
                                    Theme.Palette.accent.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func unitCard(_ unit: Resources_Centrum_Units_Unit) -> some View {
        Button {
            route = .unit(unit.id)
        } label: {
            HStack(spacing: Theme.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(unitColor(unit).opacity(0.2))
                        .frame(width: 44, height: 44)
                    Text(unit.initials)
                        .font(.headline.bold())
                        .foregroundStyle(unitColor(unit))
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("\(unit.initials) – \(unit.name)")
                        .font(.headline)
                    if !unit.jobLabel.isEmpty {
                        Text(unit.jobLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(unit.status.status.label)
                    .font(.caption.bold())
                    .foregroundStyle(unit.status.status.color)
                CardChevron()
            }
            .padding(Theme.Spacing.xl)
            .background(
                Theme.Palette.surface,
                in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
            )
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func unitStatusActions(_ unit: Resources_Centrum_Units_Unit) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Einheiten-Status setzen")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(Self.unitStatusOptions, id: \.self) { status in
                        let isActive = unit.status.status == status
                        Button {
                            Task { await appState.updateUnitStatus(unit.id, status: status) }
                        } label: {
                            Text(status.label)
                                .font(.caption.bold())
                                .foregroundStyle(isActive ? .white : status.color)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.sm)
                                .background(
                                    isActive ? status.color : status.color.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Divider()
                Button(role: .destructive) {
                    Task { await appState.leaveUnit(unit.id) }
                } label: {
                    Label("Einheit verlassen", systemImage: "person.crop.circle.badge.minus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(
                            Theme.Palette.danger.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private static var unitStatusOptions: [Resources_Centrum_Units_StatusUnit] {
        [.available, .busy, .onBreak, .unavailable]
    }

    private func unitColor(_ unit: Resources_Centrum_Units_Unit) -> Color {
        Color(hex: unit.color) ?? .accentColor
    }

    // MARK: - Dein Einsatz

    private var ownDispatchSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader("Dein Einsatz")
                .padding(.horizontal, Theme.Spacing.xs)

            if ownDispatches.isEmpty {
                SectionCard {
                    Text("Kein aktiver Einsatz für deine Einheit.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(ownDispatches) { dispatch in
                    dispatchCard(dispatch, own: true)
                }
            }
        }
    }

    /// Dispatches currently assigned to the character's own unit that have been
    /// accepted (same filter as `MyDutyView`).
    private var ownDispatches: [Resources_Centrum_Dispatches_Dispatch] {
        guard let ownUnitID = appState.ownUnitID else { return [] }
        return appState.dispatches.filter { dispatch in
            !Self.closedStatuses.contains(dispatch.status.status)
                && !appState.pendingAlarmDispatchIDs.contains(dispatch.id)
                && dispatch.units.contains { $0.unitID == ownUnitID }
        }
    }

    // MARK: - Offene Einsätze

    private var openDispatchesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader("Offene Einsätze")
                .padding(.horizontal, Theme.Spacing.xs)

            if openDispatches.isEmpty {
                SectionCard {
                    Text("Aktuell sind keine offenen Einsätze vorhanden.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(openDispatches.prefix(Self.maxOpenShown)) { dispatch in
                    dispatchCard(dispatch, own: false)
                }
                if openDispatches.count > Self.maxOpenShown {
                    Button {
                        route = .dispatches
                    } label: {
                        Label("Alle \(openDispatches.count) Einsätze anzeigen", systemImage: "list.bullet")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(
                                Theme.Palette.surface,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var openDispatches: [Resources_Centrum_Dispatches_Dispatch] {
        appState.dispatches.filter { dispatch in
            Self.shownStatuses.contains(dispatch.status.status)
                && !Self.closedStatuses.contains(dispatch.status.status)
        }
    }

    private static let maxOpenShown = 6

    // MARK: - Dispatch-Karte

    private func dispatchCard(_ dispatch: Resources_Centrum_Dispatches_Dispatch, own: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Button {
                route = .dispatch(dispatch.id)
            } label: {
                HStack(spacing: Theme.Spacing.lg) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(dispatch.status.status.color)
                        .frame(width: 5)
                        .frame(maxHeight: .infinity)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.sm) {
                            Text(formatDispatchID(dispatch.id))
                                .font(.headline)
                            Spacer()
                            Label(dispatch.status.status.label, systemImage: "circle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(dispatch.status.status.color)
                        }
                        if let message = dispatchMessageText(dispatch) {
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if !own {
                            HStack(spacing: Theme.Spacing.lg) {
                                if !dispatch.postal.isEmpty {
                                    Label(dispatch.postal, systemImage: "mappin")
                                }
                                if !dispatch.units.isEmpty {
                                    Label("\(dispatch.units.count) \(dispatch.units.count == 1 ? "Einheit" : "Einheiten")", systemImage: "building.2")
                                }
                                Spacer()
                                Text(formatRelative(dispatch.createdAt))
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.caption)
                        }
                    }
                    Spacer(minLength: 0)
                    CardChevron()
                }
            }
            .buttonStyle(.plain)

            if own {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(Self.dispatchStatusOptions) { option in
                        let isActive = dispatch.status.status == option.status
                        Button {
                            Task { await appState.updateDispatchStatus(dispatch.id, status: option.status) }
                        } label: {
                            Label(option.title, systemImage: option.icon)
                                .font(.caption.bold())
                                .foregroundStyle(isActive ? .white : option.tint)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.sm)
                                .background(
                                    isActive ? option.tint : option.tint.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private struct DispatchStatusOption: Identifiable {
        let status: Resources_Centrum_Dispatches_StatusDispatch
        let title: String
        let icon: String
        let tint: Color

        var id: Resources_Centrum_Dispatches_StatusDispatch { status }
    }

    private static var dispatchStatusOptions: [DispatchStatusOption] {
        [
            DispatchStatusOption(status: .enRoute, title: "Auf dem Weg", icon: "arrow.right.circle.fill", tint: .yellow),
            DispatchStatusOption(status: .onScene, title: "Vor Ort", icon: "location.circle.fill", tint: .green),
            DispatchStatusOption(status: .needAssistance, title: "Verstärkung", icon: "exclamationmark.triangle.fill", tint: .red),
            DispatchStatusOption(status: .completed, title: "Erledigt", icon: "checkmark.circle.fill", tint: .blue),
        ]
    }

    // MARK: - Module

    private var moduleStrip: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader("Module")
                .padding(.horizontal, Theme.Spacing.xs)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.lg) {
                    ForEach(appState.accessibleModules) { module in
                        Button {
                            route = .module(module)
                        } label: {
                            QuickAccessTile(module, width: 120, showsBackground: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.xs)
            }
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
}

/// Einsätze direkt mit eigenem „+“-Toolbar-Button (ohne den Umweg über die
/// Leitstellen-Tabs), als Wrapper um `DispatchListView`.
private struct QuickDispatchesView: View {
    @Environment(AppState.self) private var appState
    @State private var showCreateDispatchSheet = false

    var body: some View {
        DispatchListView()
            .navigationTitle("Einsätze")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateDispatchSheet = true
                    } label: {
                        Label("Einsatz erstellen", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateDispatchSheet) {
                CreateDispatchSheet()
                    .environment(appState)
            }
    }
}

/// Einheiten mit zweitem Tab: „Einheiten" (Status-Liste) und „Beitreten"
/// (Kacheln mit Beitreten/Verlassen, wie im LiveMap-„Einheiten"-Tab).
private struct QuickUnitsView: View {
    @Environment(AppState.self) private var appState

    private enum UnitsTab: String, CaseIterable, Identifiable {
        case list = "Einheiten"
        case join = "Beitreten"

        var id: String { rawValue }
    }

    @State private var tab: UnitsTab = .list

    var body: some View {
        VStack(spacing: 0) {
            PillTabBar(tabs: UnitsTab.allCases, selection: $tab) { $0.rawValue }

            Group {
                switch tab {
                case .list:
                    UnitListView()
                case .join:
                    joinGrid
                }
            }
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle("Einheiten")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var joinGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                ForEach(sortedUnits) { unit in
                    UnitTileView(unit: unit)
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .overlay {
            if appState.units.isEmpty {
                EmptyStateView(
                    "building.2",
                    color: Theme.Palette.accent,
                    title: "Keine Einheiten",
                    message: "Es sind keine Einheiten verfügbar."
                )
            }
        }
    }

    /// All units, favorites first.
    private var sortedUnits: [Resources_Centrum_Units_Unit] {
        let favorites = appState.favoriteUnitIDs
        return appState.units.sorted { lhs, rhs in
            let l = favorites.contains(lhs.id)
            let r = favorites.contains(rhs.id)
            if l != r { return l }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

/// Einsatz-Archiv mit Navigationstitel, als Wrapper um `ArchiveView`.
private struct QuickArchiveView: View {
    var body: some View {
        ArchiveView()
            .navigationTitle("Archiv")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    QuickView()
        .environment(AppState())
}
