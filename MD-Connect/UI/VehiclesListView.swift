import SwiftUI

/// Vehicles module: searchable list of vehicles with page-based pagination.
/// Searching (license plate, model or owner name) reloads live as the text
/// changes. Owner names are resolved to user ids via the completor service.
struct VehiclesListView: View {
    @Environment(AppState.self) private var appState

    private static let pageSize: Int64 = 50

    @State private var searchText = ""
    @State private var vehicles: [Resources_Vehicles_Vehicle] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentPage: Int64 = 0
    @State private var totalCount: Int64 = 0
    @State private var hasLoaded = false
    @State private var selectedPlate: String?

    private var totalPages: Int64 {
        max(1, Int64(ceil(Double(totalCount) / Double(Self.pageSize))))
    }

    var body: some View {
        Group {
            List {
                if let errorMessage {
                    Section {
                        StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .cardRow()
                    }
                }

                if isLoading && vehicles.isEmpty {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonListRow()
                    }
                } else if let errorMessage, vehicles.isEmpty {
                    EmptyStateView(
                        "exclamationmark.triangle",
                        color: Theme.Palette.danger,
                        title: "Laden fehlgeschlagen",
                        message: errorMessage,
                        actionTitle: "Erneut versuchen"
                    ) {
                        Task { await load(reset: true) }
                    }
                } else if vehicles.isEmpty {
                    EmptyStateView(
                        "car",
                        color: Theme.Palette.accent,
                        title: "Keine Fahrzeuge gefunden",
                        message: "Für diese Suche sind keine Fahrzeuge vorhanden."
                    )
                } else {
                    Section("\(totalCount) Fahrzeuge gefunden") {
                        ForEach(vehicles, id: \.plate) { vehicle in
                            Button {
                                selectedPlate = vehicle.plate
                            } label: {
                                ListCardRow {
                                    VehicleRow(vehicle: vehicle)
                                }
                            }
                            .buttonStyle(.plain)
                            .cardRow()
                        }
                    }

                    if totalPages > 1 {
                        Section("Seite \(currentPage + 1) von \(totalPages)") {
                            HStack {
                                Button {
                                    Task { await load(page: currentPage - 1) }
                                } label: {
                                    Label("Zurück", systemImage: "chevron.left")
                                }
                                .buttonStyle(.borderless)
                                .disabled(currentPage == 0 || isLoading)

                                Spacer()

                                if isLoading {
                                    ProgressView()
                                }

                                Spacer()

                                Button {
                                    Task { await load(page: currentPage + 1) }
                                } label: {
                                    Label("Weiter", systemImage: "chevron.right")
                                        .labelStyle(.titleAndIcon)
                                }
                                .buttonStyle(.borderless)
                                .disabled(currentPage + 1 >= totalPages || isLoading)
                            }
                            .padding(Theme.Spacing.xl)
                            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                            .cardRow()
                        }
                    }
                }
            }
            .cardListStyle()
            .searchable(text: $searchText, prompt: "Kennzeichen, Modell oder Besitzer suchen")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: searchText) {
                Task { await load(reset: true) }
            }
            .refreshable {
                await load(reset: true)
            }
            .pendingAlarmBell()
            .moduleNavTitle(.vehicles)
            .navConnectionDot()
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                await load(reset: true)
            }
        }
        .navigationDestination(item: $selectedPlate) { plate in
            VehicleDetailView(plate: plate)
        }
    }

    private func load(page: Int64 = 0, reset: Bool = false) async {
        if reset { currentPage = 0 }
        let target = reset ? 0 : page
        currentPage = target
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let userIds = try await resolveOwnerIDs(query)
            let response = try await appState.listVehicles(
                licensePlate: query,
                model: query.count >= 6 ? query : "",
                userIds: userIds,
                offset: target * Self.pageSize,
                pageSize: Self.pageSize
            )
            vehicles = response.vehicles
            totalCount = response.pagination.totalCount
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Resolves a name search to owner user ids via the completor service.
    private func resolveOwnerIDs(_ query: String) async throws -> [Int32] {
        guard !query.isEmpty else { return [] }
        let nameParts = query.split(separator: " ")
        let looksLikeName = nameParts.count <= 2 && nameParts.allSatisfy { part in
            !part.isEmpty && part.first?.isLetter == true
        }
        guard looksLikeName else { return [] }
        let results = try await appState.completeCitizens(search: String(query.prefix(64)))
        return results.map(\.userID)
    }
}

/// Single vehicle row in the list: plate, then FAHRZEUGART · MODELL · EIGENTÜMER.
private struct VehicleRow: View {
    let vehicle: Resources_Vehicles_Vehicle

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            GradientIconTile(vehicleTypeIcon, gradient: FiveNetModule.vehicles.gradient, size: 44)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.md) {
                    Text(vehicle.plate)
                        .font(.headline.monospaced())
                    if vehicle.props.wanted {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.danger)
                    }
                }

                HStack(spacing: Theme.Spacing.xs) {
                    Text(vehicle.type.isEmpty ? "—" : vehicle.type)
                    if vehicle.hasModel, !vehicle.model.isEmpty {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(vehicle.model)
                    }
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(ownerName)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }

    private var ownerName: String {
        if vehicle.hasOwner {
            let owner = vehicle.owner
            let name = [owner.firstname, owner.lastname].filter { !$0.isEmpty }.joined(separator: " ")
            if !name.isEmpty { return name }
        }
        if vehicle.hasOwnerIdentifier, !vehicle.ownerIdentifier.isEmpty {
            return "CIT-\(vehicle.ownerIdentifier)"
        }
        return vehicle.hasOwnerID ? "CIT-\(vehicle.ownerID)" : "k.A."
    }

    private var vehicleTypeIcon: String {
        switch vehicle.type.lowercased() {
        case let t where t.contains("motor"): return "bicycle"
        case let t where t.contains("boat") || t.contains("boot") || t.contains("ship"): return "sailboat.fill"
        case let t where t.contains("truck") || t.contains("lkw") || t.contains("transporter"): return "truck.box.fill"
        case let t where t.contains("air") || t.contains("heli"): return "airplane"
        default: return "car.fill"
        }
    }
}

#Preview {
    NavigationStack {
        VehiclesListView()
            .environment(AppState())
    }
}