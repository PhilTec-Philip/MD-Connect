import SwiftUI

/// Detailed view of a single unit with its members and status actions.
struct UnitDetailView: View {
    @Environment(AppState.self) private var appState

    let unitID: Int64

    @State private var unit: Resources_Centrum_Units_Unit?
    @State private var activity: [Resources_Centrum_Units_UnitStatus] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedStatus: Resources_Centrum_Units_StatusUnit = .available
    @State private var showStatusPicker = false

    var body: some View {
        Group {
            if let unit {
                content(unit)
            } else if let errorMessage {
                EmptyStateView(
                    "exclamationmark.triangle",
                    color: Theme.Palette.danger,
                    title: "Laden fehlgeschlagen",
                    message: errorMessage,
                    actionTitle: "Erneut versuchen"
                ) {
                    Task { await load() }
                }
            } else {
                ScrollView {
                    SkeletonDetailView()
                }
            }
        }
        .navigationTitle(unit?.name ?? "Einheit")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .sheet(isPresented: $showStatusPicker) {
            statusSheet
        }
    }

    private func content(_ unit: Resources_Centrum_Units_Unit) -> some View {
        List {
            detailHeroSection(DetailHero(
                gradient: FiveNetModule.centrum.gradient,
                icon: "building.2.fill",
                title: unit.name,
                subtitle: unitJobLine(unit),
                badges: unitBadges(unit)
            ))

            Section("Details") {
                row("Einheiten-Nr.", "\(unit.id)")
                row("Beschreibung", unit.description_p.isEmpty ? "k.A." : unit.description_p)
                if unit.hasStatus {
                    row("Letzte Aktualisierung", formatTimestamp(unit.status.createdAt))
                    row("Code", orNA(unit.status.code))
                    row("Grund", orNA(unit.status.reason))
                }
                row("Standort", unit.homePostal.isEmpty ? "k.A." : unit.homePostal)
                if unit.hasStatus && !unit.status.postal.isEmpty {
                    row("Aktueller Standort", unit.status.postal)
                }
            }

            Section {
                Button {
                    selectedStatus = unit.status.status == .available ? .busy : .available
                    showStatusPicker = true
                } label: {
                    Label("Status ändern", systemImage: "arrow.left.arrow.right")
                }
            } footer: {
                Text("Setzt den Status der Einheit (z. B. verfügbar, Pause, beschäftigt).")
            }

            if unit.id == appState.ownUnitID {
                Section {
                    Button(role: .destructive) {
                        Task { await leaveUnit(unit) }
                    } label: {
                        Label("Einheit verlassen", systemImage: "person.crop.circle.badge.minus")
                    }
                } footer: {
                    Text("Entfernt dich aus dieser Einheit.")
                }
            }

            Section("Mitglieder (\(unit.users.count))") {
                if unit.users.isEmpty {
                    Text("Keine Mitglieder zugewiesen.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(unit.users, id: \.userID) { member in
                        NavigationLink(value: ColleagueRoute(userID: member.userID)) {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(memberName(member))
                                    .font(.subheadline.weight(.medium))
                                let job = memberJobLine(member)
                                if !job.isEmpty {
                                    Text(job)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section("Aktivitäts-Feed") {
                if activity.isEmpty {
                    Text("Keine Aktivität vorhanden.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activity, id: \.id) { entry in
                        ActivityRow(
                            icon: entry.feedIcon,
                            title: entry.feedLabel,
                            subtitle: activitySubtitle(entry)
                        )
                    }
                }
            }
        }
    }

    private func unitJobLine(_ unit: Resources_Centrum_Units_Unit) -> String {
        if !unit.jobLabel.isEmpty { return unit.jobLabel }
        return "Einheit #\(unit.id)"
    }

    private func unitBadges(_ unit: Resources_Centrum_Units_Unit) -> [String] {
        var result: [String] = []
        if !unit.initials.isEmpty {
            result.append(unit.initials)
        }
        if unit.hasStatus {
            result.append(unit.status.status.label)
        }
        return result
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func leaveUnit(_ unit: Resources_Centrum_Units_Unit) async {
        await appState.leaveUnit(unit.id)
        await load()
    }

    private func memberName(_ member: Resources_Centrum_Units_UnitAssignment) -> String {
        let user = member.user
        let name = [user.firstname, user.lastname].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "Benutzer #\(member.userID)" : name
    }

    private func memberJobLine(_ member: Resources_Centrum_Units_UnitAssignment) -> String {
        let user = member.user
        var parts: [String] = []
        if !user.jobLabel.isEmpty { parts.append(user.jobLabel) }
        if !user.jobGradeLabel.isEmpty { parts.append(user.jobGradeLabel) }
        return parts.joined(separator: " · ")
    }

    private func activitySubtitle(_ entry: Resources_Centrum_Units_UnitStatus) -> String {
        var parts: [String] = []
        let user = colleagueName(entry.user)
        if !user.isEmpty { parts.append(user) }
        if entry.hasCode, !entry.code.isEmpty { parts.append("Code: \(entry.code)") }
        if entry.hasReason, !entry.reason.isEmpty { parts.append(entry.reason) }
        parts.append(formatRelative(entry.createdAt))
        return parts.joined(separator: " · ")
    }

    private var statusSheet: some View {
        NavigationStack {
            Form {
                Picker("Status", selection: $selectedStatus) {
                    ForEach(Self.statusOptions, id: \.self) { status in
                        Text(status.label).tag(status)
                    }
                }
            }
            .navigationTitle("Status ändern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { showStatusPicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        Task {
                            await appState.updateUnitStatus(unitID, status: selectedStatus)
                            showStatusPicker = false
                            await load()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private static var statusOptions: [Resources_Centrum_Units_StatusUnit] {
        [.available, .onBreak, .busy, .unavailable]
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.listUnits()
            unit = response.units.first { $0.id == unitID }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        if let unit, unit.hasStatus {
            do {
                let response = try await client.listUnitActivity(unitID: unitID)
                activity = response.activity
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        UnitDetailView(unitID: 1)
            .environment(AppState())
    }
}
