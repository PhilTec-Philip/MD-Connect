import SwiftUI
import SwiftProtobuf

/// Global search across all modules (Bürger, Fahrzeuge, Einsätze, Dokumente,
/// Wiki). Presented modally with its own navigation stack so it can be reached
/// from both the overview and the quick view. Queries run in parallel with a
/// ~300 ms debounce; a failing module does not hide the others.
struct GlobalSearchView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var results = SearchResults()

    private enum Route: Hashable {
        case citizen(Int32)
        case vehicle(String)
        case dispatch(Int64)
        case document(Int64)
        case wiki(Int64)
    }

    private struct SearchResults {
        var citizens: [Resources_Users_User] = []
        var vehicles: [Resources_Vehicles_Vehicle] = []
        var dispatches: [Resources_Centrum_Dispatches_Dispatch] = []
        var documents: [Resources_Documents_DocumentShort] = []
        var wikiPages: [Resources_Wiki_PageShort] = []

        var isEmpty: Bool {
            citizens.isEmpty && vehicles.isEmpty && dispatches.isEmpty
                && documents.isEmpty && wikiPages.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if searchText.isEmpty {
                    promptView
                } else if isSearching {
                    List {
                        Section {
                            SectionCard {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                    Spacer()
                                }
                            }
                            .cardRow()
                        }
                    }
                } else if let errorMessage {
                    List {
                        Section {
                            StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .cardRow()
                        }
                    }
                } else if results.isEmpty {
                    ContentUnavailableView(
                        "Keine Treffer",
                        systemImage: "magnifyingglass",
                        description: Text("Zu „\(searchText)“ wurde nichts gefunden.")
                    )
                } else {
                    resultsList
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Alles durchsuchen"
            )
            .navigationTitle("Suche")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .citizen(let userID):
                    CitizenDetailView(userID: userID)
                case .vehicle(let plate):
                    VehicleDetailView(plate: plate)
                case .dispatch(let dispatchID):
                    DispatchDetailView(dispatchID: dispatchID)
                case .document(let documentID):
                    DocumentDetailView(documentID: documentID)
                case .wiki(let pageID):
                    WikiPageView(pageID: pageID)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onChange(of: searchText) {
                scheduleSearch()
            }
        }
    }

    private var promptView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Bürger, Fahrzeuge, Einsätze, Dokumente und Wiki durchsuchen")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xxxl)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.background.ignoresSafeArea())
    }

    private var resultsList: some View {
        List {
            if !results.citizens.isEmpty {
                Section {
                    ForEach(results.citizens) { user in
                        NavigationLink(value: Route.citizen(user.userID)) {
                            SearchCitizenRow(user: user)
                        }
                        .buttonStyle(.plain)
                        .navigationLinkIndicatorVisibility(.hidden)
                        .cardRow()
                    }
                } header: {
                    resultHeader(results.citizens.count, "Bürger", "person.crop.circle")
                }
            }

            if !results.vehicles.isEmpty {
                Section {
                    ForEach(results.vehicles, id: \.plate) { vehicle in
                        NavigationLink(value: Route.vehicle(vehicle.plate)) {
                            SearchVehicleRow(vehicle: vehicle)
                        }
                        .buttonStyle(.plain)
                        .navigationLinkIndicatorVisibility(.hidden)
                        .cardRow()
                    }
                } header: {
                    resultHeader(results.vehicles.count, "Fahrzeuge", "car.fill")
                }
            }

            if !results.dispatches.isEmpty {
                Section {
                    ForEach(results.dispatches) { dispatch in
                        NavigationLink(value: Route.dispatch(dispatch.id)) {
                            SearchDispatchRow(dispatch: dispatch)
                        }
                        .buttonStyle(.plain)
                        .navigationLinkIndicatorVisibility(.hidden)
                        .cardRow()
                    }
                } header: {
                    resultHeader(results.dispatches.count, "Einsätze", "exclamationmark.octagon.fill")
                }
            }

            if !results.documents.isEmpty {
                Section {
                    ForEach(results.documents) { document in
                        NavigationLink(value: Route.document(document.id)) {
                            SearchDocumentRow(document: document)
                        }
                        .buttonStyle(.plain)
                        .navigationLinkIndicatorVisibility(.hidden)
                        .cardRow()
                    }
                } header: {
                    resultHeader(results.documents.count, "Dokumente", "doc.text.fill")
                }
            }

            if !results.wikiPages.isEmpty {
                Section {
                    ForEach(results.wikiPages) { page in
                        NavigationLink(value: Route.wiki(page.id)) {
                            SearchWikiRow(page: page)
                        }
                        .buttonStyle(.plain)
                        .navigationLinkIndicatorVisibility(.hidden)
                        .cardRow()
                    }
                } header: {
                    resultHeader(results.wikiPages.count, "Wiki", "book.fill")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.background.ignoresSafeArea())
    }

    private func resultHeader(_ count: Int, _ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            isSearching = false
            results = SearchResults()
            errorMessage = nil
            return
        }
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await runSearch()
        }
        searchTask = task
    }

    private func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isSearching = true
        errorMessage = nil
        results = SearchResults()
        defer { isSearching = false }

        let dispatchIDs: [Int64] = {
            if let id = Int64(query), id > 0 {
                return [id]
            }
            return []
        }()

        async let citizens = try? appState.listCitizens(search: query, pageSize: 10)
        async let vehicles = try? appState.listVehicles(licensePlate: query, pageSize: 10)
        async let dispatches = try? appState.searchDispatches(ids: dispatchIDs, postal: query, pageSize: 10)
        async let documents = try? appState.listDocuments(search: query, pageSize: 10)
        async let wikiPages = try? appState.listWikiPages(search: query, pageSize: 10)

        let (citizensResult, vehiclesResult, dispatchesResult, documentsResult, wikiResult) =
            await (citizens, vehicles, dispatches, documents, wikiPages)

        if let response = citizensResult {
            results.citizens = response.users
        }
        if let response = vehiclesResult {
            results.vehicles = response.vehicles
        }
        if let response = dispatchesResult {
            results.dispatches = response.dispatches
        }
        if let response = documentsResult {
            results.documents = response.documents
        }
        if let response = wikiResult {
            results.wikiPages = response.pages
        }

        if results.isEmpty {
            errorMessage = "Alle Module haben die Suche ohne Ergebnis beantwortet."
        }
    }
}

// MARK: - Search result rows

private struct SearchCitizenRow: View {
    let user: Resources_Users_User

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            GradientIconTile("person.crop.circle.fill", gradient: FiveNetModule.citizens.gradient, size: 44)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                if !jobLine.isEmpty {
                    Text(jobLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            IDBadge("CIT-\(user.userID)")
            CardChevron()
        }
        .padding(Theme.Spacing.xl)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private var name: String {
        [user.firstname, user.lastname]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var jobLine: String {
        var parts: [String] = []
        if !user.jobLabel.isEmpty { parts.append(user.jobLabel) }
        if !user.jobGradeLabel.isEmpty { parts.append(user.jobGradeLabel) }
        return parts.joined(separator: " · ")
    }
}

private struct SearchVehicleRow: View {
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

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
            CardChevron()
        }
        .padding(Theme.Spacing.xl)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private var vehicleTypeIcon: String {
        if vehicle.props.wanted {
            return "car.fill"
        }
        switch vehicle.type.lowercased() {
        case let type where type.contains("motor"): return "scooter"
        case let type where type.contains("lkw") || type.contains("truck"): return "truck.fill"
        case let type where type.contains("boot") || type.contains("wasser"): return "ferry.fill"
        default: return "car.fill"
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !vehicle.type.isEmpty { parts.append(vehicle.type.uppercased()) }
        if vehicle.hasModel, !vehicle.model.isEmpty { parts.append(vehicle.model) }
        parts.append(ownerName)
        return parts.joined(separator: " · ")
    }

    private var ownerName: String {
        if vehicle.hasOwner {
            let name = [vehicle.owner.firstname, vehicle.owner.lastname]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !name.isEmpty { return name }
        }
        if vehicle.hasOwnerIdentifier, !vehicle.ownerIdentifier.isEmpty {
            return "CIT-\(vehicle.ownerIdentifier)"
        }
        return vehicle.hasOwnerID ? "CIT-\(vehicle.ownerID)" : "k.A."
    }
}

private struct SearchDispatchRow: View {
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
                    StatusBadge(dispatch.status.status.label, color: dispatch.status.status.color)
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
                    if dispatch.units.count > 0 {
                        Label("\(dispatch.units.count) \(dispatch.units.count == 1 ? "Einheit" : "Einheiten")", systemImage: "building.2")
                    }
                    Spacer()
                    Text(formatRelative(dispatch.createdAt))
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
            }
            .padding(.leading, Theme.Spacing.xl)

            Spacer(minLength: 0)
            CardChevron()
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

private struct SearchDocumentRow: View {
    let document: Resources_Documents_DocumentShort

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.lg) {
            GradientIconTile("doc.text", gradient: FiveNetModule.documents.gradient, size: 44)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            IDBadge(formatDocumentID(document.id))
            CardChevron()
        }
        .padding(Theme.Spacing.xl)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private var title: String {
        document.title.isEmpty ? "Unbenanntes Dokument" : document.title
    }

    private var subtitle: String {
        var parts: [String] = []
        if document.hasCategory, !document.category.name.isEmpty {
            parts.append(document.category.name)
        }
        let creatorName = [document.creator.firstname, document.creator.lastname]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !creatorName.isEmpty {
            parts.append(creatorName)
        }
        if document.hasUpdatedAt, document.updatedAt.timestamp.date.timeIntervalSince1970 > 0 {
            parts.append(formatRelative(document.updatedAt))
        } else if document.hasCreatedAt, document.createdAt.timestamp.date.timeIntervalSince1970 > 0 {
            parts.append(formatRelative(document.createdAt))
        }
        return parts.joined(separator: " · ")
    }
}

private struct SearchWikiRow: View {
    let page: Resources_Wiki_PageShort

    var body: some View {
        HStack(spacing: Theme.Spacing.xl) {
            GradientIconTile("doc.text.magnifyingglass", gradient: FiveNetModule.wiki.gradient, size: 44)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(page.title.isEmpty ? "Unbenannt" : page.title)
                    .font(.headline)
                HStack(spacing: Theme.Spacing.xs) {
                    Text(jobLabel)
                    if page.hasSlug && !page.slug.isEmpty {
                        Text("·")
                        Text(page.slug)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()
            CardChevron()
        }
        .padding(Theme.Spacing.xl)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private var jobLabel: String {
        page.jobLabel.isEmpty ? page.job : page.jobLabel
    }
}

#Preview {
    GlobalSearchView()
        .environment(AppState())
}
