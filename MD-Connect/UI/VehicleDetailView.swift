import SwiftUI

/// Vehicles module: full detail of a single vehicle, including owner and
/// wanted status.
struct VehicleDetailView: View {
    @Environment(AppState.self) private var appState

    let plate: String

    @State private var vehicle: Resources_Vehicles_Vehicle?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var copiedToClipboard = false

    var body: some View {
        Group {
            if let vehicle {
                content(vehicle)
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
        .navigationTitle(vehicle?.plate ?? "Fahrzeug")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let vehicle {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.copyVehicleToClipboard(vehicle)
                        copiedToClipboard = true
                    } label: {
                        Label("In Zwischenablage kopieren", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .toast(isPresented: $copiedToClipboard, message: "Kopiert")
        .task {
            await load()
        }
    }

    private func content(_ vehicle: Resources_Vehicles_Vehicle) -> some View {
        List {
            detailHeroSection(DetailHero(
                gradient: FiveNetModule.vehicles.gradient,
                icon: vehicleTypeIcon(vehicle),
                title: vehicle.plate,
                subtitle: modelLine(vehicle).isEmpty ? nil : modelLine(vehicle),
                badges: vehicleBadges(vehicle)
            ))

            Section("Eigentümer") {
                if vehicle.hasOwner {
                    NavigationLink(value: vehicle.owner.userID) {
                        HStack(spacing: Theme.Spacing.lg) {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(ownerName(vehicle))
                                if !ownerJob(vehicle).isEmpty {
                                    Text(ownerJob(vehicle))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    Text("Kein Eigentümer.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Details") {
                labeledRow("Kennzeichen", vehicle.plate)
                labeledRow("Typ", vehicle.type.isEmpty ? "—" : vehicle.type)
                if vehicle.hasModel {
                    labeledRow("Modell", vehicle.model)
                }
                if vehicle.hasJobLabel {
                    labeledRow("Beruf", vehicle.jobLabel)
                }
                if vehicle.props.wanted {
                    if vehicle.props.hasWantedReason, !vehicle.props.wantedReason.isEmpty {
                        labeledRow("Fahndungsgrund", vehicle.props.wantedReason)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: Int32.self) { userID in
            CitizenDetailView(userID: userID)
        }
    }

    private func modelLine(_ vehicle: Resources_Vehicles_Vehicle) -> String {
        var parts: [String] = []
        if !vehicle.type.isEmpty { parts.append(vehicle.type) }
        if vehicle.hasModel, !vehicle.model.isEmpty { parts.append(vehicle.model) }
        return parts.joined(separator: " · ")
    }

    private func ownerName(_ vehicle: Resources_Vehicles_Vehicle) -> String {
        let owner = vehicle.owner
        let name = [owner.firstname, owner.lastname].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "Benutzer #\(vehicle.ownerID)" : name
    }

    private func ownerJob(_ vehicle: Resources_Vehicles_Vehicle) -> String {
        let owner = vehicle.owner
        var parts: [String] = []
        if !owner.jobLabel.isEmpty { parts.append(owner.jobLabel) }
        if !owner.jobGradeLabel.isEmpty { parts.append(owner.jobGradeLabel) }
        return parts.joined(separator: " · ")
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func vehicleBadges(_ vehicle: Resources_Vehicles_Vehicle) -> [String] {
        var result: [String] = []
        if !vehicle.type.isEmpty {
            result.append(vehicle.type)
        }
        if vehicle.props.wanted {
            result.append("GESUCHT")
        }
        return result
    }

    private func vehicleTypeIcon(_ vehicle: Resources_Vehicles_Vehicle) -> String {
        switch vehicle.type.lowercased() {
        case let t where t.contains("motor"): return "bicycle"
        case let t where t.contains("boat") || t.contains("boot") || t.contains("ship"): return "sailboat.fill"
        case let t where t.contains("truck") || t.contains("lkw") || t.contains("transporter"): return "truck.box.fill"
        case let t where t.contains("air") || t.contains("heli"): return "airplane"
        default: return "car.fill"
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await appState.listVehicles(licensePlate: plate, offset: 0, pageSize: 1)
            vehicle = response.vehicles.first
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        VehicleDetailView(plate: "B-1234")
            .environment(AppState())
    }
}