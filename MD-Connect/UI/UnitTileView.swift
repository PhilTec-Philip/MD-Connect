import SwiftUI

/// Einheiten-Kachel mit Beitreten/Verlassen, wie sie der LiveMap-„Einheiten"-
/// Tab verwendet. Wiederverwendbar für die Quick-Ansicht, damit man direkt aus
/// einer Einheiten-Liste einer Einheit beitreten kann.
struct UnitTileView: View {
    @Environment(AppState.self) private var appState
    let unit: Resources_Centrum_Units_Unit

    @State private var joinInProgress = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(unit.initials)
                    .font(.title3.bold())
                    .foregroundStyle(color)
                Spacer()
                Button {
                    appState.toggleUnitFavorite(unit.id)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.subheadline)
                        .foregroundStyle(isFavorite ? .yellow : Color(.tertiaryLabel))
                }
                .buttonStyle(.plain)
            }
            Text(unit.name)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text("\(unit.users.count) \(unit.users.count == 1 ? "Mitglied" : "Mitglieder")")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isOwnUnit {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Deine Einheit")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    Button(role: .destructive) {
                        Task { await performLeave(unit) }
                    } label: {
                        Label("Verlassen", systemImage: "person.crop.circle.badge.minus")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .foregroundStyle(Color.red)
                    }
                    .buttonStyle(.plain)
                    .disabled(joinInProgress)
                }
                .padding(.top, 2)
            } else {
                Button {
                    Task { await performJoin(unit) }
                } label: {
                    Label(joinInProgress ? "Beitritt …" : "Beitreten", systemImage: "person.badge.plus")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(joinInProgress)
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isFavorite ? Color.yellow.opacity(0.5) : Color(.separator), lineWidth: isFavorite ? 1.5 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .alert("Beitritt nicht möglich", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private var isFavorite: Bool {
        appState.favoriteUnitIDs.contains(unit.id)
    }

    private var isOwnUnit: Bool {
        appState.ownUnitID == unit.id
    }

    private var color: Color {
        Color(hex: unit.color) ?? .accentColor
    }

    @MainActor
    private func performJoin(_ unit: Resources_Centrum_Units_Unit) async {
        guard !joinInProgress else { return }
        joinInProgress = true
        defer { joinInProgress = false }
        await appState.joinUnit(unit.id)
        if let error = appState.centrumError {
            errorText = error
        }
    }

    @MainActor
    private func performLeave(_ unit: Resources_Centrum_Units_Unit) async {
        guard !joinInProgress else { return }
        joinInProgress = true
        defer { joinInProgress = false }
        await appState.leaveUnit(unit.id)
        if let error = appState.centrumError {
            errorText = error
        }
    }
}

#Preview {
    UnitTileView(unit: Resources_Centrum_Units_Unit())
        .environment(AppState())
}
