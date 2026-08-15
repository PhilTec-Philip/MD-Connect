import SwiftUI
import SwiftProtobuf

/// Einstellungen → Über FiveNet Mobile: Version, Lizenz, Drittanbieter-Attribution
/// und Marken-/Haftungs-Hinweise.
struct SettingsAboutView: View {
    var body: some View {
        List {
            Section {
                SectionCard {
                    VStack(spacing: Theme.Spacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [FiveNetModule.settings.tint, FiveNetModule.settings.tint.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Image(systemName: "globe.desk.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 72, height: 72)
                        .shadow(color: FiveNetModule.settings.tint.opacity(0.35), radius: 12, y: 6)

                        VStack(spacing: Theme.Spacing.xs) {
                            Text("FiveNet Mobile")
                                .font(Theme.Typography.title)
                            Text("Version \(appVersion)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Ein Community-Projekt für deinen FiveNet-Server")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.md)
                }
                .cardRow()
            }

            Section {
                SectionCard {
                    legalText(
                        title: "Lizenz",
                        body: "FiveNet Mobile ist unter der Apache License, Version 2.0 lizenziert. Quellcode und Lizenztext sind im Projekt verfügbar. Die Software wird OHNE GEWÄHRLEISTUNG bereitgestellt („AS IS“, siehe Apache License §7)."
                    )
                }
                .cardRow()
            }

            Section {
                SectionCard {
                    legalText(
                        title: "Drittanbieter-Attribution",
                        body: "Dieses Produkt enthält Software, die auf dem FiveNet-Projekt (https://github.com/fivenet-app/fivenet, Copyright 2023 Alexander Trost, Apache License 2.0) basiert — insbesondere die Protobuf-Dienstdefinitionen und die daraus generierten Client-Bindungen unter Generated/. SwiftProtobuf (Apache License 2.0), Copyright 2014–2017 Apple Inc. und die Swift-Projekt-Autoren."
                    )
                }
                .cardRow()
            }

            Section {
                SectionCard {
                    legalText(
                        title: "Marken-Hinweis",
                        body: "FiveNet Mobile ist ein Community-Projekt auf Basis des FiveNet-Projekts (https://github.com/fivenet-app/fivenet, Copyright 2023 Alexander Trost). „FiveNet“ ist ein Produktname seines jeweiligen Inhabers und wird hier zur Beschreibung des Servers verwendet, mit dem diese App kompatibel ist."
                    )
                }
                .cardRow()
            }

            Section {
                SectionCard {
                    legalText(
                        title: "API-Nutzung",
                        body: "Die App verbindet sich ausschließlich mit FiveNet-Servern, die von dir oder deiner Community selbst betrieben werden (FiveNet ist Open Source, Apache 2.0). Die Nutzung der Demo-Instanz (demo.fivenet.app) unterliegt den Nutzungsbedingungen des Betreibers. Bitte stelle sicher, dass du für die von dir genutzten Server die jeweils geltenden Bedingungen einhältst."
                    )
                }
                .cardRow()
            }
        }
        .cardListStyle()
        .contentMargins(.top, Theme.Spacing.xl, for: .scrollContent)
        .navigationTitle("Über FiveNet Mobile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func legalText(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
    }
}

#Preview {
    NavigationStack {
        SettingsAboutView()
    }
}