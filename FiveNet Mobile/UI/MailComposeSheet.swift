import SwiftUI
import SwiftProtobuf

/// Composer for a new mail thread or a reply inside an existing thread.
/// `replyTo` nil = new thread (server derives the sending account), otherwise
/// a reply into that thread (recipients/subject are pre-filled).
struct MailComposeSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let replyTo: Resources_Mailer_Threads_Thread?
    var onSent: (Resources_Mailer_Threads_Thread) -> Void

    @State private var recipientsText = ""
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var suggestions: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var proposalsTask: Task<Void, Never>?
    @State private var didPrefill = false

    init(replyTo: Resources_Mailer_Threads_Thread? = nil, onSent: @escaping (Resources_Mailer_Threads_Thread) -> Void) {
        self.replyTo = replyTo
        self.onSent = onSent
    }

    private var parsedRecipients: [String] {
        recipientsText
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var proposalInput: String {
        recipientsText
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace })
            .last
            .map(String.init) ?? ""
    }

    private var canSend: Bool {
        !parsedRecipients.isEmpty && subject.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 && !isLoading
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Empfänger") {
                    TextField("E-Mail-Adressen (getrennt durch Komma)", text: $recipientsText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Spacing.sm) {
                                ForEach(suggestions, id: \.self) { email in
                                    Button {
                                        applyProposal(email)
                                    } label: {
                                        Text(email)
                                            .font(.caption.weight(.medium))
                                            .padding(.horizontal, Theme.Spacing.lg)
                                            .padding(.vertical, Theme.Spacing.sm)
                                            .background(FiveNetModule.mailer.tint.opacity(0.14), in: Capsule())
                                            .foregroundStyle(FiveNetModule.mailer.tint)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, Theme.Spacing.xs)
                        }
                    }
                }

                Section("Betreff") {
                    TextField("Betreff", text: $subject)
                }

                Section("Nachricht") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 180)
                }

                if let errorMessage {
                    Section {
                        StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    }
                }
            }
            .navigationTitle(replyTo == nil ? "Neue Nachricht" : "Antworten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(replyTo == nil ? "Senden" : "Antworten") {
                        Task { await send() }
                    }
                    .disabled(!canSend)
                }
            }
            .onChange(of: recipientsText) {
                proposalsTask?.cancel()
                let input = proposalInput
                guard input.count >= 2 else {
                    suggestions = []
                    return
                }
                let task = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    await loadProposals(input: input)
                }
                proposalsTask = task
            }
            .onAppear {
                prefillIfNeeded()
            }
            .interactiveDismissDisabled(isLoading)
        }
    }

    // MARK: - Helpers

    private func prefillIfNeeded() {
        guard !didPrefill else { return }
        didPrefill = true
        guard let replyTo else { return }
        subject = replyTo.title
        var recipients: [String] = []
        if replyTo.hasCreatorEmail, !replyTo.creatorEmail.email.isEmpty {
            recipients.append(replyTo.creatorEmail.email)
        }
        recipients += replyTo.recipients.compactMap { recipient in
            guard recipient.hasEmail, !recipient.email.email.isEmpty else { return nil }
            return recipient.email.email
        }
        recipientsText = Array(Set(recipients)).joined(separator: ", ")
    }

    private func applyProposal(_ email: String) {
        var parts = recipientsText
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        parts.append(email)
        recipientsText = parts.joined(separator: ", ")
        suggestions = []
    }

    private func loadProposals(input: String) async {
        do {
            let response = try await appState.getEmailProposals(input: input)
            suggestions = response.emails
        } catch {
            suggestions = []
        }
    }

    private func send() async {
        isLoading = true
        defer { isLoading = false }
        var message = Resources_Mailer_Messages_Message()
        message.title = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        message.content = Self.content(from: bodyText)
        do {
            if let replyTo {
                _ = try await appState.postMessage(message: message)
                dismiss()
                onSent(replyTo)
            } else {
                let thread = try await appState.createThread(
                    title: message.title,
                    message: message,
                    recipients: parsedRecipients
                )
                dismiss()
                onSent(thread)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Builds a Tiptap-JSON `Content` for the plain-text editor content.
    private static func content(from text: String) -> Resources_Common_Content_Content {
        var content = Resources_Common_Content_Content()
        content.contentType = .tiptapJson
        content.tiptapJson = tiptapDoc(text: text)
        return content
    }

    /// `{type:"doc",content:[{type:"paragraph",content:[{type:"text",text:"…"}]}]}`.
    private static func tiptapDoc(text: String) -> SwiftProtobuf.Google_Protobuf_Struct {
        var doc = SwiftProtobuf.Google_Protobuf_Struct()
        doc.fields["type"] = .with { $0.stringValue = "doc" }

        var paragraph = SwiftProtobuf.Google_Protobuf_Struct()
        paragraph.fields["type"] = .with { $0.stringValue = "paragraph" }

        var textNode = SwiftProtobuf.Google_Protobuf_Struct()
        textNode.fields["type"] = .with { $0.stringValue = "text" }
        textNode.fields["text"] = .with { $0.stringValue = text }

        paragraph.fields["content"] = .with { $0.listValue = .with {
            $0.values = [SwiftProtobuf.Google_Protobuf_Value.with { $0.structValue = textNode }]
        } }

        doc.fields["content"] = .with { $0.listValue = .with {
            $0.values = [SwiftProtobuf.Google_Protobuf_Value.with { $0.structValue = paragraph }]
        } }

        return doc
    }
}
