import SwiftUI
import SwiftProtobuf

/// Einstellungen → FiveNet-Einstellungen: zeigt die Server-Konfiguration
/// (Version, Setup, Auth- und Anzeige-Optionen) als Lese-Ansicht.
struct SettingsConfigView: View {
    @Environment(AppState.self) private var appState

    @State private var config: Resources_Settings_AppConfig?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .cardRow()
                }
            }

            if isLoading && config == nil {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonListRow()
                }
            } else if let config {
                Section {
                    SectionCard {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            SectionHeader("Server")
                            LabeledContent("Version") {
                                Text(config.version.isEmpty ? "–" : config.version)
                            }
                            LabeledContent("Setup abgeschlossen") {
                                Text(config.setupComplete ? "Ja" : "Nein")
                            }
                            LabeledContent("Standard-Sprache") {
                                Text(config.defaultLocale.isEmpty ? "–" : config.defaultLocale)
                            }
                        }
                        .padding(Theme.Spacing.md)
                    }
                    .cardRow()
                }

                if config.hasAuth {
                    Section {
                        SectionCard {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                SectionHeader("Anmeldung")
                                LabeledContent("Registrierung") {
                                    Text(config.auth.signupEnabled ? "Offen" : "Geschlossen")
                                }
                                LabeledContent("Charakter-Sperre") {
                                    Text(config.auth.lastCharLock ? "Aktiv" : "Inaktiv")
                                }
                                if config.auth.jobAdminGroups.count > 0 || config.auth.jobAdminUsers.count > 0 {
                                    Divider()
                                    LabeledContent("Job-Administration") {
                                        Text(adminSummary(config.auth.jobAdminGroups, config.auth.jobAdminUsers))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.trailing)
                                    }
                                }
                                if config.auth.configAdminGroups.count > 0 || config.auth.configAdminUsers.count > 0 {
                                    LabeledContent("Konfig-Administration") {
                                        Text(adminSummary(config.auth.configAdminGroups, config.auth.configAdminUsers))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.trailing)
                                    }
                                }
                            }
                            .padding(Theme.Spacing.md)
                        }
                        .cardRow()
                    }
                }

                if config.hasWebsite {
                    Section {
                        SectionCard {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                SectionHeader("Website")
                                LabeledContent("Statistik-Seite") {
                                    Text(config.website.statsPage ? "Sichtbar" : "Versteckt")
                                }
                                if config.website.hasLinks {
                                    if config.website.links.hasPrivacyPolicy, !config.website.links.privacyPolicy.isEmpty {
                                        LabeledContent("Datenschutz") {
                                            Text(config.website.links.privacyPolicy)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.trailing)
                                        }
                                    }
                                    if config.website.links.hasImprint, !config.website.links.imprint.isEmpty {
                                        LabeledContent("Impressum") {
                                            Text(config.website.links.imprint)
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
                }

                if config.hasDisplay {
                    Section {
                        SectionCard {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                SectionHeader("Anzeige")
                                if !config.display.intlLocale.isEmpty {
                                    LabeledContent("Sprache") {
                                        Text(config.display.intlLocale)
                                    }
                                }
                                if !config.display.currencyName.isEmpty {
                                    LabeledContent("Währung") {
                                        Text(config.display.currencyName)
                                    }
                                }
                            }
                            .padding(Theme.Spacing.md)
                        }
                        .cardRow()
                    }
                }

                if config.hasSystem {
                    Section {
                        SectionCard {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                SectionHeader("System")
                                LabeledContent("Banner-Benachrichtigung") {
                                    Text(config.system.bannerMessageEnabled ? "Aktiv" : "Inaktiv")
                                }
                                if config.system.hasBannerMessage, !config.system.bannerMessage.title.isEmpty {
                                    LabeledContent("Banner-Text") {
                                        Text(config.system.bannerMessage.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.trailing)
                                    }
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
                        "server.rack",
                        color: FiveNetModule.settings.tint,
                        title: "Keine Konfiguration",
                        message: "Die Server-Konfiguration konnte nicht geladen werden."
                    )
                    .cardRow()
                }
            }
        }
        .cardListStyle()
        .contentMargins(.top, Theme.Spacing.xl, for: .scrollContent)
        .navigationTitle("FiveNet-Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func adminSummary(_ groups: [String], _ users: [String]) -> String {
        var parts: [String] = []
        if !groups.isEmpty {
            parts.append("Gruppen: \(groups.joined(separator: ", "))")
        }
        if !users.isEmpty {
            parts.append("Nutzer: \(users.joined(separator: ", "))")
        }
        return parts.joined(separator: "\n")
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            config = try await appState.getAppConfig()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        SettingsConfigView()
    }
}
