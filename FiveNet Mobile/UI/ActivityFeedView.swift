import SwiftUI

/// Live activity feed of the Leitstelle: unit and dispatch status changes,
/// streamed in real time from the centrum stream.
struct ActivityFeedView: View {
    @Environment(AppState.self) private var appState

    @State private var searchText = ""

    private var filteredActivity: [CentrumActivityEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return appState.centrumActivity }
        return appState.centrumActivity.filter { entry in
            entry.title.lowercased().contains(query) || entry.subtitle.lowercased().contains(query)
        }
    }

    var body: some View {
        List {
            Section("Letzte Aktivität") {
                if filteredActivity.isEmpty {
                    SectionCard {
                        Text(searchText.isEmpty ? "Noch keine Aktivität vorhanden." : "Keine Treffer für deine Suche.")
                            .foregroundStyle(.secondary)
                    }
                    .cardRow()
                } else {
                    ForEach(filteredActivity) { entry in
                        HStack(spacing: Theme.Spacing.lg) {
                            IconTile(entry.icon, color: FiveNetModule.centrum.tint, size: 36)
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(entry.title)
                                    .font(.subheadline.weight(.medium))
                                if !entry.subtitle.isEmpty {
                                    Text("\(formatRelative(entry.timestamp)) · \(entry.subtitle)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
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
                }
            }
        }
        .cardListStyle()
        .contentMargins(.top, Theme.Spacing.xl, for: .scrollContent)
        .searchable(text: $searchText, prompt: "Aktivität durchsuchen")
        .refreshable {
            await appState.loadCentrum()
        }
    }
}

#Preview {
    NavigationStack {
        ActivityFeedView()
            .environment(AppState())
    }
}
