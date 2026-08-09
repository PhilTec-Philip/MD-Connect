import SwiftUI

/// Detailed view of a single dispatch with status actions and unit assignment.
struct DispatchDetailView: View {
    @Environment(AppState.self) private var appState

    let dispatchID: Int64

    @State private var dispatch: Resources_Centrum_Dispatches_Dispatch?
    @State private var activity: [Resources_Centrum_Dispatches_DispatchStatus] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedStatus: Resources_Centrum_Dispatches_StatusDispatch = .unspecified
    @State private var showStatusPicker = false
    @State private var reason = ""
    @State private var isSaving = false
    @State private var stagedUnitIDs: Set<Int64> = []

    /// The currently-assigned unit ids of the loaded dispatch.
    private var currentUnitIDs: Set<Int64> {
        Set(dispatch?.units.map(\.unitID) ?? [])
    }

    /// Whether the staged assignment differs from the loaded dispatch.
    private var hasPendingAssignment: Bool {
        stagedUnitIDs != currentUnitIDs
    }

    var body: some View {
        Group {
            if let dispatch {
                content(dispatch)
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
        .navigationTitle(dispatch.map { formatDispatchID($0.id) } ?? "Einsatz")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .sheet(isPresented: $showStatusPicker) {
            statusSheet
        }
    }

    private func content(_ dispatch: Resources_Centrum_Dispatches_Dispatch) -> some View {
        List {
            detailHeroSection(DetailHero(
                gradient: FiveNetModule.centrum.gradient,
                icon: "megaphone.fill",
                title: formatDispatchID(dispatch.id),
                subtitle: dispatchMessageText(dispatch),
                badges: dispatchBadges(dispatch)
            ))

            Section("Details") {
                row("Gesendet am", formatTimestamp(dispatch.createdAt))
                row("Gesendet von", senderName(dispatch))
                if !dispatch.jobs.jobs.isEmpty {
                    row("Zuständig", dispatch.jobs.jobs.map(\.label).joined(separator: ", "))
                }
                row("Standort", locationLabel(dispatch))
                row("Beschreibung", dispatch.description_p.isEmpty ? "k.A." : dispatch.description_p)
                let attributes = dispatch.attributes.list.map(\.label).filter { $0 != "–" }.joined(separator: ", ")
                row("Attribute", attributes.isEmpty ? "k.A." : attributes)
            }

            if !dispatch.units.isEmpty {
                Section("Zugewiesene Einheiten") {
                    ForEach(dispatch.units, id: \.unitID) { assignment in
                        NavigationLink(value: UnitRoute(unitID: assignment.unitID)) {
                            UnitBubbleRow(unit: assignment.unit)
                        }
                    }
                }
            }

            Section("Letzte Aktualisierung") {
                if dispatch.hasStatus {
                    row("Aktualisiert", formatTimestamp(dispatch.status.createdAt))
                    row("Status", dispatch.status.status.label)
                    row("Code", orNA(dispatch.status.code))
                    row("Grund", orNA(dispatch.status.reason))
                } else {
                    Text("Keine Statusänderung vorhanden.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    showStatusPicker = true
                } label: {
                    Label("Status ändern", systemImage: "arrow.left.arrow.right")
                }

                Button {
                    Task { await take(.accepted) }
                } label: {
                    Label("Übernehmen", systemImage: "checkmark.circle")
                }
                .disabled(isSaving)

                Button(role: .destructive) {
                    Task { await take(.declined) }
                } label: {
                    Label("Ablehnen", systemImage: "xmark.circle")
                }
                .disabled(isSaving)
            } footer: {
                Text("Übernehmen/Ablehnen beantwortet eine dir zugewiesene Einheit.")
            }

            Section("Einheiten zuweisen") {
                let assignable = appState.units.filter { !$0.users.isEmpty }
                if assignable.isEmpty {
                    Text("Keine besetzten Einheiten vorhanden.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: Theme.Spacing.lg)], spacing: Theme.Spacing.lg) {
                        ForEach(assignable) { unit in
                            Button {
                                toggleUnit(unit.id)
                            } label: {
                                UnitTile(
                                    unit: unit,
                                    isAssigned: stagedUnitIDs.contains(unit.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)

                    Button {
                        Task { await confirmAssignment() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label(
                                hasPendingAssignment ? "Änderungen übernehmen" : "Keine Änderungen",
                                systemImage: "checkmark.circle"
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasPendingAssignment || isSaving)
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

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func creatorName(_ dispatch: Resources_Centrum_Dispatches_Dispatch) -> String? {
        let user = dispatch.creator
        let name = [user.firstname, user.lastname].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? nil : name
    }

    private func senderName(_ dispatch: Resources_Centrum_Dispatches_Dispatch) -> String {
        if dispatch.anon {
            return "Anonym"
        }
        return creatorName(dispatch) ?? "Unbekannt"
    }

    private func dispatchBadges(_ dispatch: Resources_Centrum_Dispatches_Dispatch) -> [String] {
        var result: [String] = []
        if dispatch.hasStatus {
            result.append(dispatch.status.status.label)
        }
        if !dispatch.postal.isEmpty {
            result.append(dispatch.postal)
        }
        return result
    }

    private func locationLabel(_ dispatch: Resources_Centrum_Dispatches_Dispatch) -> String {
        var parts: [String] = []
        if !dispatch.postal.isEmpty { parts.append(dispatch.postal) }
        if dispatch.x != 0 || dispatch.y != 0 {
            parts.append("(\(Int(dispatch.x)), \(Int(dispatch.y)))")
        }
        return parts.isEmpty ? "k.A." : parts.joined(separator: " · ")
    }

    private func activitySubtitle(_ entry: Resources_Centrum_Dispatches_DispatchStatus) -> String {
        var parts: [String] = []
        let user = colleagueName(entry.user)
        if !user.isEmpty { parts.append(user) }
        if !entry.unit.name.isEmpty { parts.append(entry.unit.name) }
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
                TextField("Grund (optional)", text: $reason)
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
                            await appState.updateDispatchStatus(dispatchID, status: selectedStatus, reason: reason)
                            showStatusPicker = false
                            await load()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private static var statusOptions: [Resources_Centrum_Dispatches_StatusDispatch] {
        [.new, .unassigned, .updated, .enRoute, .onScene, .needAssistance, .completed, .cancelled]
    }

    private func toggleUnit(_ unitID: Int64) {
        if stagedUnitIDs.contains(unitID) {
            stagedUnitIDs.remove(unitID)
        } else {
            stagedUnitIDs.insert(unitID)
        }
    }

    private func confirmAssignment() async {
        guard dispatch != nil else { return }
        isSaving = true
        defer { isSaving = false }
        let current = currentUnitIDs
        let toAdd = Array(stagedUnitIDs.subtracting(current))
        let toRemove = Array(current.subtracting(stagedUnitIDs))
        guard !toAdd.isEmpty || !toRemove.isEmpty else { return }
        await appState.assignDispatch(dispatchID, toAdd: toAdd, toRemove: toRemove)
        await load()
        stagedUnitIDs = currentUnitIDs
    }

    private func take(_ resp: Resources_Centrum_Dispatches_TakeDispatchResp) async {
        isSaving = true
        defer { isSaving = false }
        await appState.takeDispatch(dispatchID, resp: resp)
        await load()
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            dispatch = try await client.getDispatch(id: dispatchID)
            errorMessage = nil
            stagedUnitIDs = Set(dispatch?.units.map(\.unitID) ?? [])
        } catch {
            errorMessage = error.localizedDescription
        }
        do {
            let response = try await client.listDispatchActivity(dispatchID: dispatchID)
            activity = response.activity
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A compact unit row showing the unit color bubble, its alias and its full name.
/// Used for assigned units and the assignment checklist.
private struct UnitBubbleRow: View {
    let unit: Resources_Centrum_Units_Unit

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(unitColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                Text("\(unit.users.count)")
                    .font(.subheadline.bold())
                    .foregroundStyle(unitColor)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("\(unit.initials) – \(unit.name)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                if !unit.jobLabel.isEmpty {
                    Text(unit.jobLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var unitColor: Color {
        Color(hex: unit.color) ?? .accentColor
    }
}

/// A selectable tile for the assignment grid: color bubble with member count,
/// alias + name and an assignment checkbox.
private struct UnitTile: View {
    let unit: Resources_Centrum_Units_Unit
    let isAssigned: Bool

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                ZStack {
                    Circle()
                        .fill(unitColor.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Text("\(unit.users.count)")
                        .font(.caption.bold())
                        .foregroundStyle(unitColor)
                }
                Spacer()
                Image(systemName: isAssigned ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isAssigned ? Theme.Palette.accent : Color(.tertiaryLabel))
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("\(unit.initials) – \(unit.name)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !unit.jobLabel.isEmpty {
                    Text(unit.jobLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(
            isAssigned ? Theme.Palette.accent.opacity(0.1) : Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(isAssigned ? Theme.Palette.accent.opacity(0.6) : Color(.separator), lineWidth: 1)
        }
    }

    private var unitColor: Color {
        Color(hex: unit.color) ?? .accentColor
    }
}

#Preview {
    NavigationStack {
        DispatchDetailView(dispatchID: 1)
            .environment(AppState())
    }
}
