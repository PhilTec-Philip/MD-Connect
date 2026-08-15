import SwiftUI

/// Dispatch archive ("Archiv"): all dispatches with search by dispatch id /
/// postal code and pagination, mirroring the web archive page.
struct ArchiveView: View {
    @Environment(AppState.self) private var appState

    private static let pageSize: Int64 = 50

    private static let archivedStatuses: [Resources_Centrum_Dispatches_StatusDispatch] = [
        .completed, .cancelled, .archived, .deleted,
    ]

    @State private var searchText = ""
    @State private var dispatches: [Resources_Centrum_Dispatches_Dispatch] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentPage: Int64 = 0
    @State private var totalCount: Int64 = 0
    @State private var hasLoaded = false

    private var totalPages: Int64 {
        max(1, Int64(ceil(Double(totalCount) / Double(Self.pageSize))))
    }

    var body: some View {
        Group {
            List {
                Section {
                    SectionCard {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                TextField("Dispatch-ID oder PLZ", text: $searchText)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                if !searchText.isEmpty {
                                    Button {
                                        searchText = ""
                                        Task { await load(reset: true) }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Text("Es werden nur abgeschlossene Einsätze angezeigt.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .cardRow()
                }

                if isLoading && dispatches.isEmpty {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonListRow()
                    }
                } else if let errorMessage, dispatches.isEmpty {
                    EmptyStateView(
                        "exclamationmark.triangle",
                        color: Theme.Palette.danger,
                        title: "Laden fehlgeschlagen",
                        message: errorMessage,
                        actionTitle: "Erneut versuchen"
                    ) {
                        Task { await load(reset: true) }
                    }
                } else if dispatches.isEmpty {
                    EmptyStateView(
                        "archivebox",
                        color: Theme.Palette.accent,
                        title: "Keine Einsätze gefunden",
                        message: "Für diese Suche sind keine Einsätze vorhanden."
                    )
                } else {
                    Section("\(totalCount) Einsätze gefunden") {
                        ForEach(dispatches) { dispatch in
                            NavigationLink(value: CentrumRoute.dispatch(dispatch.id)) {
                                ArchiveDispatchRow(dispatch: dispatch)
                            }
                            .buttonStyle(.plain)
                            .cardRow()
                        }
                    }

                    if totalPages > 1 {
                        Section("Seite \(currentPage + 1) von \(totalPages)") {
                            PaginationFooter {
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
                            }
                        }
                    }
                }
            }
            .cardListStyle()
            .contentMargins(.top, Theme.Spacing.xl, for: .scrollContent)
            .onChange(of: searchText) {
                Task { await load(reset: true) }
            }
            .refreshable {
                await load(reset: true)
            }
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                await load(reset: true)
            }
        }
    }

    private func load(page: Int64 = 0, reset: Bool = false) async {
        guard let client = appState.client else { return }
        if reset { currentPage = 0 }
        let target = reset ? 0 : page
        currentPage = target
        isLoading = true
        defer { isLoading = false }
        do {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let isNumeric = !query.isEmpty && query.allSatisfy(\.isNumber)
            let parsedID = isNumeric ? (Int64(query) ?? 0) : 0
            let ids: [Int64] = parsedID > 0 ? [parsedID] : []
            let postal = isNumeric ? "" : String(query.filter(\.isNumber))
            let response = try await client.searchDispatches(
                ids: ids,
                postal: postal,
                status: Self.archivedStatuses,
                offset: target * Self.pageSize,
                pageSize: Self.pageSize
            )
            dispatches = response.dispatches
            totalCount = response.pagination.totalCount
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ArchiveDispatchRow: View {
    let dispatch: Resources_Centrum_Dispatches_Dispatch

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(dispatch.status.status.color)
                .frame(width: 5)
                .padding(.vertical, Theme.Spacing.md)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(formatDispatchID(dispatch.id))
                        .font(.headline)
                        .foregroundStyle(.tint)
                    Spacer()
                    Label(dispatch.status.status.label, systemImage: "circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(dispatch.status.status.color)
                }
                Text(sentByLabel(dispatch))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    if !dispatch.postal.isEmpty {
                        Label(dispatch.postal, systemImage: "mappin")
                    }
                    Spacer()
                    Text(formatTimestamp(dispatch.createdAt))
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
}

#Preview {
    NavigationStack {
        ArchiveView()
            .environment(AppState())
    }
}
