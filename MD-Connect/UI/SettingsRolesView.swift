import SwiftUI
import SwiftProtobuf

/// Navigation route into the role permission detail.
struct SettingsRoleRoute: Hashable {
    let roleID: Int64
}

/// Einstellungen → Rollen & Berechtigungen: listet die Rollen des aktiven
/// Berufs, erlaubt das Anlegen/Löschen und die Einsicht in die effektiven
/// Berechtigungen einer Rolle.
struct SettingsRolesView: View {
    @Environment(AppState.self) private var appState

    @State private var roles: [Resources_Permissions_Permissions_Role] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedRoute: SettingsRoleRoute?
    @State private var showCreate = false
    @State private var roleToDelete: Resources_Permissions_Permissions_Role?

    private var canCreate: Bool {
        appState.can("settings.SettingsService/CreateRole")
    }

    private var canDelete: Bool {
        appState.can("settings.SettingsService/DeleteRole")
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

                if isLoading && roles.isEmpty {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonListRow()
                    }
                } else if roles.isEmpty {
                    Section {
                        EmptyStateView(
                            "person.3.fill",
                            color: FiveNetModule.settings.tint,
                            title: "Keine Rollen",
                            message: "Für deinen Beruf wurden noch keine Rollen eingerichtet."
                        )
                        .cardRow()
                    }
                } else {
                    Section {
                        ForEach(roles) { role in
                            Button {
                                selectedRoute = SettingsRoleRoute(roleID: role.id)
                            } label: {
                                SettingsRoleRow(role: role)
                            }
                            .cardRow()
                            .swipeActions(edge: .trailing) {
                                if canDelete {
                                    Button(role: .destructive) {
                                        roleToDelete = role
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .cardListStyle()
            .contentMargins(.top, Theme.Spacing.xl, for: .scrollContent)
            .navigationTitle("Rollen & Berechtigungen")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .toolbar {
                if canCreate {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showCreate = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Rolle erstellen")
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                SettingsCreateRoleSheet(onCreated: {
                    showCreate = false
                    Task { await load() }
                })
            }
            .confirmationDialog(
                "Rolle löschen?",
                isPresented: Binding(get: { roleToDelete != nil }, set: { if !$0 { roleToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Löschen", role: .destructive) {
                    if let role = roleToDelete {
                        delete(role)
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Die Rolle kann danach nicht mehr zugewiesen werden.")
            }
        }
        .navigationDestination(item: $selectedRoute) { route in
            SettingsRoleDetailView(roleID: route.roleID)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            roles = try await appState.getRoles()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func delete(_ role: Resources_Permissions_Permissions_Role) {
        Task {
            do {
                try await appState.deleteRole(id: role.id)
                roles.removeAll { $0.id == role.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Karten-Zeile für eine Rolle.
private struct SettingsRoleRow: View {
    let role: Resources_Permissions_Permissions_Role

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(FiveNetModule.settings.tint.opacity(0.14))
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FiveNetModule.settings.tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(roleName)
                    .font(.headline)
                if let gradeLabel = gradeLabel {
                    Text(gradeLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            CardChevron()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var roleName: String {
        role.hasJobLabel && !role.jobLabel.isEmpty ? role.jobLabel : "Rang \(role.grade)"
    }

    private var gradeLabel: String? {
        guard role.hasJobGradeLabel, !role.jobGradeLabel.isEmpty else { return nil }
        return role.jobGradeLabel
    }
}

/// Sheet zum Erstellen einer neuen Rolle (Beruf + Rang).
struct SettingsCreateRoleSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var onCreated: () -> Void

    @State private var job = ""
    @State private var grade: Int32 = 0
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Rolle") {
                    TextField("Beruf (Job-Code)", text: $job)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                    Stepper("Rang: \(grade)", value: $grade, in: 0...30)
                }

                if let errorMessage {
                    Section {
                        StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    }
                }
            }
            .navigationTitle("Rolle erstellen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen") {
                        save()
                    }
                    .disabled(isSaving || job.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if job.isEmpty {
                    job = appState.character?.job ?? ""
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                _ = try await appState.createRole(
                    job: job.trimmingCharacters(in: .whitespacesAndNewlines),
                    grade: grade
                )
                onCreated()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsRolesView()
    }
}
