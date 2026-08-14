import SwiftUI
import SwiftProtobuf

/// Berufe "Kollegen": searchable list of colleagues with an absence filter,
/// label filters and page-based pagination. Mirrors the web colleagues list.
struct ColleaguesListView: View {
    @Environment(AppState.self) private var appState

    private static let pageSize: Int64 = 20

    @State private var searchText = ""
    @State private var colleagues: [Resources_Jobs_Colleagues_Colleague] = []
    @State private var labels: [Resources_Jobs_Labels_Label] = []
    @State private var selectedLabelIDs: Set<Int64> = []
    @State private var onlyAbsent = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentPage: Int64 = 0
    @State private var totalCount: Int64 = 0
    @State private var hasLoaded = false
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedColleagueID: Int32?
    @State private var showLabels = false

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
                                TextField("Name suchen", text: $searchText)
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
                        }
                    }
                    .cardRow()
                }

                if let errorMessage {
                    Section {
                        StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .cardRow()
                    }
                }

                if isLoading && colleagues.isEmpty {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonListRow()
                    }
                } else if let errorMessage, colleagues.isEmpty {
                    EmptyStateView(
                        "exclamationmark.triangle",
                        color: Theme.Palette.danger,
                        title: "Laden fehlgeschlagen",
                        message: errorMessage,
                        actionTitle: "Erneut versuchen"
                    ) {
                        Task { await load(reset: true) }
                    }
                } else if colleagues.isEmpty {
                    EmptyStateView(
                        "person.2",
                        color: Theme.Palette.accent,
                        title: "Keine Kollegen gefunden",
                        message: "Für diese Filter sind keine Kollegen vorhanden."
                    )
                } else {
                    Section("\(totalCount) Kollegen gefunden") {
                        ForEach(colleagues) { colleague in
                            Button {
                                selectedColleagueID = colleague.userID
                            } label: {
                                ListCardRow {
                                    ColleagueRow(colleague: colleague)
                                }
                            }
                            .buttonStyle(.plain)
                            .cardRow()
                        }
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
            .cardListStyle()
            .contentMargins(.top, Theme.Spacing.xl, for: .scrollContent)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        JobsLabelsView()
                    } label: {
                        Label("Labels", systemImage: "tag")
                    }
                    Toggle("Nur abwesend", isOn: $onlyAbsent)
                        .toggleStyle(.button)
                        .labelStyle(.titleOnly)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !labels.isEmpty {
                    labelFilterBar
                }
            }
            .onChange(of: searchText) {
                searchTask?.cancel()
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if query.isEmpty {
                    searchTask = Task { @MainActor in
                        await load(reset: true)
                    }
                    return
                }
                let task = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    await load(reset: true)
                }
                searchTask = task
            }
            .onChange(of: onlyAbsent) {
                Task { await load(reset: true) }
            }
            .onChange(of: selectedLabelIDs) {
                Task { await load(reset: true) }
            }
            .refreshable {
                await load(reset: true)
            }
            .navigationTitle("Kollegen")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                async let labelsLoad: Void = loadLabels()
                async let colleaguesLoad: Void = load(reset: true)
                _ = await (labelsLoad, colleaguesLoad)
            }
        }
        .navigationDestination(item: $selectedColleagueID) { userID in
            ColleagueDetailView(userID: userID)
        }
    }

    private var labelFilterBar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showLabels.toggle()
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Labels")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if !selectedLabelIDs.isEmpty {
                        Text("\(selectedLabelIDs.count) aktiv")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.Palette.accent)
                    }
                    Spacer()
                    Image(systemName: showLabels ? "chevron.down" : "chevron.up")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showLabels {
                FlowLayout(spacing: Theme.Spacing.sm) {
                    ForEach(labels) { label in
                        Button {
                            if selectedLabelIDs.contains(label.id) {
                                selectedLabelIDs.remove(label.id)
                            } else {
                                selectedLabelIDs.insert(label.id)
                            }
                        } label: {
                            Text(label.name)
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, Theme.Spacing.lg)
                                .padding(.vertical, Theme.Spacing.sm)
                                .background(Color(hex: label.color) ?? .secondary.opacity(0.15), in: Capsule())
                                .foregroundStyle(foregroundForLabel(label))
                        }
                        .buttonStyle(.plain)
                        .overlay(
                            Capsule().strokeBorder(selectedLabelIDs.contains(label.id) ? Theme.Palette.accent : .clear, lineWidth: 2)
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, Theme.Spacing.md)
        .background(.bar)
    }

    private func foregroundForLabel(_ label: Resources_Jobs_Labels_Label) -> Color {
        if let color = Color(hex: label.color) {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
            return luminance > 0.6 ? .black : .white
        }
        return .primary
    }

    // MARK: - Loading

    private func loadLabels() async {
        do {
            labels = try await appState.getColleagueLabels()
        } catch {
            labels = []
        }
    }

    private func load(page: Int64 = 0, reset: Bool = false) async {
        let target = reset ? 0 : page
        if reset { currentPage = 0 }
        let previous = currentPage
        currentPage = target
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = try await appState.listColleagues(
                search: query,
                absent: onlyAbsent ? true : nil,
                labelIds: selectedLabelIDs.sorted(),
                offset: target * Self.pageSize,
                pageSize: Self.pageSize
            )
            colleagues = response.colleagues
            totalCount = response.pagination.totalCount
        } catch {
            errorMessage = error.localizedDescription
            currentPage = previous
        }
    }
}

/// One row in the colleagues list: name, rank, absence and labels.
private struct ColleagueRow: View {
    let colleague: Resources_Jobs_Colleagues_Colleague
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            GradientIconTile("person.crop.circle.fill", gradient: FiveNetModule.jobs.gradient, size: 44)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(colleagueName(colleague))
                        .font(.headline)
                        .lineLimit(1)
                    if isSelf {
                        Text("Du")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xxs)
                            .background(Theme.Palette.accent.opacity(0.15), in: Capsule())
                    }
                }

                if !gradeLabel.isEmpty {
                    Text(gradeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let summary = absenceSummary {
                    Label(summary, systemImage: "calendar.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            if !colleague.props.labels.list.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(colleague.props.labels.list.prefix(2)) { label in
                        Circle()
                            .fill(Color(hex: label.color) ?? .secondary)
                            .frame(width: 10, height: 10)
                    }
                    if colleague.props.labels.list.count > 2 {
                        Text("+\(colleague.props.labels.list.count - 2)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }

    private var isSelf: Bool {
        colleague.userID == appState.activeCharacterUserID
    }

    private var gradeLabel: String {
        colleague.jobGradeLabel
    }

    private var absenceSummary: String? {
        guard colleague.props.hasAbsenceEnd else { return nil }
        let date = colleague.props.absenceEnd.timestamp.date
        guard date > Date() else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

#Preview {
    NavigationStack {
        ColleaguesListView()
            .environment(AppState())
    }
}
