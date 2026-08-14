import SwiftUI

/// Dispatches: list of active jobs ("Einsätze").
struct DispatchListView: View {
    @Environment(AppState.self) private var appState

    private static let shownStatuses: [Resources_Centrum_Dispatches_StatusDispatch] = [
        .new, .unassigned, .updated, .unitAssigned, .unitUnassigned,
        .unitAccepted, .unitDeclined, .enRoute, .onScene, .needAssistance,
    ]

    var body: some View {
        Group {
            List(appState.dispatches) { dispatch in
                NavigationLink(value: CentrumRoute.dispatch(dispatch.id)) {
                    DispatchRow(dispatch: dispatch)
                }
                .buttonStyle(.plain)
                .cardRow()
            }
            .cardListStyle()
            .contentMargins(.top, Theme.Spacing.xl, for: .scrollContent)
            .overlay {
                if appState.dispatches.isEmpty {
                    EmptyStateView(
                        "checkmark.circle",
                        color: Theme.Palette.accent,
                        title: "Keine Einsätze",
                        message: "Aktuell sind keine offenen Einsätze vorhanden."
                    )
                }
            }
            .refreshable {
                await appState.loadDispatches()
            }
        }
    }
}

/// Sheet to create a new dispatch ("Einsatz erstellen").
struct CreateDispatchSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var message = ""
    @State private var description = ""
    @State private var anon = false
    @State private var postal = ""
    @State private var resolvedPostal: PostalLocation?
    @State private var isLookingUpPostal = false
    @State private var postalLookupTask: Task<Void, Never>?
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nachricht", text: $message, axis: .vertical)
                        .lineLimit(2 ... 4)
                    TextField("Beschreibung", text: $description, axis: .vertical)
                        .lineLimit(2 ... 6)
                    Toggle("Anonym", isOn: $anon)
                } header: {
                    Text("Einsatzdetails")
                } footer: {
                    Text("Anonyme Einsätze werden ohne Absendernamen angezeigt.")
                }

                Section {
                    TextField("Postleitzahl", text: $postal)
                        .keyboardType(.numberPad)
                        .autocorrectionDisabled()
                } header: {
                    Text("Ort")
                } footer: {
                    locationPreview
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Palette.danger)
                    }
                }
            }
            .navigationTitle("Einsatz erstellen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Erstellt …" : "Erstellen") {
                        Task { await create() }
                    }
                    .disabled(!canSubmit)
                }
            }
            .interactiveDismissDisabled(isCreating)
            .onChange(of: postal) {
                postalLookupTask?.cancel()
                let query = postal.trimmingCharacters(in: .whitespacesAndNewlines)
                if query.isEmpty {
                    resolvedPostal = nil
                    isLookingUpPostal = false
                    return
                }
                isLookingUpPostal = true
                let task = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    await lookUpPostal(query)
                }
                postalLookupTask = task
            }
        }
    }

    @ViewBuilder
    private var locationPreview: some View {
        if isLookingUpPostal {
            Text("Ort wird gesucht …")
        } else if let resolvedPostal {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Label("Postleitzahl \(resolvedPostal.code) gefunden", systemImage: "mappin.circle.fill")
                    .foregroundStyle(Theme.Palette.success)
                MapPreviewView(worldPoint: CGPoint(x: resolvedPostal.x, y: resolvedPostal.y), baseURL: appState.client?.baseURL)
                Text("Position: \(Int(resolvedPostal.x)), \(Int(resolvedPostal.y))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if !postal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Label("Für diese Postleitzahl wurde kein Ort gefunden.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Palette.danger)
        }
    }

    private var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && resolvedPostal != nil
            && !isCreating
    }

    private func lookUpPostal(_ query: String) async {
        guard let baseURL = appState.client?.baseURL else {
            isLookingUpPostal = false
            resolvedPostal = nil
            return
        }
        let location = await PostalLoader.shared.location(for: query, baseURL: baseURL)
        resolvedPostal = location
        isLookingUpPostal = false
    }

    private func create() async {
        guard !isCreating else { return }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            let job = appState.dispatcherJob ?? appState.character?.job ?? ""
            _ = try await appState.createDispatch(
                job: job,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                anon: anon,
                x: resolvedPostal?.x ?? 0,
                y: resolvedPostal?.y ?? 0,
                postal: resolvedPostal?.code ?? ""
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A single postal code entry from the server's static `data/postals.json`.
struct PostalLocation: Decodable, Sendable {
    let x: Double
    let y: Double
    let code: String
}

/// Loads and caches the server's postal codes, mirroring the web's
/// `$fetch('/data/postals.json')` behavior.
actor PostalLoader {
    static let shared = PostalLoader()

    private var cache: [String: PostalLocation]?

    func location(for code: String, baseURL: URL) async -> PostalLocation? {
        let all = await loadAll(baseURL: baseURL)
        return all?[code]
    }

    private func loadAll(baseURL: URL) async -> [String: PostalLocation]? {
        if let cache { return cache }

        let url = baseURL.appendingPathComponent("data/postals.json")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let entries = try JSONDecoder().decode([PostalLocation].self, from: data)
            let byCode = Dictionary(uniqueKeysWithValues: entries.map { ($0.code, $0) })
            cache = byCode
            return byCode
        } catch {
            return nil
        }
    }
}

private struct DispatchRow: View {
    let dispatch: Resources_Centrum_Dispatches_Dispatch

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(dispatch.status.status.color)
                .frame(width: 5)
                .padding(.vertical, Theme.Spacing.md)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text(formatDispatchID(dispatch.id))
                        .font(.headline)
                        .foregroundStyle(.tint)
                    Spacer()
                    statusBadge
                }
                Text(sentByLabel(dispatch))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let message = dispatchMessageText(dispatch) {
                    Text(message)
                        .font(.subheadline)
                        .lineLimit(2)
                }
                HStack(spacing: Theme.Spacing.lg) {
                    if !dispatch.postal.isEmpty {
                        Label(dispatch.postal, systemImage: "mappin")
                    }
                    if assignedUnits > 0 {
                        Label("\(assignedUnits) \(assignedUnits == 1 ? "Einheit" : "Einheiten")", systemImage: "building.2")
                    }
                    Spacer()
                    Text(formatRelative(dispatch.createdAt))
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
            }
            .padding(.leading, Theme.Spacing.xl)

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .padding(.trailing, Theme.Spacing.sm)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private var statusBadge: some View {
        StatusBadge(dispatch.status.status.label, color: dispatch.status.status.color)
    }

    private var assignedUnits: Int {
        dispatch.units.count
    }
}
