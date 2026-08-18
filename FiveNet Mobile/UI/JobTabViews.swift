import SwiftUI
import SwiftProtobuf

// MARK: - Aktivität (globaler Feed)

/// Global colleague activity feed with type filter and pagination.
/// Mirrors the web `pages/jobs/activity.vue` → `ActivityFeed.vue`.
struct JobActivityFeedView: View {
    @Environment(AppState.self) private var appState

    private static let pageSize: Int64 = 20

    @State private var activity: [Resources_Jobs_Colleagues_Activity_ColleagueActivity] = []
    @State private var selectedType: Resources_Jobs_Colleagues_Activity_ColleagueActivityType = .unspecified
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentPage: Int64 = 0
    @State private var totalCount: Int64 = 0
    @State private var hasLoaded = false

    private var totalPages: Int64 {
        max(1, Int64(ceil(Double(totalCount) / Double(Self.pageSize))))
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .cardRow()
                }
            }

            if isLoading && activity.isEmpty {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonListRow()
                }
            } else if activity.isEmpty {
                EmptyStateView(
                    "list.bullet",
                    color: Theme.Palette.accent,
                    title: "Keine Aktivität",
                    message: "Für diesen Filter ist noch keine Aktivität vorhanden."
                )
            } else {
                Section {
                    ForEach(activity) { entry in
                        JobActivityRow(entry: entry, previousGrade: gradeLookup[entry.id])
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
        .navigationTitle("Aktivität")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(activityTypes, id: \.rawValue) { type in
                        Button {
                            selectedType = type
                            Task { await load(reset: true) }
                        } label: {
                            if selectedType == type {
                                Label(type.title, systemImage: type.icon)
                            } else {
                                Text(type.title)
                            }
                        }
                    }
                    Button(role: .destructive) {
                        selectedType = .unspecified
                        Task { await load(reset: true) }
                    } label: {
                        Text("Alle anzeigen")
                    }
                } label: {
                    Label(filterLabel, systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .refreshable { await load(reset: true) }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await load(reset: true)
        }
    }

    private var activityTypes: [Resources_Jobs_Colleagues_Activity_ColleagueActivityType] {
        [.hired, .fired, .promoted, .demoted, .absenceDate, .note, .labels, .name]
    }

    /// The web client always sends the full set of activity types it has access
    /// to. The server returns an EMPTY response when `activityTypes` is empty
    /// (colleagues.go), so "Alle anzeigen" must send all known types instead of [].
    private var requestActivityTypes: [Resources_Jobs_Colleagues_Activity_ColleagueActivityType] {
        selectedType == .unspecified ? activityTypes : [selectedType]
    }

    private var filterLabel: String {
        guard selectedType != .unspecified else { return "Filter" }
        return selectedType.title
    }

    private var gradeLookup: [Int64: Int32] {
        previousGradeLookup(for: activity)
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
            let response = try await appState.listColleagueActivity(
                activityTypes: requestActivityTypes,
                offset: target * Self.pageSize,
                pageSize: Self.pageSize
            )
            activity = response.activity
            totalCount = response.pagination.totalCount
        } catch {
            errorMessage = error.localizedDescription
            currentPage = previous
        }
    }
}

/// One row in the global colleague activity feed.
private struct JobActivityRow: View {
    let entry: Resources_Jobs_Colleagues_Activity_ColleagueActivity
    let previousGrade: Int32?

    init(entry: Resources_Jobs_Colleagues_Activity_ColleagueActivity, previousGrade: Int32? = nil) {
        self.entry = entry
        self.previousGrade = previousGrade
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            IconTile(entry.activityType.icon, color: Theme.Palette.accent, size: 36)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(titleText)
                    .font(.subheadline.weight(.medium))
                Text(colleagueActivitySubtitle(entry, previousGrade: previousGrade))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(Theme.Spacing.xl)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private var titleText: String {
        colleagueActivityHeadline(entry, previousGrade: previousGrade)
    }
}

// MARK: - Stempeluhr

/// Stempeluhr entry view with three sub-tabs: own service time (with time range
/// filter), the colleagues view, and inactive colleagues. Mirrors the web
/// timeclock navigation (`/jobs/timeclock/*`).
struct JobTimeclockTabsView: View {
    @Environment(AppState.self) private var appState

    private enum Tab: String, CaseIterable, Identifiable {
        case own
        case colleagues
        case inactive

        var id: String { rawValue }

        var label: String {
            switch self {
            case .own: return "Eigene Dienstzeit"
            case .colleagues: return "Kollegium"
            case .inactive: return "Inaktive Kollegen"
            }
        }
    }

    @State private var selectedTab: Tab = .own

    var body: some View {
        // The sub-views are Lists themselves, so this wrapper must NOT nest them
        // inside another List — a List inside a List row is undefined in SwiftUI
        // (empty/broken rows). The picker sits above, the child lists below.
        VStack(spacing: 0) {
            PillTabBar(tabs: Tab.allCases, selection: $selectedTab) { $0.label }
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.sm)

            switch selectedTab {
            case .own:
                JobTimeclockView(userID: nil, forceViewMode: .self_)
            case .colleagues:
                JobTimeclockView(userID: nil, forceViewMode: .all)
            case .inactive:
                JobInactiveColleaguesView()
            }
        }
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle("Stempeluhr")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Timeclock listing with day/weekly/range modes and total sum.
/// Mirrors the web `components/jobs/timeclock/List.vue`.
///
/// When used inside the timeclock sub-tabs (`JobTimeclockTabsView`) the caller
/// passes `forceViewMode` so the "Eigene"/"Kollegium" split is handled by the
/// parent. When `userID` is set (colleague detail) only that user is shown.
struct JobTimeclockView: View {
    @Environment(AppState.self) private var appState

    private static let pageSize: Int64 = 20

    /// When set, only this colleague's entries are loaded (colleague detail).
    let userID: Int32?

    /// Locks the view mode (own vs. all) when used inside the sub-tab view.
    private let forceViewMode: Resources_Jobs_Timeclock_TimeclockViewMode?

    @State private var mode: Resources_Jobs_Timeclock_TimeclockMode = .range
    @State private var viewMode: Resources_Jobs_Timeclock_TimeclockViewMode = .all
    @State private var perDay = false
    @State private var startDate = Date().addingTimeInterval(-7 * 86400)
    @State private var endDate = Date()
    @State private var entries: [Resources_Jobs_Timeclock_TimeclockEntry] = []
    @State private var totalSum: Int64 = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasLoaded = false

    init(userID: Int32?, forceViewMode: Resources_Jobs_Timeclock_TimeclockViewMode? = nil) {
        self.userID = userID
        self.forceViewMode = forceViewMode
        _viewMode = State(initialValue: forceViewMode ?? .all)
    }

    private var effectiveViewMode: Resources_Jobs_Timeclock_TimeclockViewMode {
        forceViewMode ?? viewMode
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .cardRow()
                }
            }

            Section("Zeitraum") {
                SectionCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        DatePicker("Von", selection: $startDate, displayedComponents: .date)
                        Divider()
                        DatePicker("Bis", selection: $endDate, displayedComponents: .date)
                        Divider()
                        Button {
                            let today = Calendar.current.startOfDay(for: Date())
                            startDate = today
                            endDate = today
                            mode = .range
                            Task { await load() }
                        } label: {
                            Label("Heutigen Tag auswerten", systemImage: "calendar.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.accent)
                        .padding(.top, Theme.Spacing.md)
                    }
                }
                .cardRow()
            }

            Section("Ansicht") {
                SectionCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        if userID == nil, forceViewMode == nil {
                            Picker("Ansicht", selection: $viewMode) {
                                ForEach(viewModes, id: \.rawValue) { vm in
                                    Text(vm.label).tag(vm)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Picker("Modus", selection: $mode) {
                            ForEach(modes, id: \.rawValue) { m in
                                Text(m.label).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)

                        if mode != .timeline {
                            Divider()
                            Toggle("Pro Tag anzeigen", isOn: $perDay)
                        }
                    }
                }
                .cardRow()
            }

            if isLoading && entries.isEmpty {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonListRow()
                }
            } else if entries.isEmpty {
                EmptyStateView(
                    "clock.badge.checkmark",
                    color: Theme.Palette.accent,
                    title: "Keine Einträge",
                    message: "Für diesen Zeitraum sind keine Stempeluhr-Einträge vorhanden."
                )
            } else {
                Section("Einträge · Summe: \(formatDuration(seconds: totalSum))") {
                    ForEach(entries) { entry in
                        timeclockRow(entry)
                            .cardRow()
                    }
                }
            }
        }
        .cardListStyle()
        .contentMargins(.top, Theme.Spacing.xl, for: .scrollContent)
        .navigationTitle("Stempeluhr")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: mode) { Task { await load() } }
        .onChange(of: viewMode) {
            if !modes.contains(mode) {
                mode = modes.first ?? .range
            }
            Task { await load() }
        }
        .onChange(of: perDay) { Task { await load() } }
        .refreshable { await load() }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await load()
        }
    }

    /// View modes (Eigene/Kollegium). The colleague detail always shows all
    /// colleagues of that user, so only the main timeclock tab can switch.
    private var viewModes: [Resources_Jobs_Timeclock_TimeclockViewMode] {
        [.self_, .all]
    }

    private var modes: [Resources_Jobs_Timeclock_TimeclockMode] {
        if effectiveViewMode == .self_ {
            // Web (List.vue) restricts the mode tabs in the "Eigene" view to
            // RANGE and TIMELINE.
            return [.range, .timeline]
        }
        if userID != nil {
            return [.daily, .weekly, .range]
        }
        return [.daily, .weekly, .range, .timeline]
    }

    @ViewBuilder
    private func timeclockRow(_ entry: Resources_Jobs_Timeclock_TimeclockEntry) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            GradientIconTile(
                entry.hasEndTime ? "clock.fill" : "bolt.fill",
                gradient: FiveNetModule.jobs.gradient,
                size: 36
            )
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if entry.hasUser {
                    Text(colleagueName(entry.user))
                        .font(.subheadline.weight(.medium))
                }
                Text(dateLabel(for: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if !entry.hasEndTime, entry.hasStartTime {
                Text("Aktiv")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.success)
            } else {
                Text(formatSpentTime(hours: entry.spentTime))
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(Theme.Spacing.xl)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private func dateLabel(for entry: Resources_Jobs_Timeclock_TimeclockEntry) -> String {
        var parts: [String] = []
        if entry.hasStartTime, entry.startTime.timestamp.date.timeIntervalSince1970 > 0 {
            parts.append(entry.startTime.timestamp.date.formatted(date: .abbreviated, time: .shortened))
        }
        if entry.hasEndTime, entry.endTime.timestamp.date.timeIntervalSince1970 > 0 {
            parts.append("→ \(entry.endTime.timestamp.date.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: " ")
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var userIds: [Int32] = []
            if let userID {
                userIds = [userID]
            }
            let response = try await appState.listTimeclock(
                userMode: effectiveViewMode,
                mode: mode,
                perDay: perDay,
                userIds: userIds,
                start: startDate,
                end: endDate,
                pageSize: Self.pageSize
            )
            switch response.entries {
            case .daily(let day):
                entries = day.entries
                totalSum = day.sum
            case .weekly(let week):
                entries = week.entries
                totalSum = week.sum
            case .range(let range):
                entries = range.entries
                totalSum = range.sum
            case .none:
                entries = []
                totalSum = 0
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Führungsregister

/// Conduct register listing with type filter.
/// Mirrors the web `components/jobs/conduct/List.vue`.
struct JobConductListView: View {
    @Environment(AppState.self) private var appState

    private static let pageSize: Int64 = 20

    /// When set, only entries for this colleague are loaded (colleague detail).
    let userID: Int32?

    @State private var entries: [Resources_Jobs_Conduct_ConductEntry] = []
    @State private var selectedType: Resources_Jobs_Conduct_ConductType = .unspecified
    @State private var showExpired = false
    @State private var showDrafts = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentPage: Int64 = 0
    @State private var totalCount: Int64 = 0
    @State private var hasLoaded = false
    @State private var showCreateSheet = false
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?

    private var totalPages: Int64 {
        max(1, Int64(ceil(Double(totalCount) / Double(Self.pageSize))))
    }

    private var canCreate: Bool {
        appState.can("jobs.ConductService/CreateConductEntry")
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
                                TextField("Eintrag oder #ID suchen", text: $searchText)
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

                if canCreate {
                    Section {
                        Button {
                            showCreateSheet = true
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(FiveNetModule.jobs.tint)
                                Text("Neuen Eintrag erstellen")
                                    .foregroundStyle(.primary)
                                Spacer()
                                CardChevron()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(Theme.Spacing.xl)
                        .background(
                            Theme.Palette.surface,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        )
                        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                        .cardRow()
                    }
                }

                Section("Ansicht") {
                    SectionCard {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            Toggle("Abgelaufene anzeigen", isOn: $showExpired)
                            Divider()
                            Toggle("Entwürfe anzeigen", isOn: $showDrafts)
                        }
                    }
                    .cardRow()
                }

                if isLoading && entries.isEmpty {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonListRow()
                    }
                } else if entries.isEmpty {
                    EmptyStateView(
                        "list.clipboard",
                        color: Theme.Palette.accent,
                        title: "Keine Einträge",
                        message: "Für diese Filter sind keine Führungsregister-Einträge vorhanden."
                    )
                } else {
                    Section("\(totalCount) Einträge") {
                        ForEach(entries) { entry in
                            NavigationLink(value: ConductRoute(entryID: entry.id)) {
                                conductRow(entry)
                            }
                            .buttonStyle(.plain)
                            .navigationLinkIndicatorVisibility(.hidden)
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
            .navigationTitle("Führungsregister")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(conductTypes, id: \.rawValue) { type in
                            Button {
                                selectedType = type
                                Task { await load(reset: true) }
                            } label: {
                                if selectedType == type {
                                    Label(type.label, systemImage: type.icon)
                                } else {
                                    Text(type.label)
                                }
                            }
                        }
                        Button(role: .destructive) {
                            selectedType = .unspecified
                            Task { await load(reset: true) }
                        } label: {
                            Text("Alle anzeigen")
                        }
                    } label: {
                        Label(filterLabel, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateConductEntrySheet(presetUserID: userID)
                    .environment(appState)
            }
            .onChange(of: showCreateSheet) {
                if !showCreateSheet {
                    Task { await load(reset: true) }
                }
            }
            .onChange(of: showExpired) { Task { await load(reset: true) } }
            .onChange(of: showDrafts) { Task { await load(reset: true) } }
            .refreshable { await load(reset: true) }
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                await load(reset: true)
            }
        }
    }

    private var conductTypes: [Resources_Jobs_Conduct_ConductType] {
        [.neutral, .positive, .negative, .warning, .suspension, .note]
    }

    private var filterLabel: String {
        guard selectedType != .unspecified else { return "Filter" }
        return selectedType.label
    }

    @ViewBuilder
    private func conductRow(_ entry: Resources_Jobs_Conduct_ConductEntry) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(entry.type.tint)
                .frame(width: 5, height: 40)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.md) {
                    Text("#\(entry.id)")
                        .font(.subheadline.weight(.semibold))

                    Text(entry.type.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(entry.type.tint)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xxs)
                        .background(entry.type.tint.opacity(0.15), in: Capsule())

                    Spacer()

                    if entry.draft {
                        Text("Entwurf")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xxs)
                            .background(Theme.Palette.warning.opacity(0.2), in: Capsule())
                    }

                    if entry.hasExpiresAt, isExpired(entry) {
                        Text("Abgelaufen")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xxs)
                            .background(Theme.Palette.danger.opacity(0.2), in: Capsule())
                    }
                }

                if !conductMessagePreview(entry).isEmpty {
                    Text(conductMessagePreview(entry))
                        .font(.subheadline)
                        .lineLimit(2)
                }

                Text(metaText(for: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            CardChevron()
                .padding(.leading, Theme.Spacing.md)
        }
        .padding(Theme.Spacing.xl)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private func metaText(for entry: Resources_Jobs_Conduct_ConductEntry) -> String {
        var parts: [String] = []
        if entry.hasCreatedAt, entry.createdAt.timestamp.date.timeIntervalSince1970 > 0 {
            parts.append(formatTimestamp(entry.createdAt))
        }
        if entry.hasTargetUser {
            parts.append("für \(colleagueName(entry.targetUser))")
        }
        if entry.hasCreator {
            parts.append("von \(colleagueName(entry.creator))")
        }
        return parts.joined(separator: " · ")
    }

    private func isExpired(_ entry: Resources_Jobs_Conduct_ConductEntry) -> Bool {
        entry.hasExpiresAt && entry.expiresAt.timestamp.date < Date()
    }

    /// Crude HTML → plain text preview of the entry content.
    private func conductMessagePreview(_ entry: Resources_Jobs_Conduct_ConductEntry) -> String {
        let html = entry.message.rawHtml
        guard !html.isEmpty else { return "" }
        let text = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\"", with: "\u{00A0}\u{00A0}\u{00A0}")
        let cleaned = text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
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
            let types: [Resources_Jobs_Conduct_ConductType] =
                selectedType == .unspecified ? [] : [selectedType]
            let userIds: [Int32] = userID.map { [$0] } ?? []
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let ids: [Int64] = Int64(query).map { [$0] } ?? []

            if !ids.isEmpty {
                let response = try await appState.listConductEntries(
                    types: types,
                    userIds: userIds,
                    showExpired: showExpired ? true : nil,
                    showDrafts: showDrafts ? true : nil,
                    ids: ids,
                    offset: target * Self.pageSize,
                    pageSize: Self.pageSize
                )
                entries = response.entries
                totalCount = response.pagination.totalCount
                return
            }

            // Empty search: plain paginated listing of all entries (the server
            // filters nothing here, so pagination and totals stay intact).
            if query.isEmpty {
                let response = try await appState.listConductEntries(
                    types: types,
                    userIds: userIds,
                    showExpired: showExpired ? true : nil,
                    showDrafts: showDrafts ? true : nil,
                    offset: target * Self.pageSize,
                    pageSize: Self.pageSize
                )
                entries = response.entries
                totalCount = response.pagination.totalCount
                return
            }

            // Text search: the server has no `search` field, so walk the pages
            // until we have a full page of matches (capped at 400 entries).
            let queryLower = query.lowercased()
            var matches: [Resources_Jobs_Conduct_ConductEntry] = []
            var offset: Int64 = 0
            var fetched: Int64 = 0
            while matches.count < Self.pageSize {
                let response = try await appState.listConductEntries(
                    types: types,
                    userIds: userIds,
                    showExpired: showExpired ? true : nil,
                    showDrafts: showDrafts ? true : nil,
                    offset: offset,
                    pageSize: Self.pageSize
                )
                let pageEntries = response.entries
                if pageEntries.isEmpty { break }
                matches.append(contentsOf: pageEntries.filter { matchesQuery($0, queryLower) })
                fetched += Int64(pageEntries.count)
                offset += Int64(pageEntries.count)
                if fetched >= 400 { break }
            }
            totalCount = Int64(matches.count)
            let start = min(Int(target * Self.pageSize), matches.count)
            entries = Array(matches.dropFirst(start).prefix(Int(Self.pageSize)))
        } catch {
            errorMessage = error.localizedDescription
            currentPage = previous
        }
    }

    private func matchesQuery(_ entry: Resources_Jobs_Conduct_ConductEntry, _ queryLower: String) -> Bool {
        if "\(entry.id)".contains(queryLower) { return true }
        if conductMessagePreview(entry).lowercased().contains(queryLower) { return true }
        if entry.hasTargetUser, colleagueName(entry.targetUser).lowercased().contains(queryLower) { return true }
        if entry.hasCreator, colleagueName(entry.creator).lowercased().contains(queryLower) { return true }
        return false
    }
}

// MARK: - Inaktive Kollegen

/// Colleagues without a timeclock entry within the last `days` days.
/// Mirrors the web `pages/jobs/timeclock/inactive.vue` (`InactiveList.vue`).
struct JobInactiveColleaguesView: View {
    @Environment(AppState.self) private var appState

    private static let pageSize: Int64 = 20

    @State private var days: Int32 = 14
    @State private var colleagues: [Resources_Jobs_Colleagues_Colleague] = []
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
                if let errorMessage {
                    Section {
                        StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .cardRow()
                    }
                }

                Section("Zeitraum") {
                    SectionCard {
                        Picker("Inaktiv seit", selection: $days) {
                            ForEach([7, 14, 30] as [Int32], id: \.self) { value in
                                Text("\(value) Tage").tag(value)
                            }
                        }
                    }
                    .cardRow()
                }

                if isLoading && colleagues.isEmpty {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonListRow()
                    }
                } else if colleagues.isEmpty {
                    EmptyStateView(
                        "person.crop.circle.badge.checkmark",
                        color: Theme.Palette.accent,
                        title: "Keine inaktiven Kollegen",
                        message: "Alle Kollegen waren in diesem Zeitraum im Dienst."
                    )
                } else {
                    Section("\(totalCount) inaktive Kollegen") {
                        ForEach(colleagues) { colleague in
                            NavigationLink(value: ColleagueRoute(userID: colleague.userID)) {
                                inactiveRow(colleague)
                            }
                            .buttonStyle(.plain)
                            .navigationLinkIndicatorVisibility(.hidden)
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
            .navigationTitle("Inaktive Kollegen")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: days) {
                Task { await load(reset: true) }
            }
            .refreshable { await load(reset: true) }
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                await load(reset: true)
            }
        }
    }

    @ViewBuilder
    private func inactiveRow(_ colleague: Resources_Jobs_Colleagues_Colleague) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            GradientIconTile("person.crop.circle.fill", gradient: FiveNetModule.jobs.gradient, size: 40)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(colleagueName(colleague))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !colleague.jobGradeLabel.isEmpty {
                    Text(colleague.jobGradeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !colleague.phoneNumber.isEmpty {
                    Label(formatPhoneNumber(colleague.phoneNumber), systemImage: "phone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            CardChevron()
                .padding(.leading, Theme.Spacing.md)
        }
        .padding(Theme.Spacing.xl)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
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
            let response = try await appState.listInactiveEmployees(
                days: days,
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

// MARK: - Führungsregister-Detail

/// Detail view for a single conduct register entry (`Führungsregister`).
/// Renders the entry content via `WikiContentView` and links the involved
/// colleagues to their colleague detail.
struct ConductEntryDetailView: View {
    @Environment(AppState.self) private var appState

    let entryID: Int64

    @State private var entry: Resources_Jobs_Conduct_ConductEntry?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let entry {
                detailContent(entry)
            } else if isLoading {
                ScrollView {
                    SkeletonDetailView()
                }
            } else {
                EmptyStateView(
                    "exclamationmark.triangle.fill",
                    color: Theme.Palette.danger,
                    title: "Eintrag nicht verfügbar",
                    message: errorMessage ?? "Der Eintrag konnte nicht geladen werden."
                )
            }
        }
        .navigationTitle("Führungsregister")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func detailContent(_ entry: Resources_Jobs_Conduct_ConductEntry) -> some View {
        List {
            detailHeroSection(DetailHero(
                gradient: FiveNetModule.jobs.gradient,
                icon: "list.clipboard.fill",
                title: "#\(entry.id)",
                subtitle: entry.type.label,
                badges: conductHeroBadges(entry)
            ))

            Section("Person") {
                SectionCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        if entry.hasTargetUser {
                            NavigationLink(value: ColleagueRoute(userID: entry.targetUser.userID)) {
                                HStack(alignment: .top) {
                                    Label("Ziel", systemImage: "person.fill")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    colleagueBadge(entry.targetUser)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }
                        if entry.hasCreator {
                            NavigationLink(value: ColleagueRoute(userID: entry.creator.userID)) {
                                HStack(alignment: .top) {
                                    Label("Erstellt von", systemImage: "person.badge.key")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    colleagueBadge(entry.creator)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }
                    }
                }
                .cardRow()
            }

            Section("Inhalt") {
                SectionCard {
                    WikiContentView(content: entry.message)
                }
                .cardRow()
            }

            Section("Details") {
                SectionCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        if entry.hasCreatedAt, entry.createdAt.timestamp.date.timeIntervalSince1970 > 0 {
                            LabeledContent("Erstellt", value: formatTimestamp(entry.createdAt))
                        }
                        if entry.hasUpdatedAt, entry.updatedAt.timestamp.date.timeIntervalSince1970 > 0 {
                            LabeledContent("Aktualisiert", value: formatTimestamp(entry.updatedAt))
                        }
                        if entry.hasExpiresAt, entry.expiresAt.timestamp.date.timeIntervalSince1970 > 0 {
                            LabeledContent("Gültig bis", value: formatTimestamp(entry.expiresAt))
                        }
                    }
                }
                .cardRow()
            }
        }
        .cardListStyle()
    }

    private func conductHeroBadges(_ entry: Resources_Jobs_Conduct_ConductEntry) -> [String] {
        var result: [String] = [entry.type.label]
        if entry.draft {
            result.append("Entwurf")
        }
        if entry.hasExpiresAt, entry.expiresAt.timestamp.date < Date() {
            result.append("Abgelaufen")
        }
        return result
    }

    @ViewBuilder
    private func colleagueBadge(_ colleague: Resources_Jobs_Colleagues_Colleague) -> some View {
        Text(colleagueName(colleague))
            .foregroundStyle(.primary)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await appState.getConductEntry(id: entryID)
            entry = response.hasEntry ? response.entry : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
