import SwiftUI
import SwiftProtobuf

extension Resources_Centrum_Settings_CentrumType {
    var label: String {
        switch self {
        case .dispatch: return "Einsatz"
        case .delivery: return "Lieferung"
        case .unspecified, .UNRECOGNIZED: return "Unbekannt"
        }
    }
}

extension Resources_Centrum_Settings_CentrumMode {
    var label: String {
        switch self {
        case .manual: return "Manuell"
        case .centralCommand: return "Zentrale"
        case .autoRoundRobin: return "Automatisch (Round Robin)"
        case .simplified: return "Vereinfacht"
        case .unspecified, .UNRECOGNIZED: return "Unbekannt"
        }
    }
}

/// Einstellungen → Leitstellen-Einstellungen: zeigt die Centrum-Konfiguration
/// (Modus, Zeiten, Status-Presets) und erlaubt das Bearbeiten der Kernfelder.
struct SettingsCentrumView: View {
    @Environment(AppState.self) private var appState

    @State private var settings: Resources_Centrum_Settings_Settings?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveErrorMessage: String?
    @State private var showSavedToast = false
    @State private var hasSeeded = false

    @State private var enabled = false
    @State private var isPublic = false
    @State private var type: Resources_Centrum_Settings_CentrumType = .unspecified
    @State private var mode: Resources_Centrum_Settings_CentrumMode = .unspecified
    @State private var fallbackMode: Resources_Centrum_Settings_CentrumMode = .unspecified
    @State private var dispatchMaxWait: Int64 = 0
    @State private var requireUnit = false
    @State private var requireUnitReminderSeconds: Int64 = 0
    @State private var deduplicationEnabled = false
    @State private var deduplicationRadius: Int64 = 0
    @State private var unitStatusText = ""
    @State private var dispatchStatusText = ""

    private var canEdit: Bool {
        appState.can("centrum.CentrumService/UpdateSettings")
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .cardRow()
                }
            }

            if isLoading && settings == nil {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonListRow()
                }
            } else if let settings {
                Section {
                    SectionCard {
                        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            SectionHeader("Leitstelle")
                            LabeledContent("Aktiviert") {
                                Text(enabled ? "Ja" : "Nein")
                            }
                            LabeledContent("Öffentlich") {
                                Text(isPublic ? "Ja" : "Nein")
                            }
                            LabeledContent("Typ") {
                                Text(type.label)
                            }
                            LabeledContent("Modus") {
                                Text(mode.label)
                            }
                            if fallbackMode != .unspecified {
                                LabeledContent("Fallback-Modus") {
                                    Text(fallbackMode.label)
                                }
                            }
                            if settings.hasTimings {
                                Divider()
                                LabeledContent("Max. Wartezeit") {
                                    Text("\(dispatchMaxWait) s")
                                }
                                LabeledContent("Einheit erforderlich") {
                                    Text(requireUnit ? "Ja" : "Nein")
                                }
                                if requireUnit {
                                    LabeledContent("Erinnerung nach") {
                                        Text("\(requireUnitReminderSeconds) s")
                                    }
                                }
                            }
                            if settings.hasConfiguration {
                                Divider()
                                LabeledContent("Deduplizierung") {
                                    Text(deduplicationEnabled ? "Aktiv" : "Inaktiv")
                                }
                                if deduplicationEnabled {
                                    LabeledContent("Deduplizierungs-Radius") {
                                        Text("\(deduplicationRadius) m")
                                    }
                                }
                            }
                            if settings.hasPredefinedStatus {
                                Divider()
                                if !unitStatusText.isEmpty {
                                    LabeledContent("Einheiten-Status") {
                                        Text(unitStatusText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.trailing)
                                    }
                                }
                                if !dispatchStatusText.isEmpty {
                                    LabeledContent("Einsatz-Status") {
                                        Text(dispatchStatusText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.trailing)
                                    }
                                }
                            }
                        }
                        .padding(Theme.Spacing.md)
                    }
                    .cardRow()
                }

                if canEdit {
                    Section {
                        SectionCard {
                            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                                SectionHeader("Bearbeiten")

                                Toggle("Leitstelle aktiviert", isOn: $enabled)
                                Toggle("Öffentlich", isOn: $isPublic)

                                Picker("Typ", selection: $type) {
                                    Text("Einsatz").tag(Resources_Centrum_Settings_CentrumType.dispatch)
                                    Text("Lieferung").tag(Resources_Centrum_Settings_CentrumType.delivery)
                                }

                                Picker("Modus", selection: $mode) {
                                    Text("Manuell").tag(Resources_Centrum_Settings_CentrumMode.manual)
                                    Text("Zentrale").tag(Resources_Centrum_Settings_CentrumMode.centralCommand)
                                    Text("Automatisch").tag(Resources_Centrum_Settings_CentrumMode.autoRoundRobin)
                                    Text("Vereinfacht").tag(Resources_Centrum_Settings_CentrumMode.simplified)
                                }

                                Picker("Fallback-Modus", selection: $fallbackMode) {
                                    Text("Keiner").tag(Resources_Centrum_Settings_CentrumMode.unspecified)
                                    Text("Manuell").tag(Resources_Centrum_Settings_CentrumMode.manual)
                                    Text("Zentrale").tag(Resources_Centrum_Settings_CentrumMode.centralCommand)
                                    Text("Automatisch").tag(Resources_Centrum_Settings_CentrumMode.autoRoundRobin)
                                    Text("Vereinfacht").tag(Resources_Centrum_Settings_CentrumMode.simplified)
                                }

                                Stepper("Max. Wartezeit: \(dispatchMaxWait) s", value: $dispatchMaxWait, in: 0...600)

                                Toggle("Einheit erforderlich", isOn: $requireUnit)

                                if requireUnit {
                                    Stepper("Erinnerung nach: \(requireUnitReminderSeconds) s", value: $requireUnitReminderSeconds, in: 0...300)
                                }

                                Toggle("Deduplizierung", isOn: $deduplicationEnabled)

                                if deduplicationEnabled {
                                    Stepper("Radius: \(deduplicationRadius) m", value: $deduplicationRadius, in: 0...5000)
                                }

                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    Text("Einheiten-Status")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("Kommagetrennt", text: $unitStatusText)
                                        .textFieldStyle(.roundedBorder)
                                        .autocorrectionDisabled()
                                }

                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    Text("Einsatz-Status")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("Kommagetrennt", text: $dispatchStatusText)
                                        .textFieldStyle(.roundedBorder)
                                        .autocorrectionDisabled()
                                }

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

                if settings.hasEffectiveAccess {
                    Section {
                        SectionCard {
                            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                                SectionHeader("Zugriff")
                                if settings.effectiveAccess.hasDispatches, !settings.effectiveAccess.dispatches.jobs.isEmpty {
                                    ForEach(settings.effectiveAccess.dispatches.jobs, id: \.job) { entry in
                                        LabeledContent(entry.hasJobLabel && !entry.jobLabel.isEmpty ? entry.jobLabel : entry.job) {
                                            Text(accessLabel(entry.access))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                } else {
                                    Text("Keine Einsatzzugriffe konfiguriert.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(Theme.Spacing.md)
                        }
                        .cardRow()
                    }
                }
            } else {
                Section {
                    EmptyStateView(
                        "building.2.crop.circle.fill",
                        color: FiveNetModule.settings.tint,
                        title: "Keine Leitstellen-Einstellungen",
                        message: "Die Leitstellen-Konfiguration konnte nicht geladen werden."
                    )
                    .cardRow()
                }
            }
        }
        .cardListStyle()
        .contentMargins(.top, Theme.Spacing.xl, for: .scrollContent)
        .navigationTitle("Leitstellen-Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .toast(isPresented: $showSavedToast, message: "Leitstellen-Einstellungen gespeichert", systemImage: "checkmark")
    }

    private func accessLabel(_ level: Resources_Centrum_Access_CentrumAccessLevel) -> String {
        switch level {
        case .blocked: return "Gesperrt"
        case .view: return "Ansehen"
        case .participate: return "Teilnehmen"
        case .dispatch: return "Einsatz leiten"
        case .unspecified, .UNRECOGNIZED: return "Unbekannt"
        }
    }

    private func seedIfNeeded() {
        guard let settings, !hasSeeded else { return }
        hasSeeded = true
        enabled = settings.enabled
        isPublic = settings.`public`
        type = settings.type == .unspecified ? .dispatch : settings.type
        mode = settings.mode == .unspecified ? .manual : settings.mode
        fallbackMode = settings.fallbackMode
        if settings.hasTimings {
            dispatchMaxWait = settings.timings.dispatchMaxWait
            requireUnit = settings.timings.requireUnit
            requireUnitReminderSeconds = settings.timings.requireUnitReminderSeconds
        }
        if settings.hasConfiguration {
            deduplicationEnabled = settings.configuration.deduplicationEnabled
            deduplicationRadius = settings.configuration.deduplicationRadius
        }
        if settings.hasPredefinedStatus {
            unitStatusText = settings.predefinedStatus.unitStatus.joined(separator: ", ")
            dispatchStatusText = settings.predefinedStatus.dispatchStatus.joined(separator: ", ")
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await appState.getCentrumSettings()
            settings = response.settings
            seedIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func save() {
        guard var updated = settings else { return }
        isSaving = true
        saveErrorMessage = nil
        updated.enabled = enabled
        updated.`public` = isPublic
        updated.type = type == .unspecified ? .dispatch : type
        updated.mode = mode == .unspecified ? .manual : mode
        updated.fallbackMode = fallbackMode

        if updated.hasTimings {
            updated.timings.dispatchMaxWait = dispatchMaxWait
            updated.timings.requireUnit = requireUnit
            updated.timings.requireUnitReminderSeconds = requireUnitReminderSeconds
        } else {
            updated.timings = Resources_Centrum_Settings_Timings.with {
                $0.dispatchMaxWait = dispatchMaxWait
                $0.requireUnit = requireUnit
                $0.requireUnitReminderSeconds = requireUnitReminderSeconds
            }
        }

        if updated.hasConfiguration {
            updated.configuration.deduplicationEnabled = deduplicationEnabled
            updated.configuration.deduplicationRadius = deduplicationRadius
        } else {
            updated.configuration = Resources_Centrum_Settings_Configuration.with {
                $0.deduplicationEnabled = deduplicationEnabled
                $0.deduplicationRadius = deduplicationRadius
            }
        }

        if updated.hasPredefinedStatus {
            updated.predefinedStatus.unitStatus = splitComma(unitStatusText)
            updated.predefinedStatus.dispatchStatus = splitComma(dispatchStatusText)
        } else {
            updated.predefinedStatus = Resources_Centrum_Settings_PredefinedStatus.with {
                $0.unitStatus = splitComma(unitStatusText)
                $0.dispatchStatus = splitComma(dispatchStatusText)
            }
        }

        Task {
            do {
                settings = try await appState.updateCentrumSettings(updated)
                showSavedToast = true
            } catch {
                saveErrorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func splitComma(_ input: String) -> [String] {
        input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

#Preview {
    NavigationStack {
        SettingsCentrumView()
    }
}
