import SwiftUI
import SwiftProtobuf

/// Einstellungen → Konten: listet die Benutzerkonten des Servers und erlaubt
/// das Aktivieren/Deaktivieren und Löschen von Konten. Konten werden nicht über
/// die App erstellt — der Server implementiert `AccountsService/CreateAccount`
/// nicht (v2026.8.0), auch das Web bietet keine Konten-Erstellung.
struct SettingsAccountsView: View {
    @Environment(AppState.self) private var appState

    private static let pageSize: Int64 = 50

    @State private var accounts: [Resources_Accounts_Account] = []
    @State private var currentPage: Int64 = 0
    @State private var totalCount: Int64 = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var accountToDelete: Resources_Accounts_Account?

    /// Konten-RPCs sind auf dem Server ConfigAdmin-gated (System-Permission
    /// `internal.Superuser/ConfigAdmin`, NICHT `settings.AccountsService/…`).
    private var canEdit: Bool {
        appState.canBeConfigAdmin
    }

    private var totalPages: Int64 {
        max(1, Int64(ceil(Double(totalCount) / Double(Self.pageSize))))
    }

    private var hasMultiplePages: Bool {
        if totalCount >= 0 { return totalPages > 1 }
        return accounts.count == Int(Self.pageSize)
    }

    private var canGoNext: Bool {
        if totalCount >= 0 { return currentPage + 1 < totalPages }
        return accounts.count == Int(Self.pageSize)
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .cardRow()
                }
            }

            if isLoading && accounts.isEmpty {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonListRow()
                }
            } else if accounts.isEmpty {
                Section {
                    EmptyStateView(
                        "person.crop.circle.badge.questionmark",
                        color: FiveNetModule.settings.tint,
                        title: "Keine Konten",
                        message: searchText.isEmpty
                            ? "Es wurden noch keine Benutzerkonten angelegt."
                            : "Keine Konten zu „\(searchText)“ gefunden."
                    )
                    .cardRow()
                }
            } else {
                Section {
                    ForEach(accounts) { account in
                        SettingsAccountRow(account: account, onToggleEnabled: {
                            toggleEnabled(account)
                        })
                        .cardRow()
                        .swipeActions(edge: .trailing) {
                            if appState.canBeConfigAdmin {
                                Button(role: .destructive) {
                                    accountToDelete = account
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }

            if hasMultiplePages {
                Section {
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
        .navigationTitle("Konten")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Benutzername suchen")
        .onChange(of: searchText) {
            scheduleSearch()
        }
        .task { await load() }
        .confirmationDialog(
            "Konto löschen?",
            isPresented: Binding(get: { accountToDelete != nil }, set: { if !$0 { accountToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                if let account = accountToDelete {
                    delete(account)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            currentPage = 0
            await load()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await appState.listAccounts(username: searchText, offset: currentPage * Self.pageSize, pageSize: Self.pageSize)
            accounts = response.accounts
            totalCount = response.pagination.totalCount
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func toggleEnabled(_ account: Resources_Accounts_Account) {
        Task {
            do {
                let updated = try await appState.updateAccount(id: account.id, enabled: !account.enabled)
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    accounts[index] = updated
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ account: Resources_Accounts_Account) {
        Task {
            do {
                try await appState.deleteAccount(id: account.id)
                accounts.removeAll { $0.id == account.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Karten-Zeile für ein Benutzerkonto.
private struct SettingsAccountRow: View {
    let account: Resources_Accounts_Account
    var onToggleEnabled: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill((account.enabled ? Theme.Palette.success : Theme.Palette.danger).opacity(0.14))
                Image(systemName: account.enabled ? "checkmark.seal.fill" : "lock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(account.enabled ? Theme.Palette.success : Theme.Palette.danger)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(account.username.isEmpty ? "Unbenannt" : account.username)
                    .font(.headline)
                HStack(spacing: Theme.Spacing.md) {
                    if !account.license.isEmpty {
                        Text(account.license)
                            .font(.caption.monospaced())
                    }
                    if account.hasCreatedAt {
                        Text("Seit \(account.createdAt.timestamp.date.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: Binding(
                get: { account.enabled },
                set: { _ in onToggleEnabled() }
            ))
            .labelsHidden()
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
        SettingsAccountsView()
    }
}
