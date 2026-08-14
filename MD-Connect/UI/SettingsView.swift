import SwiftUI
import SwiftProtobuf

/// Unter-Routen des Einstellungen-Moduls (Beruf, Rollen, Audit-Log, Discord,
/// Leitstelle, Gesetzbücher, System).
private enum SettingsSubRoute: Hashable {
    case roles
    case audit
    case discord
    case centrum
    case laws
    case storage
    case accounts
    case config
    case cron
    case about
}

/// Einstellungen-Modul (Beruf): zeigt die JobProps des aktiven Jobs (Logo,
/// Bezeichnung, Funkfrequenz, Livemap-Farbe, MOTD) und erlaubt mit
/// `SetJobProps`-Berechtigung das Bearbeiten der Felder.
struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var motd = ""
    @State private var radioFrequency = ""
    @State private var jobLabel = ""
    @State private var markerColor: Color = .secondary
    @State private var penaltyCalculator = false
    @State private var absencePastDays: Int32 = 0
    @State private var absenceFutureDays: Int32 = 30
    @State private var hasSeeded = false
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveErrorMessage: String?
    @State private var showSavedToast = false
    @State private var showDeleteLogoConfirm = false
    @State private var subRoute: SettingsSubRoute?

    private var props: Resources_Jobs_Props_JobProps? {
        appState.jobProps
    }

    private var canEdit: Bool {
        appState.can("settings.SettingsService/SetJobProps")
    }

    private var jobTitle: String {
        if let props, props.hasJobLabel, !props.jobLabel.isEmpty {
            return props.jobLabel
        }
        return appState.character?.jobLabel ?? "Beruf"
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

                if let props {
                    Section {
                        DetailHero(
                            gradient: FiveNetModule.settings.gradient,
                            icon: "gearshape.fill",
                            title: jobTitle,
                            subtitle: "Beruf-Einstellungen",
                            badges: heroBadges(props)
                        )
                        .listRowInsets(EdgeInsets(
                            top: 0,
                            leading: Theme.Spacing.xl,
                            bottom: 0,
                            trailing: Theme.Spacing.xl
                        ))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

                if isLoading && props == nil {
                    ForEach(0..<4, id: \.self) { _ in
                        SkeletonListRow()
                    }
                } else if let props {
                    infoSection(props)

                    if canEdit {
                        editSection(props)
                    } else {
                        Section {
                            StatusLabelRow(
                                "Du hast keine Berechtigung, diese Einstellungen zu bearbeiten.",
                                systemImage: "lock.fill",
                                tint: .secondary
                            )
                            .cardRow()
                        }
                    }

                    moreSection(props)
                } else {
                    Section {
                        EmptyStateView(
                            "gearshape",
                            color: FiveNetModule.settings.tint,
                            title: "Keine Einstellungen",
                            message: "Für deinen Beruf konnten keine Einstellungen geladen werden."
                        )
                        .cardRow()
                    }
                }
            }
            .cardListStyle()
            .moduleNavTitle(.settings)
            .navConnectionDot()
            .pendingAlarmBell()
            .navigationBarTitleDisplayMode(.inline)
            .task(id: props) {
                seedIfNeeded()
                if props == nil && !isLoading {
                    await load()
                }
            }
            .confirmationDialog(
                "Logo löschen?",
                isPresented: $showDeleteLogoConfirm,
                titleVisibility: .visible
            ) {
                Button("Löschen", role: .destructive) {
                    deleteLogo()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Das Berufs-Logo wird vom Server entfernt.")
            }
            .toast(isPresented: $showSavedToast, message: "Einstellungen gespeichert", systemImage: "checkmark")
        }
        .navigationDestination(item: $subRoute) { route in
            switch route {
            case .roles:
                SettingsRolesView()
            case .audit:
                SettingsAuditLogView()
            case .discord:
                SettingsDiscordView()
            case .centrum:
                SettingsCentrumView()
            case .laws:
                SettingsLawsView()
            case .storage:
                SettingsStorageView()
            case .accounts:
                SettingsAccountsView()
            case .config:
                SettingsConfigView()
            case .cron:
                SettingsCronView()
            case .about:
                SettingsAboutView()
            }
        }
    }

    // MARK: - Sections

    private func infoSection(_ props: Resources_Jobs_Props_JobProps) -> some View {
        Section {
            SectionCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    HStack(spacing: Theme.Spacing.lg) {
                        if let logoURL {
                            AuthAsyncImage(url: logoURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                                case .failure:
                                    placeholderLogo
                                default:
                                    placeholderLogo
                                        .redacted(reason: .placeholder)
                                }
                            }
                        } else {
                            placeholderLogo
                        }

                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Beruf")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(.secondary)
                            Text(jobTitle)
                                .font(.headline)
                        }
                    }

                    Divider()

                    LabeledContent("Job-Code") {
                        Text(props.job)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Funkfrequenz") {
                        Text(props.hasRadioFrequency && !props.radioFrequency.isEmpty ? props.radioFrequency : "Nicht gesetzt")
                            .font(.subheadline)
                            .foregroundStyle(props.hasRadioFrequency ? .primary : .secondary)
                    }

                    LabeledContent("Livemap-Farbe") {
                        HStack(spacing: Theme.Spacing.sm) {
                            Circle()
                                .fill(markerColor)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().stroke(.quaternary, lineWidth: 1))
                            Text(props.livemapMarkerColor.uppercased())
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if props.hasMotd, !props.motd.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("MOTD")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(.secondary)
                            Text(props.motd)
                                .font(.subheadline)
                        }
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .cardRow()
        }
    }

    private var moreRows: [(icon: String, title: String, subtitle: String, route: SettingsSubRoute)] {
        var rows: [(icon: String, title: String, subtitle: String, route: SettingsSubRoute)] = []
        if appState.can("settings.SettingsService/GetRoles") {
            rows.append((
                "person.3.fill",
                "Rollen & Berechtigungen",
                "Rollen ansehen, anlegen und verwalten",
                .roles
            ))
        }
        if appState.can("settings.SettingsService/ViewAuditLog") {
            rows.append((
                "list.bullet.rectangle",
                "Audit-Log",
                "Server-Aktivität einsehen",
                .audit
            ))
        }
        if appState.can("centrum.CentrumService/GetSettings") {
            rows.append((
                "building.2.crop.circle.fill",
                "Leitstellen-Einstellungen",
                "Leitstellen-Modus, Zeiten und Status",
                .centrum
            ))
        }
        if appState.can("settings.LawsService/CreateOrUpdateLawBook") {
            rows.append((
                "scale.3d",
                "Gesetzbücher",
                "Gesetzbücher und Gesetze verwalten",
                .laws
            ))
        }
        if canEdit {
            rows.append((
                "person.2.fill",
                "Discord",
                "Verknüpfte Discord-Server und Kanäle",
                .discord
            ))
        }
        return rows
    }

    private var systemRows: [(icon: String, title: String, subtitle: String, route: SettingsSubRoute)] {
        var rows: [(icon: String, title: String, subtitle: String, route: SettingsSubRoute)] = [
            (
                "externaldrive.fill",
                "Datenspeicher",
                "Hochgeladene Dateien verwalten",
                .storage
            ),
            (
                "server.rack",
                "FiveNet-Einstellungen",
                "App-Konfiguration anzeigen",
                .config
            ),
            (
                "clock.arrow.circlepath",
                "Hintergrund-Aufgaben",
                "Geplante Server-Jobs anzeigen und starten",
                .cron
            ),
            (
                "info.circle.fill",
                "Über MD-Connect",
                "Version, Lizenz und Marken-Hinweis",
                .about
            ),
        ]
        // Konten ist ConfigAdmin-gated (Server-System-Permission), kein normaler Guard-Name.
        if appState.canBeConfigAdmin {
            rows.insert(
                (
                    "person.crop.circle.badge.checkmark",
                    "Konten",
                    "Benutzerkonten verwalten",
                    .accounts
                ),
                at: 1
            )
        }
        return rows
    }

    private func moreSection(_ props: Resources_Jobs_Props_JobProps) -> some View {
        let rows = moreRows
        let systemRows = systemRows
        return Group {
            if !rows.isEmpty || (canEdit && props.hasLogoFileID) {
                Section {
                    SectionCard {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.route) { index, row in
                                settingsRow(icon: row.icon, title: row.title, subtitle: row.subtitle, tint: FiveNetModule.settings.tint, route: row.route)

                                if index < rows.count - 1 {
                                    Divider()
                                }
                            }

                            if canEdit && props.hasLogoFileID {
                                if !rows.isEmpty {
                                    Divider()
                                }
                                Button(role: .destructive) {
                                    showDeleteLogoConfirm = true
                                } label: {
                                    HStack(spacing: Theme.Spacing.lg) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                                .fill(Theme.Palette.danger.opacity(0.12))
                                            Image(systemName: "photo.badge.trash.fill")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(Theme.Palette.danger)
                                        }
                                        .frame(width: 40, height: 40)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Logo löschen")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Theme.Palette.danger)
                                            Text("Entfernt das Berufs-Logo vom Server")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()
                                    }
                                    .padding(.vertical, Theme.Spacing.sm)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Theme.Spacing.md)
                    }
                    .cardRow()
                }
            }

            if !systemRows.isEmpty {
                Section {
                    SectionCard {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            SectionHeader("System")
                            VStack(spacing: 0) {
                                ForEach(Array(systemRows.enumerated()), id: \.element.route) { index, row in
                                    settingsRow(icon: row.icon, title: row.title, subtitle: row.subtitle, tint: .secondary, route: row.route)

                                    if index < systemRows.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding(Theme.Spacing.md)
                    }
                    .cardRow()
                }
            }
        }
    }

    private func settingsRow(icon: String, title: String, subtitle: String, tint: Color, route: SettingsSubRoute) -> some View {
        Button {
            subRoute = route
        } label: {
            HStack(spacing: Theme.Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(tint.opacity(0.14))
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                CardChevron()
            }
            .padding(.vertical, Theme.Spacing.sm)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func editSection(_ props: Resources_Jobs_Props_JobProps) -> some View {
        Section {
            SectionCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    SectionHeader("Einstellungen bearbeiten")

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Job-Bezeichnung")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                        TextField("Job-Bezeichnung", text: $jobLabel)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Funkfrequenz")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                        TextField("Funkfrequenz", text: $radioFrequency)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Livemap-Farbe")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                        ColorPicker("Livemap-Farbe", selection: $markerColor, supportsOpacity: false)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("MOTD")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                        TextField("MOTD", text: $motd, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                    }

                    Toggle("Strafen-Rechner", isOn: $penaltyCalculator)
                        .font(.subheadline)

                    Stepper("Abwesenheit rückwirkend: \(absencePastDays) Tage", value: $absencePastDays, in: 0...31)
                        .font(.subheadline)

                    Stepper("Abwesenheit voraus: \(absenceFutureDays) Tage", value: $absenceFutureDays, in: 3...186)
                        .font(.subheadline)

                    if let saveErrorMessage {
                        StatusLabelRow(saveErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    }

                    Button {
                        save()
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            if isSaving {
                                ProgressView()
                            }
                            Text(isSaving ? "Speichern …" : "Speichern")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Palette.accent)
                    .disabled(isSaving)
                }
                .padding(Theme.Spacing.md)
            }
            .cardRow()
        }
    }

    // MARK: - Derived

    private var logoURL: URL? {
        guard let filePath = props?.logoFile.filePath, !filePath.isEmpty,
              let baseURL = appState.session.serverURL else { return nil }
        return URL(string: "/api/filestore/\(filePath)", relativeTo: baseURL)?.absoluteURL
    }

    private var placeholderLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(FiveNetModule.settings.tint.opacity(0.14))
            Image(systemName: "building.2.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(FiveNetModule.settings.tint)
        }
        .frame(width: 56, height: 56)
    }

    private func heroBadges(_ props: Resources_Jobs_Props_JobProps) -> [String] {
        var badges: [String] = []
        if props.hasRadioFrequency, !props.radioFrequency.isEmpty {
            badges.append(props.radioFrequency)
        }
        if !props.livemapMarkerColor.isEmpty {
            badges.append(props.livemapMarkerColor.uppercased())
        }
        return badges
    }

    // MARK: - Loading & Saving

    private func seedIfNeeded() {
        guard let props, !hasSeeded else { return }
        hasSeeded = true
        motd = props.hasMotd ? props.motd : ""
        radioFrequency = props.hasRadioFrequency ? props.radioFrequency : ""
        jobLabel = props.hasJobLabel ? props.jobLabel : ""
        markerColor = Color(hex: props.livemapMarkerColor) ?? .secondary
        penaltyCalculator = props.hasQuickButtons && props.quickButtons.penaltyCalculator
        absencePastDays = props.hasSettings ? props.settings.absencePastDays : 0
        absenceFutureDays = props.hasSettings ? props.settings.absenceFutureDays : 30
    }

    private func deleteLogo() {
        Task {
            do {
                try await appState.deleteJobLogo()
                showSavedToast = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            if appState.jobProps == nil {
                try await appState.reloadJobProps()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func save() {
        guard let props else { return }
        isSaving = true
        saveErrorMessage = nil
        Task {
            do {
                _ = try await appState.setJobProps(propsWithEdits(from: props))
                showSavedToast = true
            } catch {
                saveErrorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func propsWithEdits(from props: Resources_Jobs_Props_JobProps) -> Resources_Jobs_Props_JobProps {
        var updated = props
        let trimmedMOTD = motd.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedMOTD.isEmpty {
            updated.clearMotd()
        } else {
            updated.motd = trimmedMOTD
        }
        let trimmedRF = radioFrequency.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRF.isEmpty {
            updated.clearRadioFrequency()
        } else {
            updated.radioFrequency = trimmedRF
        }
        let trimmedLabel = jobLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLabel.isEmpty {
            updated.clearJobLabel()
        } else {
            updated.jobLabel = trimmedLabel
        }
        if let hex = markerColor.hexString {
            updated.livemapMarkerColor = hex
        }

        if updated.hasQuickButtons {
            updated.quickButtons.penaltyCalculator = penaltyCalculator
        } else {
            updated.quickButtons = Resources_Jobs_Props_QuickButtons.with {
                $0.penaltyCalculator = penaltyCalculator
            }
        }

        if updated.hasSettings {
            updated.settings.absencePastDays = absencePastDays
            updated.settings.absenceFutureDays = absenceFutureDays
        } else {
            updated.settings = Resources_Jobs_Settings_JobSettings.with {
                $0.absencePastDays = absencePastDays
                $0.absenceFutureDays = absenceFutureDays
            }
        }
        return updated
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
