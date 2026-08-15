import SwiftUI
import SwiftProtobuf

// MARK: - Labels/Farben

extension Resources_Audit_EventAction {
    var label: String {
        switch self {
        case .viewed: return "Angesehen"
        case .created: return "Erstellt"
        case .updated: return "Aktualisiert"
        case .deleted: return "Gelöscht"
        case .restored: return "Wiederhergestellt"
        case .unspecified, .UNRECOGNIZED: return "Unbekannt"
        }
    }
}

extension Resources_Audit_EventResult {
    var label: String {
        switch self {
        case .succeeded: return "Erfolgreich"
        case .failed: return "Fehlgeschlagen"
        case .errored: return "Fehler"
        case .unspecified, .UNRECOGNIZED: return "Unbekannt"
        }
    }

    var tint: Color {
        switch self {
        case .succeeded: return Theme.Palette.success
        case .failed: return Theme.Palette.danger
        case .errored: return Theme.Palette.warning
        case .unspecified, .UNRECOGNIZED: return Color.secondary
        }
    }
}

/// Einstellungen → Audit-Log: paginierte Liste der Server-Aktivität mit
/// Suche und Ergebnis-/Aktions-Filtern.
struct SettingsAuditLogView: View {
    @Environment(AppState.self) private var appState

    private static let pageSize: Int64 = 50

    @State private var logs: [Resources_Audit_AuditEntry] = []
    @State private var searchText = ""
    @State private var currentPage: Int64 = 0
    @State private var totalCount: Int64 = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedResult: Resources_Audit_EventResult?
    @State private var selectedAction: Resources_Audit_EventAction?
    @State private var searchTask: Task<Void, Never>?

    private var totalPages: Int64 {
        max(1, Int64(ceil(Double(totalCount) / Double(Self.pageSize))))
    }

    private var hasMultiplePages: Bool {
        if totalCount >= 0 { return totalPages > 1 }
        return logs.count == Int(Self.pageSize)
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .cardRow()
                }
            }

            Section {
                SectionCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        HStack {
                            Menu {
                                Button {
                                    selectedResult = nil
                                } label: {
                                    Label("Alle Ergebnisse", systemImage: selectedResult == nil ? "checkmark" : "")
                                }
                                ForEach(Resources_Audit_EventResult.allCases, id: \.rawValue) { result in
                                    if result != .unspecified {
                                        Button {
                                            selectedResult = result
                                        } label: {
                                            Label(result.label, systemImage: selectedResult == result ? "checkmark" : "")
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                    Text(selectedResult?.label ?? "Ergebnis")
                                        .font(.subheadline)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(Theme.Palette.accent)

                            Menu {
                                Button {
                                    selectedAction = nil
                                } label: {
                                    Label("Alle Aktionen", systemImage: selectedAction == nil ? "checkmark" : "")
                                }
                                ForEach(Resources_Audit_EventAction.allCases, id: \.rawValue) { action in
                                    if action != .unspecified {
                                        Button {
                                            selectedAction = action
                                        } label: {
                                            Label(action.label, systemImage: selectedAction == action ? "checkmark" : "")
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "bolt.horizontal.circle")
                                    Text(selectedAction?.label ?? "Aktion")
                                        .font(.subheadline)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(Theme.Palette.accent)

                            Spacer()
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
                .cardRow()
            }

            if isLoading && logs.isEmpty {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonListRow()
                }
            } else if logs.isEmpty {
                Section {
                    EmptyStateView(
                        "list.bullet.rectangle",
                        color: FiveNetModule.settings.tint,
                        title: "Keine Einträge",
                        message: "Das Audit-Log enthält keine passenden Einträge."
                    )
                    .cardRow()
                }
            } else {
                Section {
                    ForEach(logs, id: \.id) { entry in
                        SettingsAuditLogRow(entry: entry)
                            .cardRow()
                    }
                }
            }

            if hasMultiplePages {
                Section(pageHeaderText) {
                    PaginationFooter {
                        HStack {
                            Button {
                                currentPage -= 1
                                Task { await load() }
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
                                currentPage += 1
                                Task { await load() }
                            } label: {
                                Label("Weiter", systemImage: "chevron.right")
                                    .labelStyle(.titleAndIcon)
                            }
                            .buttonStyle(.borderless)
                            .disabled(!canGoNext || isLoading)
                        }
                    }
                }
            }
        }
        .cardListStyle()
        .contentMargins(.top, Theme.Spacing.xl, for: .scrollContent)
        .navigationTitle("Audit-Log")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Dienst, Methode, Nutzer …")
        .onChange(of: searchText) {
            scheduleSearch()
        }
        .onChange(of: selectedResult) {
            scheduleSearch()
        }
        .onChange(of: selectedAction) {
            scheduleSearch()
        }
        .task { await load() }
    }

    private var knownTotal: Bool {
        totalCount >= 0
    }

    private var pageHeaderText: String {
        if totalCount >= 0 {
            return "Seite \(currentPage + 1) von \(totalPages)"
        }
        return "Seite \(currentPage + 1)"
    }

    private var canGoNext: Bool {
        if totalCount >= 0 { return currentPage + 1 < totalPages }
        return logs.count == Int(Self.pageSize)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled {
                currentPage = 0
                await load()
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        let actions = selectedAction.map { [$0] } ?? []
        let results = selectedResult.map { [$0] } ?? []
        do {
            let response = try await appState.viewAuditLog(
                search: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                actions: actions,
                results: results,
                offset: currentPage * Self.pageSize,
                pageSize: Self.pageSize
            )
            logs = response.logs
            totalCount = response.pagination.totalCount
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// Karten-Zeile für einen Audit-Log-Eintrag.
private struct SettingsAuditLogRow: View {
    let entry: Resources_Audit_AuditEntry

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(entry.result.tint.opacity(0.14))
                Image(systemName: resultIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(entry.result.tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("\(entry.service).\(entry.method)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(entry.result.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(entry.result.tint, in: Capsule())
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(formatTimestamp(entry.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var resultIcon: String {
        switch entry.result {
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .errored: return "exclamationmark.circle.fill"
        case .unspecified, .UNRECOGNIZED: return "circle"
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if entry.hasUser {
            parts.append(userShortName(entry.user))
        }
        if entry.hasTargetUser {
            parts.append("→ \(userShortName(entry.targetUser))")
        }
        if entry.action != .unspecified {
            parts.append(entry.action.label)
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        SettingsAuditLogView()
    }
}
