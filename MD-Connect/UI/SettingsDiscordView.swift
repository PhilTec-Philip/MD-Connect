import SwiftUI
import SwiftProtobuf

/// Einstellungen → Discord: zeigt die verknüpften Discord-Kanäle und die
/// Discord-Gilden des Benutzers.
struct SettingsDiscordView: View {
    @Environment(AppState.self) private var appState

    @State private var channels: [Resources_Discord_Channel] = []
    @State private var guilds: [Resources_Discord_Guild] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var discordNotEnabled = false

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .cardRow()
                }
            }

            if isLoading && channels.isEmpty && guilds.isEmpty {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonListRow()
                }
            } else {
                if !guilds.isEmpty {
                    Section("Gilden") {
                        ForEach(guilds, id: \.id) { guild in
                            SettingsDiscordGuildRow(guild: guild)
                                .cardRow()
                        }
                    }
                }

                if !channels.isEmpty {
                    Section("Kanäle") {
                        ForEach(channels, id: \.id) { channel in
                            SettingsDiscordChannelRow(channel: channel)
                                .cardRow()
                        }
                    }
                }

                if channels.isEmpty && guilds.isEmpty {
                    Section {
                        EmptyStateView(
                            "person.2.fill",
                            color: FiveNetModule.settings.tint,
                            title: discordNotEnabled ? "Discord nicht aktiviert" : "Keine Discord-Daten",
                            message: discordNotEnabled
                                ? "Der Discord-Webhook ist auf dem FiveNet-Server nicht eingerichtet."
                                : "Es wurde noch kein Discord-Server mit dem Beruf verknüpft."
                        )
                        .cardRow()
                    }
                }
            }
        }
        .cardListStyle()
        .contentMargins(.top, Theme.Spacing.xl, for: .scrollContent)
        .navigationTitle("Discord")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        discordNotEnabled = false
        do {
            guilds = try await appState.listUserGuilds()
        } catch {
            errorMessage = error.localizedDescription
            discordNotEnabled = discordNotEnabled || isDiscordNotEnabledError(error)
        }
        do {
            channels = try await appState.listDiscordChannels()
        } catch {
            if errorMessage == nil {
                errorMessage = error.localizedDescription
            }
            discordNotEnabled = discordNotEnabled || isDiscordNotEnabledError(error)
        }
        isLoading = false
    }

    private func isDiscordNotEnabledError(_ error: Error) -> Bool {
        error.localizedDescription.contains("Discord ist nicht aktiviert") || error.localizedDescription.contains("ErrDiscordNotEnabled")
    }
}

/// Karten-Zeile für eine Discord-Gilde.
private struct SettingsDiscordGuildRow: View {
    let guild: Resources_Discord_Guild

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(FiveNetModule.settings.tint.opacity(0.14))
                Image(systemName: "person.2.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FiveNetModule.settings.tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(guild.name.isEmpty ? "Discord-Server" : guild.name)
                    .font(.headline)
                Text("ID: \(guild.id)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

/// Karten-Zeile für einen Discord-Kanal.
private struct SettingsDiscordChannelRow: View {
    let channel: Resources_Discord_Channel

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(FiveNetModule.settings.tint.opacity(0.14))
                Image(systemName: "number")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FiveNetModule.settings.tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(channel.name.isEmpty ? "Kanal" : channel.name)
                    .font(.headline)
                Text("ID: \(channel.id)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

#Preview {
    NavigationStack {
        SettingsDiscordView()
    }
}
