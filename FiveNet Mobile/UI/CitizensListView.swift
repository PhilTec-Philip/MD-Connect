import SwiftUI
import SwiftProtobuf

/// Citizens module: searchable list of citizens with page-based pagination.
/// Searching triggers a live reload as the text changes.
struct CitizensListView: View {
    @Environment(AppState.self) private var appState

    private static let pageSize: Int64 = 50

    @State private var searchText = ""
    @State private var citizens: [Resources_Users_User] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentPage: Int64 = 0
    @State private var totalCount: Int64 = 0
    @State private var hasLoaded = false

    private let identifierFormat = CitizenIDFormat()

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

                if isLoading && citizens.isEmpty {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonListRow()
                    }
                } else if let errorMessage, citizens.isEmpty {
                    EmptyStateView(
                        "exclamationmark.triangle",
                        color: Theme.Palette.danger,
                        title: "Laden fehlgeschlagen",
                        message: errorMessage,
                        actionTitle: "Erneut versuchen"
                    ) {
                        Task { await load(reset: true) }
                    }
                } else if citizens.isEmpty {
                    EmptyStateView(
                        "person.2",
                        color: Theme.Palette.accent,
                        title: "Keine Bürger gefunden",
                        message: "Für diese Suche sind keine Bürger vorhanden."
                    )
                } else {
                    Section("\(totalCount) Bürger gefunden") {
                        ForEach(citizens) { citizen in
                            NavigationLink(value: citizen.userID) {
                                ListCardRow {
                                    CitizenRow(user: citizen, identifierFormat: identifierFormat)
                                }
                            }
                            .buttonStyle(.plain)
                            .navigationLinkIndicatorVisibility(.hidden)
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
            .searchable(text: $searchText, prompt: "Name oder CIT suchen")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: searchText) {
                Task { await load(reset: true) }
            }
            .refreshable {
                await load(reset: true)
            }
            .pendingAlarmBell()
            .moduleNavTitle(.citizens)
            .navConnectionDot()
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                await load(reset: true)
            }
        }
        .navigationDestination(for: Int32.self) { userID in
            CitizenDetailView(userID: userID)
        }
    }

    private func load(page: Int64 = 0, reset: Bool = false) async {
        if reset { currentPage = 0 }
        let target = reset ? 0 : page
        currentPage = target
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let offset = target * Self.pageSize
        do {
            let response = try await appState.listCitizens(
                search: query,
                offset: offset,
                pageSize: Self.pageSize
            )
            citizens = response.users
            totalCount = response.pagination.totalCount
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Formats the golden CIT (Citizen-ID) shown next to a citizen's name.
struct CitizenIDFormat {
    func idString(for user: Resources_Users_User) -> String? {
        "CIT-\(user.userID)"
    }
}

private struct CitizenRow: View {
    let user: Resources_Users_User
    let identifierFormat: CitizenIDFormat

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            GradientIconTile("person.crop.circle.fill", gradient: FiveNetModule.citizens.gradient, size: 44)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(fullName)
                    .font(.headline)
                    .lineLimit(1)
                if !jobLine.isEmpty {
                    Text(jobLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let id = identifierFormat.idString(for: user) {
                IDBadge(id)
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }

    private var fullName: String {
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

#Preview {
    NavigationStack {
        CitizensListView()
            .environment(AppState())
    }
}