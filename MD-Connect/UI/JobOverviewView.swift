import SwiftUI
import SwiftProtobuf

/// Berufe "Übersicht": job data (logo, radio frequency), MOTD, self-service
/// (absence date) and a timeclock statistics block. Mirrors the web overview.
struct JobOverviewView: View {
    @Environment(AppState.self) private var appState

    @State private var jobProps: Resources_Jobs_Props_JobProps?
    @State private var motd = ""
    @State private var colleague: Resources_Jobs_Colleagues_Colleague?
    @State private var timeclockStats: Services_Jobs_GetTimeclockStatsResponse?

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isEditingMOTD = false
    @State private var editedMOTD = ""
    @State private var showAbsenceSheet = false
    @State private var showToast = false
    @State private var toastMessage = ""

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .cardRow()
                }
            }

            if isLoading && jobProps == nil {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonListRow()
                }
            } else {
                organizationHero
                    .listRowInsets(EdgeInsets(
                        top: Theme.Spacing.xs,
                        leading: Theme.Spacing.xl,
                        bottom: Theme.Spacing.xs,
                        trailing: Theme.Spacing.xl
                    ))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                motdSection
                selfServiceSection
                timeclockSection
            }
        }
        .cardListStyle()
        .navigationTitle("Übersicht")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showAbsenceSheet) {
            AbsenceDateSheet(colleague: colleague)
                .environment(appState)
                .onAbsenceSaved { updated in
                    colleague = updated
                }
        }
        .toast(isPresented: $showToast, message: toastMessage)
    }

    // MARK: - Sections

    private var organizationHero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.xl) {
                organizationLogo
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(jobLabel)
                        .font(Theme.Typography.title2)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let grade = gradeLabel, !grade.isEmpty {
                        Text("Rang: \(grade)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }
                Spacer()
            }

            if let frequency = jobProps?.radioFrequency, !frequency.isEmpty {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption)
                    Text(frequency)
                        .font(.caption.weight(.semibold).monospaced())
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .foregroundStyle(.white)
                .background(.white.opacity(0.18), in: Capsule())
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: FiveNetModule.jobs.gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 120, height: 120)
                .offset(x: 34, y: -50)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .shadow(color: FiveNetModule.jobs.tint.opacity(0.25), radius: 14, y: 6)
    }

    private var organizationLogo: some View {
        Group {
            if let logoURL = logoURL {
                AuthAsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .empty:
                        ProgressView()
                    case .failure:
                        organizationPlaceholder
                    @unknown default:
                        organizationPlaceholder
                    }
                }
            } else {
                organizationPlaceholder
            }
        }
    }

    private var organizationPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(.white.opacity(0.22))
            Image(systemName: "briefcase.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white)
        }
    }

    private var motdSection: some View {
        Section("Nachricht des Tages") {
            if isEditingMOTD {
                SectionCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        TextField("MOTD", text: $editedMOTD, axis: .vertical)
                            .lineLimit(3...8)
                        HStack {
                            Button("Abbrechen") {
                                isEditingMOTD = false
                                editedMOTD = motd
                            }
                            .foregroundStyle(.secondary)
                            Spacer()
                            Button("Speichern") {
                                Task { await saveMOTD() }
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
                .cardRow()
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text(motd.isEmpty ? "Keine Nachricht gesetzt." : motd)
                        .foregroundStyle(motd.isEmpty ? .secondary : .primary)

                    if appState.can("jobs.JobsService/SetMOTD") {
                        Button {
                            editedMOTD = motd
                            isEditingMOTD = true
                        } label: {
                            Label("Bearbeiten", systemImage: "pencil")
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .font(.subheadline)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.xl)
                .background(
                    Theme.Palette.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                )
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                .cardRow()
            }
        }
    }

    private var selfServiceSection: some View {
        Section("Eigenverwaltung") {
            Button {
                showAbsenceSheet = true
            } label: {
                HStack(spacing: Theme.Spacing.lg) {
                    GradientIconTile("calendar.badge.plus", gradient: FiveNetModule.jobs.gradient, size: 36)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Urlaub eintragen")
                            .foregroundStyle(.primary)
                        Text(absenceSummary)
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
            .buttonStyle(.plain)
            .cardRow()
        }
    }

    private var timeclockSection: some View {
        Section("Stempeluhr") {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if let stats = timeclockStats?.stats, stats.spentTimeSum > 0 || stats.spentTimeAvg > 0 || stats.spentTimeMax > 0 {
                    HStack(spacing: Theme.Spacing.md) {
                        timeclockStat(
                            label: "Gesamt",
                            value: hours(stats.spentTimeSum),
                            icon: "clock.fill",
                            tint: FiveNetModule.jobs.tint
                        )
                        timeclockStat(
                            label: "Durchschnitt",
                            value: hours(stats.spentTimeAvg),
                            icon: "chart.bar.fill",
                            tint: Theme.Palette.info
                        )
                        timeclockStat(
                            label: "Maximum",
                            value: hours(stats.spentTimeMax),
                            icon: "arrow.up.right.circle.fill",
                            tint: Theme.Palette.warning
                        )
                    }
                } else if timeclockStats != nil {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(.secondary)
                        Text("Noch keine Zeiten erfasst.")
                            .foregroundStyle(.secondary)
                    }
                } else if !isLoading {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                        Text("Stempeluhr-Statistik ist für deinen Rang nicht verfügbar.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.xl)
            .background(
                Theme.Palette.surface,
                in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
            )
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            .cardRow()
        }
    }

    private func timeclockStat(label: String, value: String, icon: String, tint: Color) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))

            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Derived

    private var logoURL: URL? {
        guard let filePath = jobProps?.logoFile.filePath, !filePath.isEmpty,
              let baseURL = appState.session.serverURL else { return nil }
        return URL(string: "/api/filestore/\(filePath)", relativeTo: baseURL)?.absoluteURL
    }

    private var jobLabel: String {
        jobProps?.jobLabel ?? appState.character?.jobLabel ?? "Beruf"
    }

    private var gradeLabel: String? {
        let grade = appState.character?.jobGradeLabel
        return (grade?.isEmpty ?? true) ? nil : grade
    }

    private var absenceSummary: String {
        guard let props = colleague?.props,
              props.hasAbsenceBegin || props.hasAbsenceEnd else {
            return "Keine Abwesenheit eingetragen."
        }
        let begin = props.hasAbsenceBegin ? formatDateOnly(props.absenceBegin) : "–"
        let end = props.hasAbsenceEnd ? formatDateOnly(props.absenceEnd) : "–"
        return "\(begin) – \(end)"
    }

    private func formatDateOnly(_ timestamp: Resources_Timestamp_Timestamp) -> String {
        timestamp.timestamp.date.formatted(date: .abbreviated, time: .omitted)
    }

    private func hours(_ value: Float) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) h"
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        jobProps = appState.jobProps

        // MOTD is available for everyone (`jobs.JobsService/GetMOTD` is remapped
        // to `PermAny`), so refresh it on every load.
        if let message = try? await appState.getMOTD() {
            motd = message
        }

        // Self-service and statistics require their own permissions; a single
        // denied RPC must not break the whole overview.
        if let selfColleague = try? await appState.getSelfColleague() {
            colleague = selfColleague
        }

        if appState.can("jobs.TimeclockService/ListTimeclock") {
            timeclockStats = try? await appState.getTimeclockStats()
        } else {
            timeclockStats = nil
        }
    }

    private func saveMOTD() async {
        let newValue = editedMOTD.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            motd = try await appState.setMOTD(newValue)
            isEditingMOTD = false
            toastMessage = "MOTD gespeichert"
            showToast = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        JobOverviewView()
            .environment(AppState())
    }
}
