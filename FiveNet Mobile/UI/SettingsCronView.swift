import SwiftUI
import SwiftProtobuf

/// Einstellungen → Hintergrund-Aufgaben: zeigt die geplanten Server-Jobs
/// (Cronjobs) und erlaubt das manuelle Starten einzelner Jobs.
struct SettingsCronView: View {
    @Environment(AppState.self) private var appState

    @State private var jobs: [Resources_Cron_Cronjob] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var runningJobNames: Set<String> = []

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .cardRow()
                }
            }

            if isLoading && jobs.isEmpty {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonListRow()
                }
            } else if jobs.isEmpty {
                Section {
                    EmptyStateView(
                        "clock.arrow.circlepath",
                        color: FiveNetModule.settings.tint,
                        title: "Keine Hintergrund-Aufgaben",
                        message: "Es sind keine geplanten Server-Jobs konfiguriert."
                    )
                    .cardRow()
                }
            } else {
                Section {
                    ForEach(jobs) { job in
                        SettingsCronRow(job: job, isRunning: runningJobNames.contains(job.name)) {
                            run(job)
                        }
                        .cardRow()
                    }
                }
            }
        }
        .cardListStyle()
        .contentMargins(.top, Theme.Spacing.xl, for: .scrollContent)
        .navigationTitle("Hintergrund-Aufgaben")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            jobs = try await appState.listCronjobs()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func run(_ job: Resources_Cron_Cronjob) {
        runningJobNames.insert(job.name)
        Task {
            do {
                try await appState.runCronjob(name: job.name)
            } catch {
                errorMessage = error.localizedDescription
            }
            runningJobNames.remove(job.name)
        }
    }
}

/// Karten-Zeile für einen Cronjob.
private struct SettingsCronRow: View {
    let job: Resources_Cron_Cronjob
    let isRunning: Bool
    var onRun: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(stateColor.opacity(0.14))
                Image(systemName: stateIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(stateColor)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(job.name)
                    .font(.headline)
                if !job.schedule.isEmpty {
                    Text("Zeitplan: \(job.schedule)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: Theme.Spacing.md) {
                    Text(stateLabel)
                    if job.hasNextScheduleTime {
                        Text("Nächster Lauf: \(job.nextScheduleTime.timestamp.date.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            if isRunning {
                ProgressView()
            } else {
                Button(action: onRun) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(Theme.Palette.accent.opacity(0.14), in: Circle())
                        .foregroundStyle(Theme.Palette.accent)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Job ausführen")
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var stateColor: Color {
        switch job.state {
        case .running: return .orange
        case .pending: return .yellow
        case .waiting: return .secondary
        case .unspecified, .UNRECOGNIZED: return .secondary
        }
    }

    private var stateIcon: String {
        switch job.state {
        case .running: return "arrow.triangle.2.circlepath"
        case .pending: return "hourglass"
        case .waiting: return "clock"
        case .unspecified, .UNRECOGNIZED: return "clock"
        }
    }

    private var stateLabel: String {
        switch job.state {
        case .running: return "Läuft"
        case .pending: return "Ausstehend"
        case .waiting: return "Wartet"
        case .unspecified, .UNRECOGNIZED: return "Unbekannt"
        }
    }
}

#Preview {
    NavigationStack {
        SettingsCronView()
    }
}
