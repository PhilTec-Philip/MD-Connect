import SwiftUI
import SwiftProtobuf

/// Wiki module overview: shows one entry per job wiki (root pages) and
/// supports full-text search across all pages.
struct WikiView: View {
    @Environment(AppState.self) private var appState

    @State private var searchText = ""
    @State private var rootPages: [Resources_Wiki_PageShort] = []
    @State private var searchResults: [Resources_Wiki_PageShort] = []
    @State private var isSearching = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedPage: WikiPageSelection?

    var body: some View {
        Group {
            if isSearching {
                searchResultsList
            } else {
                rootList
            }
        }
        .pendingAlarmBell()
        .moduleNavTitle(.wiki)
        .navConnectionDot()
        .searchable(text: $searchText, prompt: "Seiten durchsuchen")
        .onChange(of: searchText) {
            searchTask?.cancel()
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty {
                isSearching = false
                searchResults = []
                return
            }
            let task = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await runSearch()
            }
            searchTask = task
        }
        .navigationDestination(for: Int64.self) { pageID in
            WikiPageView(pageID: pageID)
        }
        .navigationDestination(item: $selectedPage) { selection in
            WikiPageView(pageID: selection.pageID)
        }
        .task {
            await loadRoots()
        }
    }

    private var rootList: some View {
        List {
            if let errorMessage {
                Section {
                    StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .cardRow()
                }
            }

            if isLoading {
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

            if rootPages.isEmpty && !isLoading && errorMessage == nil {
                Section {
                    EmptyStateView(
                        "book.closed",
                        color: FiveNetModule.wiki.tint,
                        title: "Keine Wiki-Bereiche",
                        message: "Für deinen Beruf sind noch keine Wiki-Seiten eingerichtet."
                    )
                }
            }

            Section {
                ForEach(rootPages) { page in
                    Button {
                        selectedPage = WikiPageSelection(pageID: page.id)
                    } label: {
                        WikiRootRow(page: page, isOwnJob: page.job == appState.character?.job)
                    }
                    .buttonStyle(.plain)
                    .cardRow()
                    .swipeActions(edge: .leading) {
                        Button {
                            appState.toggleWikiPin(page.job)
                            resortRoots()
                        } label: {
                            Label(appState.isWikiPinned(page.job) ? "Nicht anheften" : "Anheften", systemImage: appState.isWikiPinned(page.job) ? "pin.slash" : "pin")
                        }
                        .tint(.cyan)
                    }
                }
            }

            if !rootPages.isEmpty {
                Section {
                    SectionCard {
                        HStack {
                            Text("\(rootPages.count) Wiki-Bereiche")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                    .cardRow()
                }
            }
        }
        .cardListStyle()
        .onChange(of: appState.pinnedWikiJobs) {
            resortRoots()
        }
    }

    private var searchResultsList: some View {
        List {
            if let errorMessage {
                Section {
                    StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .cardRow()
                }
            }

            if searchResults.isEmpty && !isLoading && errorMessage == nil {
                Section {
                    EmptyStateView(
                        "magnifyingglass",
                        color: Theme.Palette.accent,
                        title: "Keine Treffer",
                        message: "Für „\(searchText)“ wurden keine Seiten gefunden."
                    )
                }
            }

            Section {
                ForEach(searchResults) { page in
                    Button {
                        selectedPage = WikiPageSelection(pageID: page.id)
                    } label: {
                        WikiSearchResultRow(page: page)
                    }
                    .buttonStyle(.plain)
                    .cardRow()
                }
            }
        }
        .cardListStyle()
    }

    private func loadRoots() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await appState.listWikiPages(rootOnly: true, pageSize: 100)
            rootPages = sortedRoots(response.pages)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Sorts root pages pinned-first, then by job label, moving the character's
    /// own job to the top.
    private func sortedRoots(_ pages: [Resources_Wiki_PageShort]) -> [Resources_Wiki_PageShort] {
        var sorted = pages.sorted {
            let lhsPinned = appState.isWikiPinned($0.job)
            let rhsPinned = appState.isWikiPinned($1.job)
            if lhsPinned != rhsPinned { return lhsPinned }
            let lhs = $0.jobLabel.isEmpty ? $0.job : $0.jobLabel
            let rhs = $1.jobLabel.isEmpty ? $1.job : $1.jobLabel
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        if let ownJob = appState.character?.job, let index = sorted.firstIndex(where: { $0.job == ownJob }), index > 0 {
            sorted.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
        }
        return sorted
    }

    /// Re-applies the pinned-first sort without refetching.
    private func resortRoots() {
        rootPages.sort {
            let lhsPinned = appState.isWikiPinned($0.job)
            let rhsPinned = appState.isWikiPinned($1.job)
            if lhsPinned != rhsPinned { return lhsPinned }
            let lhs = $0.jobLabel.isEmpty ? $0.job : $0.jobLabel
            let rhs = $1.jobLabel.isEmpty ? $1.job : $1.jobLabel
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else {
            isSearching = false
            searchResults = []
            return
        }
        isSearching = true
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await appState.listWikiPages(search: String(query.prefix(64)), pageSize: 50)
            searchResults = response.pages.sorted {
                let lhsPinned = appState.isWikiPinned($0.job)
                let rhsPinned = appState.isWikiPinned($1.job)
                if lhsPinned != rhsPinned { return lhsPinned }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Navigations-Auswahl für Wiki-Root-/Suchergebnis-Zeilen. Ein eigener Typ
/// statt nacktem `Int64`, damit die item-basierte Navigation nicht mit der
/// `navigationDestination(for: Int64.self)` der Baum-Navigation kollidiert.
private struct WikiPageSelection: Hashable {
    let pageID: Int64
}

private struct WikiRootRow: View {
    let page: Resources_Wiki_PageShort
    let isOwnJob: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xl) {
            GradientIconTile("book.fill", gradient: FiveNetModule.wiki.gradient, size: 46, cornerRadius: Theme.Radius.md)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(jobLabel)
                        .font(.headline)
                    if isOwnJob {
                        Text("Dein Beruf")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xxs)
                            .background(Theme.Palette.info.opacity(0.15), in: Capsule())
                    }
                }
                if !page.title.isEmpty {
                    Text(page.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
        let label = page.jobLabel.isEmpty ? page.job : page.jobLabel
        return label.isEmpty ? "Wiki" : "\(label) Wiki"
    }
}

private struct WikiSearchResultRow: View {
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
