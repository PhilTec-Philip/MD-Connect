import SwiftUI
import SwiftProtobuf

/// Mail thread detail: header hero + messages, with reply / state actions.
struct MailThreadView: View {
    @Environment(AppState.self) private var appState

    let route: MailThreadRoute
    /// Called after the thread changed (reply, archive, delete) so the parent
    /// list can reload.
    var onChanged: () -> Void

    @State private var thread: Resources_Mailer_Threads_Thread?
    @State private var messages: [Resources_Mailer_Messages_Message] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showReply = false
    @State private var showDeleteConfirm = false
    @State private var hasLoaded = false
    @State private var markedRead = false

    var body: some View {
        List {
            if let errorMessage, thread == nil {
                Section {
                    StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .cardRow()
                }
            }

            if let thread {
                detailHeroSection(
                    DetailHero(
                        gradient: FiveNetModule.mailer.gradient,
                        icon: "envelope.fill",
                        title: thread.title,
                        subtitle: participantText(for: thread),
                        badges: heroBadges(for: thread)
                    )
                )
            }

            if isLoading && messages.isEmpty {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonListRow()
                }
            } else if let errorMessage, messages.isEmpty {
                EmptyStateView(
                    "exclamationmark.triangle",
                    color: Theme.Palette.danger,
                    title: "Nachrichten konnten nicht geladen werden",
                    message: errorMessage,
                    actionTitle: "Erneut versuchen"
                ) {
                    Task { await load() }
                }
            } else if messages.isEmpty {
                EmptyStateView(
                    "tray",
                    color: FiveNetModule.mailer.tint,
                    title: "Keine Nachrichten",
                    message: "Diese Konversation enthält noch keine Nachrichten."
                )
            } else {
                ForEach(messages) { message in
                    Section {
                        MailMessageCard(message: message)
                            .cardRow()
                    }
                }
            }
        }
        .cardListStyle()
        .navigationTitle(thread?.title ?? "Konversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showReply = true
                } label: {
                    Label("Antworten", systemImage: "arrowshape.turn.up.left")
                }
                .disabled(thread == nil)

                Menu {
                    Button {
                        toggleArchived()
                    } label: {
                        Label(isArchived ? "Aus Archiv holen" : "Archivieren", systemImage: isArchived ? "tray.and.arrow.up" : "archivebox")
                    }
                    Button {
                        toggleImportant()
                    } label: {
                        Label(isImportant ? "Wichtig entfernen" : "Als wichtig markieren", systemImage: isImportant ? "star" : "star")
                    }
                    Button {
                        toggleUnread()
                    } label: {
                        Label(isUnread ? "Als gelesen markieren" : "Als ungelesen markieren", systemImage: isUnread ? "envelope.open" : "envelope.badge")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Konversation löschen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(thread == nil)
            }
        }
        .confirmationDialog("Konversation löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                Task { await deleteThread() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Diese Konversation wird unwiderruflich gelöscht.")
        }
        .sheet(isPresented: $showReply) {
            if let thread {
                MailComposeSheet(replyTo: thread) { _ in
                    Task { await load() }
                }
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await load()
        }
    }

    // MARK: - Derived state

    private var isUnread: Bool {
        guard let thread, thread.hasState else { return false }
        return thread.state.hasUnread && thread.state.unread
    }

    private var isArchived: Bool {
        guard let thread, thread.hasState else { return false }
        return thread.state.hasArchived && thread.state.archived
    }

    private var isImportant: Bool {
        guard let thread, thread.hasState else { return false }
        return thread.state.hasImportant && thread.state.important
    }

    private func heroBadges(for thread: Resources_Mailer_Threads_Thread) -> [String] {
        var badges: [String] = []
        if thread.hasCreatorEmail {
            badges.append(thread.creatorEmail.email)
        }
        let recipientCount = thread.recipients.count
        if recipientCount > 0 {
            badges.append("\(recipientCount) Empfänger")
        }
        return badges
    }

    private func participantText(for thread: Resources_Mailer_Threads_Thread) -> String {
        var parts: [String] = []
        if thread.hasCreator {
            parts.append(userShortName(thread.creator))
        }
        parts += thread.recipients.compactMap { recipient in
            guard recipient.hasEmail else { return nil }
            return recipient.email.email
        }
        return parts.isEmpty ? "Konversation" : parts.joined(separator: " · ")
    }

    // MARK: - Data

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let thread = try await appState.getThread(emailID: route.emailID, threadID: route.threadID)
            self.thread = thread
            let messages = try await appState.listThreadMessages(emailID: route.emailID, threadID: route.threadID, pageSize: 50)
            self.messages = messages
            errorMessage = nil
            await markAsReadIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Marks the thread as read the first time it is opened.
    private func markAsReadIfNeeded() async {
        guard !markedRead, let thread, thread.hasState, thread.state.hasUnread, thread.state.unread else { return }
        markedRead = true
        var state = thread.state
        state.threadID = thread.id
        state.emailID = route.emailID
        state.unread = false
        do {
            let updated = try await appState.setThreadState(state)
            self.thread?.state = updated
            onChanged()
        } catch {
            // Read-state updates are best-effort.
        }
    }

    private func toggleArchived() {
        guard let thread else { return }
        var state = thread.state
        state.threadID = thread.id
        state.emailID = route.emailID
        state.archived = !isArchived
        Task {
            do {
                let updated = try await appState.setThreadState(state)
                self.thread?.state = updated
                onChanged()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func toggleImportant() {
        guard let thread else { return }
        var state = thread.state
        state.threadID = thread.id
        state.emailID = route.emailID
        state.important = !isImportant
        Task {
            do {
                let updated = try await appState.setThreadState(state)
                self.thread?.state = updated
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func toggleUnread() {
        guard let thread else { return }
        var state = thread.state
        state.threadID = thread.id
        state.emailID = route.emailID
        state.unread = !isUnread
        Task {
            do {
                let updated = try await appState.setThreadState(state)
                self.thread?.state = updated
                onChanged()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteThread() async {
        do {
            try await appState.deleteThread(emailID: route.emailID, threadID: route.threadID)
            onChanged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @Environment(\.dismiss) private var dismiss
}

// MARK: - Message card

private struct MailMessageCard: View {
    let message: Resources_Mailer_Messages_Message

    private var senderName: String {
        guard message.hasSender else { return "Benutzer #\(message.senderID)" }
        let email = message.sender
        if email.hasLabel, !email.label.isEmpty {
            return email.label
        }
        if email.hasUser {
            return userShortName(email.user)
        }
        return email.email
    }

    private var senderEmail: String {
        message.hasSender ? message.sender.email : ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.lg) {
                GradientIconTile("person.crop.circle.fill", gradient: FiveNetModule.mailer.gradient, size: 40)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(senderName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if !senderEmail.isEmpty {
                        Text(senderEmail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text(formatTimestamp(message.createdAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            WikiContentView(content: message.content)
        }
        .padding(Theme.Spacing.xl)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}
