import SwiftUI
import SwiftProtobuf

/// Citizens module: full profile of a single citizen with an activity tab.
struct CitizenDetailView: View {
    @Environment(AppState.self) private var appState

    let userID: Int32

    @State private var user: Resources_Users_User?
    @State private var activity: [Resources_Users_Activity_UserActivity] = []
    @State private var documents: [Resources_Documents_Relations_DocumentRelation] = []
    @State private var checkVehicles: [Resources_Vehicles_Vehicle] = []
    @State private var isLoading = false
    @State private var isLoadingActivity = false
    @State private var isLoadingDocuments = false
    @State private var isLoadingVehicles = false
    @State private var errorMessage: String?
    @State private var activityError: String?
    @State private var documentsError: String?
    @State private var vehiclesError: String?
    @State private var copiedToClipboard = false
    @State private var selectedTab: CitizenTab = .profile

    private let identifierFormat = CitizenIDFormat()

    private enum CitizenTab: String, CaseIterable, Identifiable {
        case profile = "Profil"
        case check = "Einstellungsprüfung"

        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if let user {
                VStack(spacing: 0) {
                    PillTabBar(tabs: CitizenTab.allCases, selection: $selectedTab) { $0.rawValue }
                        .padding(.top, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.sm)

                    switch selectedTab {
                    case .profile:
                        profileContent(user)
                    case .check:
                        checkContent(user)
                    }
                }
                .background(Theme.Palette.background.ignoresSafeArea())
            } else if let errorMessage {
                EmptyStateView(
                    "exclamationmark.triangle",
                    color: Theme.Palette.danger,
                    title: "Laden fehlgeschlagen",
                    message: errorMessage,
                    actionTitle: "Erneut versuchen"
                ) {
                    Task { await load() }
                }
            } else {
                ScrollView {
                    SkeletonDetailView()
                }
            }
        }
        .navigationTitle(name(user))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let user {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.copyUserToClipboard(userShort(from: user))
                        copiedToClipboard = true
                    } label: {
                        Label("In Zwischenablage kopieren", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .toast(isPresented: $copiedToClipboard, message: "Kopiert")
        .navigationDestination(for: DocumentRoute.self) { route in
            DocumentDetailView(documentID: route.documentID)
        }
        .task {
            await load()
            await loadActivity()
            await loadDocuments()
            await loadCheckVehicles()
        }
    }

    /// Einstellungsprüfung ist über die Systemeinstellungen (Settings.bundle)
    /// konfigurierbar: Toggle `fivenetHiringCheckEnabled` + Haft-Rückblick
    /// `fivenetHiringCheckDays`.
    private var isHiringCheckEnabled: Bool {
        if UserDefaults.standard.object(forKey: "fivenetHiringCheckEnabled") != nil {
            return UserDefaults.standard.bool(forKey: "fivenetHiringCheckEnabled")
        }
        return true
    }

    private var hiringCheckDays: Int {
        if UserDefaults.standard.object(forKey: "fivenetHiringCheckDays") != nil {
            return max(1, min(UserDefaults.standard.integer(forKey: "fivenetHiringCheckDays"), 180))
        }
        return 30
    }

    private func profileContent(_ user: Resources_Users_User) -> some View {
        List {
            detailHeroSection(DetailHero(
                gradient: FiveNetModule.citizens.gradient,
                icon: "person.crop.circle.fill",
                title: name(user),
                subtitle: jobLine(user).isEmpty ? nil : jobLine(user),
                badges: citizenBadges(user)
            ))

            Section("Person") {
                labeledRow("Geburtsdatum", user.dateofbirth)
                labeledRow("Geschlecht", sexLabel(user.sex))
                if user.hasHeight {
                    labeledRow("Größe", String(format: "%.0f cm", user.height))
                }
                labeledRow("Blutgruppe", user.props.bloodType)
            }

            Section("Kontakt") {
                labeledRow("Telefon", formatPhoneNumber(primaryPhone(user)))
                labeledRow("E-Mail", user.props.email)
            }

            if user.props.openFines > 0 || user.props.trafficInfractionPoints > 0 {
                Section("Verwaltung") {
                    if user.props.openFines > 0 {
                        labeledRow("Offene Strafen", "\(user.props.openFines)")
                    }
                    if user.props.trafficInfractionPoints > 0 {
                        labeledRow("Punkte in Flensburg", "\(user.props.trafficInfractionPoints)")
                    }
                }
            }

            if !user.licenses.isEmpty {
                Section("Führerscheine") {
                    ForEach(user.licenses, id: \.type) { license in
                        Text(license.label)
                    }
                }
            }

            Section("Aktivität") {
                if let activityError {
                    Label(activityError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Palette.danger)
                } else if activity.isEmpty {
                    if isLoadingActivity {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        Text("Keine Aktivität vorhanden.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(activity, id: \.id) { entry in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: entry.type.icon)
                                    .font(.caption)
                                    .foregroundStyle(entry.type.color)
                                Text(entry.type.title)
                                    .font(.subheadline.weight(.medium))
                            }
                            if let subtitle = activitySubtitle(entry), !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, Theme.Spacing.xxs)
                    }
                }
            }

            Section("Dokumente") {
                if let documentsError {
                    Label(documentsError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Palette.danger)
                } else if documents.isEmpty {
                    if isLoadingDocuments {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        Text("Keine Dokumente verknüpft.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(documents, id: \.id) { relation in
                        if relation.hasDocument {
                            NavigationLink(value: DocumentRoute(documentID: relation.document.id)) {
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    Text(verbatim: "\(formatDocumentID(relation.document.id)) · \(relation.document.title)")
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(2)
                                    HStack(spacing: Theme.Spacing.xs) {
                                        Text(docRelationLabel(relation.relation))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        if relation.document.meta.closed {
                                            Text("Geschlossen")
                                                .font(.caption2.bold())
                                                .foregroundStyle(Theme.Palette.warning)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Einstellungsprüfung: gebündelte Polizei-Relevanz eines Bürgers
    /// (Einstellbar-Status, Fahndung inkl. Fahrzeug-Fahndung, Strafen,
    /// Punkte, Haft-Verlauf, verknüpfte Dokumente).
    private func checkContent(_ user: Resources_Users_User) -> some View {
        Group {
            if !isHiringCheckEnabled {
                EmptyStateView(
                    "person.text.rectangle",
                    color: Theme.Palette.accent,
                    title: "Einstellungsprüfung deaktiviert",
                    message: "Aktiviere die Einstellungsprüfung in den Systemeinstellungen, um alle Daten gebündelt zu sehen."
                )
            } else {
                List {
                    Section("Ergebnis") {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: jailHistory.isEmpty ? "checkmark.seal.fill" : "xmark.octagon.fill")
                                .foregroundStyle(jailHistory.isEmpty ? Theme.Palette.success : Theme.Palette.danger)
                            Text(jailHistory.isEmpty ? "Einstellbar" : "Nicht einstellbar")
                                .font(.headline)
                                .foregroundStyle(jailHistory.isEmpty ? Theme.Palette.success : Theme.Palette.danger)
                            Spacer()
                        }
                        .padding(.vertical, Theme.Spacing.xxs)
                        Text(jailHistory.isEmpty
                            ? "Keine Haft im Zeitraum der letzten \(hiringCheckDays) Tage."
                            : "Der Bürger wurde in den letzten \(hiringCheckDays) Tagen inhaftiert (\(jailHistory.count) Haft-Eintrag\(jailHistory.count == 1 ? "" : "e")).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Fahndung") {
                        labeledRow("Person gefahndet", user.props.wanted ? "GESUCHT" : "Nicht gesucht", valueColor: user.props.wanted ? Theme.Palette.danger : Theme.Palette.success)
                        if user.props.hasWantedAt {
                            labeledRow("Gesucht seit", formatDate(user.props.wantedAt))
                        }
                        if user.props.hasWantedTill {
                            labeledRow("Gesucht bis", formatDate(user.props.wantedTill))
                        }

                        if let vehiclesError {
                            Label(vehiclesError, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.Palette.danger)
                        } else {
                            let wantedVehicles = checkVehicles.filter { $0.props.wanted }
                            if wantedVehicles.isEmpty {
                                if isLoadingVehicles {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                        Spacer()
                                    }
                                } else {
                                    labeledRow("Fahrzeug-Fahndung", "Keine Fahrzeuge gesucht")
                                }
                            } else {
                                ForEach(wantedVehicles, id: \.plate) { vehicle in
                                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                        HStack(spacing: Theme.Spacing.sm) {
                                            Text("Fahrzeug-Fahndung")
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text(vehicle.plate)
                                                .font(.subheadline.weight(.semibold))
                                                .monospaced()
                                            Text("GESUCHT")
                                                .font(.caption2.bold())
                                                .foregroundStyle(Theme.Palette.danger)
                                        }
                                        if vehicle.props.hasWantedReason && !vehicle.props.wantedReason.isEmpty {
                                            Text(vehicle.props.wantedReason)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, Theme.Spacing.xxs)
                                }
                            }
                        }
                    }

                    Section("Verwaltung") {
                        labeledRow("Offene Strafen", "\(user.props.openFines)")
                        labeledRow("Punkte in Flensburg", "\(user.props.trafficInfractionPoints)")
                    }

                    Section("Haft-Verlauf (\(hiringCheckDays) Tage)") {
                        if let activityError {
                            Label(activityError, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.Palette.danger)
                        } else {
                            let jailEntries = jailHistory
                            if jailEntries.isEmpty {
                                if isLoadingActivity {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                        Spacer()
                                    }
                                } else {
                                    Text("Keine Haft im Zeitraum.")
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                ForEach(jailEntries, id: \.id) { entry in
                                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                        HStack {
                                            Text(formatDuration(seconds: Int64(entry.data.jailChange.seconds)))
                                                .font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Text(formatDate(entry.createdAt))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if entry.data.jailChange.hasLocation && !entry.data.jailChange.location.isEmpty {
                                            Text(entry.data.jailChange.location)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if !entry.reason.isEmpty {
                                            Text(entry.reason)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, Theme.Spacing.xxs)
                                }
                            }
                        }
                    }

                    Section("Dokumente") {
                        let documentLinks = documentRelations
                        if documentLinks.isEmpty {
                            if isLoadingActivity {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                    Spacer()
                                }
                            } else {
                                Text("Keine Dokumente verknüpft.")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(Array(documentLinks.enumerated()), id: \.offset) { _, entry in
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    HStack(spacing: Theme.Spacing.xs) {
                                        Image(systemName: entry.data.documentRelation.added ? "link" : "link.badge.plus")
                                            .font(.caption)
                                            .foregroundStyle(FiveNetModule.documents.tint)
                                        Text(verbatim: "\(formatDocumentID(entry.data.documentRelation.documentID))")
                                            .font(.subheadline.weight(.semibold))
                                            .monospaced()
                                        Spacer()
                                        if entry.data.documentRelation.added {
                                            Text("Bürger zugehörig zu")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("Nicht mehr zugehörig")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    HStack(spacing: Theme.Spacing.xs) {
                                        Text(docRelationLabel(entry.data.documentRelation.relation))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(formatRelative(entry.createdAt))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, Theme.Spacing.xxs)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    /// Haft-Einträge aus der Aktivität innerhalb des konfigurierten Rückblicks.
    private var jailHistory: [Resources_Users_Activity_UserActivity] {
        guard hiringCheckDays > 0 else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day, value: -hiringCheckDays, to: Date()) ?? Date()
        return activity
            .filter { $0.type == .jail && $0.hasCreatedAt && $0.createdAt.timestamp.date >= cutoff }
            .sorted { lhs, rhs in lhs.createdAt.timestamp.date > rhs.createdAt.timestamp.date }
    }

    /// Dokument-Verknüpfungen aus der Aktivität (Dokument-ID ist auch ohne
    /// Dokument-Zugriff sichtbar — Web `ActivityFeed.vue` „Bürger zugehörig
    /// zu DOC-…“). Neueste zuerst.
    private var documentRelations: [Resources_Users_Activity_UserActivity] {
        activity
            .filter { $0.type == .document && $0.hasData && $0.data.data != nil }
            .sorted { lhs, rhs in lhs.createdAt.timestamp.date > rhs.createdAt.timestamp.date }
    }

    private func formatDate(_ timestamp: Resources_Timestamp_Timestamp) -> String {
        timestamp.timestamp.date.formatted(date: .abbreviated, time: .omitted)
    }

    private func docRelationLabel(_ relation: Resources_Documents_Relations_DocRelation) -> String {
        switch relation {
        case .mentioned: return "Erwähnt"
        case .targets: return "Ziel"
        case .caused: return "Verursacht"
        case .unspecified, .UNRECOGNIZED: return "Verknüpft"
        }
    }

    private func sexLabel(_ sex: String) -> String {
        switch sex.lowercased() {
        case "m", "male", "männlich", "man": return "männlich"
        case "f", "female", "weiblich", "woman": return "Weiblich"
        case "d", "divers", "other": return "divers"
        default: return sex
        }
    }

    /// Builds a readable subtitle for an activity entry.
    private func activitySubtitle(_ entry: Resources_Users_Activity_UserActivity) -> String? {
        var parts: [String] = []
        let source = shortName(entry.sourceUser)
        if !source.isEmpty { parts.append(source) }
        if !entry.key.isEmpty { parts.append(entry.key) }
        if !entry.reason.isEmpty { parts.append(entry.reason) }
        if !entry.oldValue.isEmpty || !entry.newValue.isEmpty {
            if entry.oldValue.isEmpty {
                parts.append("→ \(entry.newValue)")
            } else {
                parts.append("\(entry.oldValue) → \(entry.newValue)")
            }
        }
        if entry.hasCreatedAt {
            parts.append(formatRelative(entry.createdAt))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func shortName(_ short: Resources_Users_Short_UserShort) -> String {
        let name = [short.firstname, short.lastname].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "" : name
    }

    private func labeledRow(_ label: String, _ value: String, valueColor: Color? = nil) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .foregroundStyle(value.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(valueColor ?? .primary))
                .multilineTextAlignment(.trailing)
        }
    }

    private func primaryPhone(_ user: Resources_Users_User) -> String {
        if let primary = user.phoneNumbers.first(where: { $0.isPrimary }), !primary.number.isEmpty {
            return primary.number
        }
        return user.phoneNumber
    }

    private func name(_ user: Resources_Users_User?) -> String {
        guard let user else { return "Profil" }
        let name = [user.firstname, user.lastname]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? "Bürger" : name
    }

    private func jobLine(_ user: Resources_Users_User) -> String {
        var parts: [String] = []
        if !user.jobLabel.isEmpty { parts.append(user.jobLabel) }
        if !user.jobGradeLabel.isEmpty { parts.append(user.jobGradeLabel) }
        return parts.joined(separator: " · ")
    }

    private func citizenBadges(_ user: Resources_Users_User) -> [String] {
        var result: [String] = []
        if let id = identifierFormat.idString(for: user) {
            result.append(id)
        }
        if user.props.wanted {
            result.append("GESUCHT")
        }
        return result
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            user = try await appState.getCitizen(userID: userID)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadActivity() async {
        guard !isLoadingActivity else { return }
        isLoadingActivity = true
        activityError = nil
        defer { isLoadingActivity = false }
        do {
            let response = try await appState.listUserActivity(userID: userID, pageSize: 100)
            activity = response.activity
        } catch {
            activityError = error.localizedDescription
        }
    }

    private func loadDocuments() async {
        guard !isLoadingDocuments else { return }
        isLoadingDocuments = true
        documentsError = nil
        defer { isLoadingDocuments = false }
        do {
            documents = try await appState.listUserDocuments(userID: userID)
        } catch {
            documentsError = error.localizedDescription
        }
    }

    private func loadCheckVehicles() async {
        guard !isLoadingVehicles else { return }
        isLoadingVehicles = true
        vehiclesError = nil
        defer { isLoadingVehicles = false }
        do {
            let response = try await appState.listVehicles(userIds: [userID], pageSize: 50)
            checkVehicles = response.vehicles
        } catch {
            vehiclesError = error.localizedDescription
        }
    }
}

extension Resources_Users_Activity_UserActivityType {
    /// SF Symbol shown for this activity type.
    var icon: String {
        switch self {
        case .name: return "person.crop.circle.badge.checkmark"
        case .licenses: return "card"
        case .wanted: return "exclamationmark.triangle.fill"
        case .trafficInfractionPoints: return "signpost.right"
        case .mugshot: return "face.smiling"
        case .labels: return "tag"
        case .job: return "briefcase"
        case .document: return "doc.text"
        case .jail: return "lock.fill"
        case .fine: return "dollarsign.circle"
        case .unspecified, .UNRECOGNIZED: return "clock"
        }
    }

    /// Accent color for the activity row.
    var color: Color {
        switch self {
        case .name: return .blue
        case .licenses: return .indigo
        case .wanted, .jail, .fine: return .red
        case .trafficInfractionPoints: return .orange
        case .mugshot: return .pink
        case .labels: return .teal
        case .job: return .green
        case .document: return .purple
        case .unspecified, .UNRECOGNIZED: return .secondary
        }
    }

    /// German past-tense title for the activity row.
    var title: String {
        switch self {
        case .name: return "Name geändert"
        case .licenses: return "Führerscheine geändert"
        case .wanted: return "Fahndung geändert"
        case .trafficInfractionPoints: return "Flensburg-Punkte geändert"
        case .mugshot: return "Mugshot geändert"
        case .labels: return "Labels geändert"
        case .job: return "Beruf geändert"
        case .document: return "Dokument verknüpft"
        case .jail: return "Haft geändert"
        case .fine: return "Strafe geändert"
        case .unspecified, .UNRECOGNIZED: return "Aktivität"
        }
    }
}

#Preview {
    NavigationStack {
        CitizenDetailView(userID: 1)
            .environment(AppState())
    }
}
