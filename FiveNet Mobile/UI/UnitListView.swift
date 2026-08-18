import SwiftUI

/// Units: list of all units ("Einheiten"), grouped by status (verfügbar,
/// beschäftigt, Pause, nicht verfügbar). Unoccupied units are hidden.
struct UnitListView: View {
    @Environment(AppState.self) private var appState

    private struct StatusSection: Identifiable {
        let title: String
        let status: Resources_Centrum_Units_StatusUnit
        let units: [Resources_Centrum_Units_Unit]

        var id: String { title }
    }

    private var sections: [StatusSection] {
        let occupied = appState.units.filter { !$0.users.isEmpty }
        let order: [(String, Resources_Centrum_Units_StatusUnit)] = [
            ("Verfügbar", .available),
            ("Beschäftigt", .busy),
            ("Pause", .onBreak),
            ("Nicht verfügbar", .unavailable),
        ]
        var result: [StatusSection] = []
        for (title, status) in order {
            let units = occupied.filter { $0.status.status == status }
            if !units.isEmpty {
                result.append(StatusSection(title: title, status: status, units: units))
            }
        }
        let unknown = occupied.filter {
            $0.status.status != .available && $0.status.status != .busy
                && $0.status.status != .onBreak && $0.status.status != .unavailable
        }
        if !unknown.isEmpty {
            result.append(StatusSection(title: "Unbekannt", status: .unspecified, units: unknown))
        }
        return result
    }

    var body: some View {
        Group {
            List {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.units) { unit in
                            NavigationLink(value: UnitRoute(unitID: unit.id)) {
                                UnitRow(unit: unit)
                            }
                            .buttonStyle(.plain)
                            .navigationLinkIndicatorVisibility(.hidden)
                            .cardRow()
                        }
                    }
                }
            }
            .cardListStyle()
            .contentMargins(.top, Theme.Spacing.xl, for: .scrollContent)
            .overlay {
                if sections.isEmpty {
                    EmptyStateView(
                        "building.2",
                        color: Theme.Palette.accent,
                        title: "Keine Einheiten",
                        message: "Es wurden keine besetzten Einheiten gefunden."
                    )
                }
            }
            .refreshable {
                await appState.loadUnits()
            }
        }
    }
}

private struct UnitRow: View {
    let unit: Resources_Centrum_Units_Unit

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(unit.status.status.color)
                .frame(width: 5)
                .padding(.vertical, Theme.Spacing.md)

            HStack(spacing: Theme.Spacing.lg) {
                UnitBadgeCircle(color: unitColor, content: "\(unit.users.count)")
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
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
                    .padding(.trailing, Theme.Spacing.md)
            }
            .padding(.leading, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.xs)

            Spacer(minLength: 0)
            CardChevron()
        }
        .padding(Theme.Spacing.md)
        .padding(.trailing, Theme.Spacing.sm)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private var unitColor: Color {
        Color(hex: unit.color) ?? .accentColor
    }
}
