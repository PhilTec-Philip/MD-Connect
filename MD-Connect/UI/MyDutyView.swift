import SwiftUI

/// "Meine Einheit": self-management for the active character — the current unit
/// (join, leave, unit status) and the assigned dispatch (status quick actions).
struct MyDutyView: View {
    @Environment(AppState.self) private var appState

    private static let closedStatuses: Set<Resources_Centrum_Dispatches_StatusDispatch> = [
        .completed, .cancelled, .archived, .deleted,
    ]

    private var ownUnit: Resources_Centrum_Units_Unit? {
        appState.ownUnit
    }

    /// Dispatches currently assigned to the character's own unit that have been
    /// accepted. Dispatches still waiting for an accept/decline (pending alarm)
    /// are only shown via the alarm/bell, not as an active duty.
    private var ownDispatches: [Resources_Centrum_Dispatches_Dispatch] {
        guard let ownUnitID = appState.ownUnitID else { return [] }
        return appState.dispatches.filter { dispatch in
            !Self.closedStatuses.contains(dispatch.status.status)
                && !appState.pendingAlarmDispatchIDs.contains(dispatch.id)
                && dispatch.units.contains { $0.unitID == ownUnitID }
        }
    }

    @State private var selectedRoute: DutyRoute?

    var body: some View {
        List {
            unitSection
            dispatchSection
        }
        .cardListStyle()
        .navigationTitle("Meine Einheit")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedRoute) { route in
            switch route {
            case .unit(let id):
                UnitDetailView(unitID: id)
            case .dispatch(let id):
                DispatchDetailView(dispatchID: id)
            }
        }
        .refreshable {
            await appState.loadCentrum()
        }
    }

    private enum DutyRoute: Hashable {
        case unit(Int64)
        case dispatch(Int64)
    }

    // MARK: - Unit

    private var unitSection: some View {
        Section {
            if let unit = ownUnit {
                unitCard(unit)
                unitStatusActions(unit)
            } else if appState.ownUnitID != nil {
                SkeletonListRow()
                SectionCard {
                    Text("Einheit wird geladen …")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .cardRow()
            } else {
                SectionCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Du bist keiner Einheit zugewiesen.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Label("Tritt einer Einheit über die Einheiten-Liste auf der Karte bei, um Status-Updates und Einsatz-Meldungen zu empfangen.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .cardRow()
            }
        } header: {
            Text("Einheit")
        }
    }

    private func unitCard(_ unit: Resources_Centrum_Units_Unit) -> some View {
        Button {
            selectedRoute = .unit(unit.id)
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
        .cardRow()
    }

    private func unitStatusActions(_ unit: Resources_Centrum_Units_Unit) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Einheiten-Status setzen")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(Self.unitStatusOptions, id: \.self) { status in
                    let isActive = unit.status.status == status
                    Button {
                        Task { await setUnitStatus(status) }
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
                .padding(.vertical, Theme.Spacing.xs)
            Button(role: .destructive) {
                Task { await leaveUnit(unit) }
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
        .padding(Theme.Spacing.xl)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        .cardRow()
    }

    private static var unitStatusOptions: [Resources_Centrum_Units_StatusUnit] {
        [.available, .busy, .onBreak, .unavailable]
    }

    private func unitColor(_ unit: Resources_Centrum_Units_Unit) -> Color {
        Color(hex: unit.color) ?? .accentColor
    }

    private func setUnitStatus(_ status: Resources_Centrum_Units_StatusUnit) async {
        guard let unit = ownUnit else { return }
        await appState.updateUnitStatus(unit.id, status: status)
    }

    private func leaveUnit(_ unit: Resources_Centrum_Units_Unit) async {
        await appState.leaveUnit(unit.id)
    }

    // MARK: - Dispatch

    private var dispatchSection: some View {
        Section {
            if ownDispatches.isEmpty {
                SectionCard {
                    Text("Kein aktiver Einsatz für deine Einheit.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .cardRow()
            } else {
                ForEach(ownDispatches) { dispatch in
                    dispatchRow(dispatch)
                }
            }
        } header: {
            Text("Dein Einsatz")
        }
    }

    private func dispatchRow(_ dispatch: Resources_Centrum_Dispatches_Dispatch) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Button {
                selectedRoute = .dispatch(dispatch.id)
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
                    }
                    Spacer(minLength: 0)
                    CardChevron()
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: Theme.Spacing.sm) {
                ForEach(Self.dispatchStatusOptions) { option in
                    let isActive = dispatch.status.status == option.status
                    Button {
                        Task { await setDispatchStatus(dispatch.id, option: option) }
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
        .padding(Theme.Spacing.xl)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        .cardRow()
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

    private func setDispatchStatus(_ dispatchID: Int64, option: DispatchStatusOption) async {
        await appState.updateDispatchStatus(dispatchID, status: option.status)
    }
}

#Preview {
    NavigationStack {
        MyDutyView()
            .environment(AppState())
    }
}
