import SwiftUI
import SwiftProtobuf

/// Einstellungen → Rolle: zeigt die effektiven (vererbten) Berechtigungen und
/// Attribute einer Rolle.
struct SettingsRoleDetailView: View {
    @Environment(AppState.self) private var appState

    let roleID: Int64

    @State private var role: Resources_Permissions_Permissions_Role?
    @State private var permissions: [Resources_Permissions_Permissions_Permission] = []
    @State private var attributes: [Resources_Permissions_Attributes_RoleAttribute] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .cardRow()
                }
            }

            if isLoading && role == nil {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonListRow()
                }
            } else if let role {
                detailHeroSection(
                    DetailHero(
                        gradient: FiveNetModule.settings.gradient,
                        icon: "person.badge.key.fill",
                        title: role.hasJobLabel && !role.jobLabel.isEmpty ? role.jobLabel : "Rang \(role.grade)",
                        subtitle: role.hasJobGradeLabel && !role.jobGradeLabel.isEmpty ? role.jobGradeLabel : nil,
                        badges: [role.job]
                    )
                )

                Section {
                    SectionCard {
                        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            SectionHeader("Berechtigungen")
                            if permissions.isEmpty {
                                Text("Keine effektiven Berechtigungen.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(permissions, id: \.id) { permission in
                                    permissionRow(permission)
                                }
                            }
                        }
                        .padding(Theme.Spacing.md)
                    }
                    .cardRow()
                }

                Section {
                    SectionCard {
                        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            SectionHeader("Attribute")
                            if attributes.isEmpty {
                                Text("Keine Attribute zugewiesen.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(attributes, id: \.attrID) { attribute in
                                    attributeRow(attribute)
                                }
                            }
                        }
                        .padding(Theme.Spacing.md)
                    }
                    .cardRow()
                }
            } else {
                Section {
                    EmptyStateView(
                        "person.badge.key.fill",
                        color: FiveNetModule.settings.tint,
                        title: "Rolle nicht gefunden",
                        message: "Die Rolle konnte nicht geladen werden."
                    )
                    .cardRow()
                }
            }
        }
        .cardListStyle()
        .navigationTitle("Rolle")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func permissionRow(_ permission: Resources_Permissions_Permissions_Permission) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: permission.val ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(permission.val ? Theme.Palette.success : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.name.isEmpty ? permission.guardName : permission.name)
                    .font(.subheadline.weight(.medium))
                Text("\(permission.namespace) / \(permission.service)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func attributeRow(_ attribute: Resources_Permissions_Attributes_RoleAttribute) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(attribute.name.isEmpty ? attribute.key : attribute.name)
                .font(.subheadline.weight(.medium))
            Text("\(attribute.namespace) / \(attribute.service) · Typ: \(attribute.type)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !attributeValueText(attribute).isEmpty {
                Text(attributeValueText(attribute))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.info)
            }
        }
    }

    private func attributeValueText(_ attribute: Resources_Permissions_Attributes_RoleAttribute) -> String {
        guard let value = attribute.value.validValues else { return "" }
        switch value {
        case .stringList(let list):
            return list.strings.joined(separator: ", ")
        case .jobList(let list):
            return list.strings.joined(separator: ", ")
        case .jobGradeList(let jobGrades):
            var parts: [String] = []
            for (job, count) in jobGrades.jobs.sorted(by: { $0.key < $1.key }) {
                parts.append("\(job): \(count)")
            }
            for (job, grades) in jobGrades.grades.sorted(by: { $0.key < $1.key }) {
                parts.append("\(job): \(grades.grades.map(String.init).joined(separator: ", "))")
            }
            return parts.joined(separator: "; ")
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await appState.getEffectivePermissions(roleId: roleID)
            role = response.role
            permissions = response.permissions
            attributes = response.attributes
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        SettingsRoleDetailView(roleID: 1)
    }
}
