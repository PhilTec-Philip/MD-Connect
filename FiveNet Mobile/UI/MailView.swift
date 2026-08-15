import SwiftUI
import SwiftProtobuf

/// Navigation route into a mail thread. Carries the email account the thread
/// belongs to (thread state is per email account) plus the thread id.
struct MailThreadRoute: Hashable {
    let emailID: Int64
    let threadID: Int64
}

/// Mail module (Basis): Posteingang/Archiv-Listen mit Suche und Verfassen.
struct MailView: View {
    @Environment(AppState.self) private var appState

    private static let pageSize: Int64 = 50

    enum MailboxTab: String, CaseIterable, Identifiable {
        case inbox = "Posteingang"
        case archive = "Archiv"

        var id: String { rawValue }
    }

    @State private var emails: [Resources_Mailer_Emails_Email] = []
    @State private var threads: [Resources_Mailer_Threads_Thread] = []
    @State private var searchMessages: [Resources_Mailer_Messages_Message] = []
    @State private var tab: MailboxTab = .inbox
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentPage: Int64 = 0
    @State private var totalCount: Int64 = 0
    @State private var hasLoaded = false
    @State private var emailsLoaded = false
    @State private var selectedRoute: MailThreadRoute?
    @State private var showCompose = false
    @State private var showUntestedHint = false
    @State private var searchTask: Task<Void, Never>?

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emailIds: [Int64] {
        Array(emails.map(\.id).prefix(10))
    }

    private var totalPages: Int64 {
        max(1, Int64(ceil(Double(totalCount) / Double(Self.pageSize))))
    }

    private var hasMultiplePages: Bool {
        if totalCount >= 0 { return totalPages > 1 }
        return displayedItems == Int(Self.pageSize)
    }

    private var displayedItems: Int {
        isSearching ? searchMessages.count : threads.count
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

                if !isSearching {
                    Section {
                        SectionCard {
                            PillTabBar(tabs: MailboxTab.allCases, selection: $tab) { $0.rawValue }
                        }
                        .cardRow()
                    }
                }

                if isLoading && threads.isEmpty && searchMessages.isEmpty {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonListRow()
                    }
                } else if emails.isEmpty {
                    EmptyStateView(
                        "envelope",
                        color: FiveNetModule.mailer.tint,
                        title: "Kein Mail-Konto",
                        message: "Für deinen Charakter wurde noch kein Mail-Konto eingerichtet."
                    )
                } else if let errorMessage, displayedItems == 0 {
                    EmptyStateView(
                        "exclamationmark.triangle",
                        color: Theme.Palette.danger,
                        title: "Laden fehlgeschlagen",
                        message: errorMessage,
                        actionTitle: "Erneut versuchen"
                    ) {
                        Task { await load(reset: true) }
                    }
                } else if isSearching, searchMessages.isEmpty {
                    EmptyStateView(
                        "magnifyingglass",
                        color: Theme.Palette.accent,
                        title: "Keine Treffer",
                        message: "Für diese Suche wurden keine Nachrichten gefunden."
                    )
                } else if threads.isEmpty {
                    EmptyStateView(
                        "tray",
                        color: FiveNetModule.mailer.tint,
                        title: "Postfach leer",
                        message: tab == .archive
                            ? "Im Archiv sind keine Konversationen."
                            : "Du hast noch keine Konversationen im Posteingang."
                    )
                } else {
                    Section(resultSectionTitle) {
                        if isSearching {
                            ForEach(searchMessages) { message in
                                Button {
                                    selectedRoute = route(for: message)
                                } label: {
                                    MailSearchRow(message: message)
                                }
                                .buttonStyle(.plain)
                                .cardRow()
                            }
                        } else {
                            ForEach(threads) { thread in
                                Button {
                                    selectedRoute = route(for: thread)
                                } label: {
                                    MailThreadRow(thread: thread)
                                }
                                .buttonStyle(.plain)
                                .cardRow()
                            }
                        }
                    }

                    if hasMultiplePages {
                        Section(pageHeaderText) {
                            PaginationFooter {
                                HStack {
                                    Button {
                                        Task { await load(page: currentPage - 1) }
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
                                        Task { await load(page: currentPage + 1) }
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
            }
            .cardListStyle()
            .searchable(text: $searchText, prompt: "Nachrichten durchsuchen")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: searchText) {
                searchTask?.cancel()
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                let task = Task { @MainActor in
                    if !query.isEmpty {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                    guard !Task.isCancelled else { return }
                    await load(reset: true)
                }
                searchTask = task
            }
            .onChange(of: tab) {
                Task { await load(reset: true) }
            }
            .refreshable {
                await load(reset: true)
            }
            .pendingAlarmBell()
            .moduleNavTitle(.mailer)
            .navConnectionDot()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showUntestedHint = true
                    } label: {
                        Image(systemName: "flask.fill")
                            .accessibilityLabel("Experimentell (noch nicht getestet)")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCompose = true
                    } label: {
                        Label("Neue Nachricht", systemImage: "square.and.pencil")
                    }
                }
            }
            .alert("Noch nicht getestet", isPresented: $showUntestedHint) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Das Mail-Modul wurde noch nicht ausreichend getestet. Es kann daher zu Fehlern oder unerwartetem Verhalten kommen.")
            }
            .sheet(isPresented: $showCompose) {
                MailComposeSheet { thread in
                    selectedRoute = route(for: thread)
                    Task { await load(reset: true) }
                }
            }
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                await loadEmails()
                await load(reset: true)
            }
        }
        .navigationDestination(item: $selectedRoute) { route in
            MailThreadView(route: route) {
                Task { await load(reset: true) }
            }
        }
    }

    private var resultSectionTitle: String {
        if isSearching { return "\(totalCount >= 0 ? "\(totalCount) " : "")Treffer" }
        return tab == .archive ? "Archiv" : "Posteingang"
    }

    private var pageHeaderText: String {
        if totalCount >= 0 {
            return "Seite \(currentPage + 1) von \(totalPages)"
        }
        return "Seite \(currentPage + 1)"
    }

    private var canGoNext: Bool {
        if totalCount >= 0 { return currentPage + 1 < totalPages }
        return displayedItems == Int(Self.pageSize)
    }

    private func route(for thread: Resources_Mailer_Threads_Thread) -> MailThreadRoute {
        let emailID = thread.hasState && thread.state.emailID > 0 ? thread.state.emailID : (emailIds.first ?? 0)
        return MailThreadRoute(emailID: emailID, threadID: thread.id)
    }

    private func route(for message: Resources_Mailer_Messages_Message) -> MailThreadRoute {
        MailThreadRoute(emailID: emailIds.first ?? 0, threadID: message.threadID)
    }

    private func loadEmails() async {
        guard !emailsLoaded else { return }
        emailsLoaded = true
        do {
            let response = try await appState.listEmails()
            emails = response.emails
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load(reset: Bool = false, page: Int64? = nil) async {
        if reset { currentPage = 0 }
        if let page { currentPage = page }
        guard !isLoading else { return }
        if emails.isEmpty, !isSearching {
            await loadEmails()
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let offset = currentPage * Self.pageSize
            if isSearching {
                let response = try await appState.searchThreads(search: searchText, offset: offset, pageSize: Self.pageSize)
                searchMessages = response.messages
                totalCount = response.pagination.totalCount
            } else {
                let response = try await appState.listThreads(emailIds: emailIds, unread: nil, archived: tab == .archive, offset: offset, pageSize: Self.pageSize)
                threads = response.threads
                totalCount = response.pagination.totalCount
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Rows

private struct MailThreadRow: View {
    let thread: Resources_Mailer_Threads_Thread

    private var isUnread: Bool {
        thread.hasState && thread.state.hasUnread && thread.state.unread
    }

    private var senderText: String {
        if thread.hasCreator {
            return userShortName(thread.creator)
        }
        if thread.hasCreatorEmail {
            return thread.creatorEmail.email
        }
        return "Unbekannt"
    }

    private var timeText: String {
        if thread.hasUpdatedAt, thread.updatedAt.timestamp.date.timeIntervalSince1970 > 0 {
            return formatRelative(thread.updatedAt)
        }
        return formatRelative(thread.createdAt)
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            GradientIconTile("envelope.fill", gradient: FiveNetModule.mailer.gradient, size: 44)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(verbatim: thread.title)
                        .font(isUnread ? Theme.Typography.headline : .subheadline.weight(.medium))
                        .foregroundStyle(isUnread ? .primary : .secondary)
                        .lineLimit(1)
                    if isUnread {
                        Circle()
                            .fill(FiveNetModule.mailer.tint)
                            .frame(width: 8, height: 8)
                    }
                    Spacer(minLength: 0)
                    Text(timeText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text(senderText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            CardChevron()
        }
        .padding(Theme.Spacing.xl)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

private struct MailSearchRow: View {
    let message: Resources_Mailer_Messages_Message

    private var senderText: String {
        if message.hasSender {
            return message.sender.email
        }
        return "Benutzer #\(message.senderID)"
    }

    private var snippet: String {
        WikiContent.plainText(for: message.content)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            GradientIconTile("envelope.open.fill", gradient: FiveNetModule.mailer.gradient, size: 44)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(verbatim: message.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(formatRelative(message.createdAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text(senderText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !snippet.isEmpty {
                    Text(snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            CardChevron()
        }
        .padding(Theme.Spacing.xl)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}
