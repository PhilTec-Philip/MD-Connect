import SwiftUI

/// First tab shown when the current character is not signed on as a centrum
/// dispatcher: offers taking over the Leitstelle and shows the own unit.
struct TakeControlView: View {
    @Environment(AppState.self) private var appState

    @State private var isTaking = false

    private var allUnits: [Resources_Centrum_Units_Unit] {
        appState.units.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Direkt an den persistierten AppState gebunden, damit eine nach Server-/
    /// Charakterwechsel wiederhergestellte Einheit immer im Picker erscheint
    /// (kein separater @State, der synchronisiert werden müsste).
    private var dutyUnitSelection: Binding<Int64?> {
        Binding(
            get: { appState.selectedDutyUnitID },
            set: { appState.setDutyUnit($0) }
        )
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                                .fill(.white.opacity(0.18))
                            Image(systemName: "person.crop.circle.badge.exclamationmark")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 56, height: 56)
                        Spacer()
                    }
                    Text("Du bist nicht in der Leitstellen-Einheit")
                        .font(Theme.Typography.title3)
                        .foregroundStyle(.white)
                    Text("Übernimm die Leitstelle, um Einsätze zu verwalten und Einheiten zuzuweisen.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.92))
                }
                .padding(Theme.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: FiveNetModule.centrum.gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
                .shadow(color: FiveNetModule.centrum.tint.opacity(0.25), radius: 14, y: 6)
                .listRowInsets(EdgeInsets(
                    top: Theme.Spacing.xs,
                    leading: Theme.Spacing.xl,
                    bottom: Theme.Spacing.xs,
                    trailing: Theme.Spacing.xl
                ))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                SectionCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        LabeledContent {
                            Picker("Einheit nach Übernahme", selection: dutyUnitSelection) {
                                Text("Keine (nur Leitstelle)").tag(Int64?.none)
                                ForEach(allUnits) { unit in
                                    Text("\(unit.initials) – \(unit.name)").tag(Int64?.some(unit.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .id(allUnits.map(\.id))
                        } label: {
                            Label("Einheit nach Übernahme", systemImage: "building.2.fill")
                        }
                        Text("Nach der Übernahme wirst du automatisch in die gewählte Einheit versetzt. Die Auswahl ist jederzeit änderbar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .cardRow()
            } header: {
                Text("Leitstellen-Einheit")
            }

            Section("Aktuelle Einheit") {
                if let unit = appState.ownUnit {
                    HStack(spacing: Theme.Spacing.lg) {
                        ZStack {
                            Circle()
                                .fill(unitColor(unit).opacity(0.2))
                                .frame(width: 40, height: 40)
                            Text("\(unit.users.count)")
                                .font(.subheadline.bold())
                                .foregroundStyle(unitColor(unit))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(unit.initials) – \(unit.name)")
                                .font(.subheadline.weight(.medium))
                            if !unit.jobLabel.isEmpty {
                                Text(unit.jobLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .background(
                        Theme.Palette.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                    .cardRow()
                } else {
                    SectionCard {
                        Text("Keine Einheit zugewiesen.")
                            .foregroundStyle(.secondary)
                    }
                    .cardRow()
                }
            }

            Section {
                SectionCard {
                    VStack(spacing: Theme.Spacing.md) {
                        Button {
                            Task { await takeControl() }
                        } label: {
                            if isTaking {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("Leitstelle übernehmen", systemImage: "location.fill")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isTaking)
                        Text("Nach der Übernahme wird dieser Tab automatisch ausgeblendet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .cardRow()
            }
        }
        .cardListStyle()
        .contentMargins(.top, Theme.Spacing.xl, for: .scrollContent)
        .navigationTitle("Leitstelle")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func takeControl() async {
        isTaking = true
        defer { isTaking = false }
        await appState.takeControl()
    }

    private func unitColor(_ unit: Resources_Centrum_Units_Unit) -> Color {
        Color(hex: unit.color) ?? .accentColor
    }
}

#Preview {
    NavigationStack {
        TakeControlView()
            .environment(AppState())
    }
}
