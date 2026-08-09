import SwiftUI
import SwiftProtobuf

/// Sheet for creating a new conduct register entry (Führungsregister).
/// Mirrors the web `components/jobs/conduct/EditorModal.vue` (create mode).
///
/// Fields: Art (type), Ziel (Bürger), Inhalt (message) and "Läuft ab am"
/// (expiresAt). The entry can be saved as a draft or published directly.
struct CreateConductEntrySheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Pre-selected target user when creating from a colleague detail.
    var presetUserID: Int32?

    @State private var type: Resources_Jobs_Conduct_ConductType = .note
    @State private var message = ""
    @State private var hasExpiry = false
    @State private var expiresAt = Date().addingTimeInterval(7 * 86400)
    @State private var targetUser: Resources_Jobs_Colleagues_Colleague?
    @State private var targetSearch = ""
    @State private var targetResults: [Resources_Jobs_Colleagues_Colleague] = []
    @State private var isSearchingTarget = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var searchTask: Task<Void, Never>?

    private let types: [Resources_Jobs_Conduct_ConductType] = [
        .note, .neutral, .positive, .negative, .warning, .suspension,
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Art") {
                    Picker("Art", selection: $type) {
                        ForEach(types, id: \.rawValue) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Ziel") {
                    if let targetUser {
                        HStack {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(colleagueName(targetUser))
                                    .font(.subheadline.weight(.medium))
                                Text("CIT-\(targetUser.userID)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                self.targetUser = nil
                                targetSearch = ""
                                targetResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    } else {
                        TextField("Kollegen suchen …", text: $targetSearch)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        if isSearchingTarget {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        }

                        if !targetResults.isEmpty {
                            ForEach(targetResults) { user in
                                Button {
                                    targetUser = user
                                    targetResults = []
                                    searchTask?.cancel()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                            Text(colleagueName(user))
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                            if !user.jobLabel.isEmpty {
                                                Text(user.jobLabel)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Text("CIT-\(user.userID)")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                Section("Inhalt") {
                    TextField("Inhalt des Eintrags …", text: $message, axis: .vertical)
                        .lineLimit(4...10)
                }

                Section("Läuft ab am") {
                    Toggle("Ablaufdatum setzen", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Läuft ab am", selection: $expiresAt, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Palette.danger)
                    }
                }
            }
            .navigationTitle("Führungsregister-Eintrag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button {
                            Task { await save(draft: true) }
                        } label: {
                            Label("Als Entwurf speichern", systemImage: "pencil")
                        }
                        Button {
                            Task { await save(draft: false) }
                        } label: {
                            Label("Veröffentlichen", systemImage: "paperplane.fill")
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Speichern")
                        }
                    }
                    .disabled(isSaving || !canSubmit)
                }
            }
            .onChange(of: targetSearch) { _, newValue in
                searchTask?.cancel()
                let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard targetUser == nil else { return }
                if query.isEmpty {
                    targetResults = []
                    isSearchingTarget = false
                    return
                }
                searchTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        await searchTargets(query)
                    } catch {
                        return
                    }
                }
            }
            .task {
                if let presetUserID {
                    targetSearch = String(presetUserID)
                    if let colleague = (try? await appState.listColleagues(search: "", userIds: [presetUserID]).colleagues.first) {
                        targetUser = colleague
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func searchTargets(_ query: String) async {
        isSearchingTarget = true
        defer { isSearchingTarget = false }
        do {
            let response = try await appState.listColleagues(search: query, pageSize: 20)
            guard !Task.isCancelled else { return }
            targetResults = response.colleagues
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private var canSubmit: Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return targetUser != nil && !trimmed.isEmpty
    }

    private func save(draft: Bool) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            var entry = Resources_Jobs_Conduct_ConductEntry()
            entry.targetUserID = targetUser?.userID ?? 0
            entry.type = type
            entry.draft = draft
            entry.message = Self.content(from: trimmed)
            if hasExpiry {
                entry.expiresAt = toTimestampProto(expiresAt)
            }
            _ = try await appState.createConductEntry(entry: entry)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Builds a Tiptap-JSON `Content` for plain text so the web editor can
    /// render it (content.ts `tiptapToContent`).
    private static func content(from text: String) -> Resources_Common_Content_Content {
        var content = Resources_Common_Content_Content()
        content.contentType = .tiptapJson
        content.tiptapJson = Self.tiptapDoc(text: text)
        return content
    }

    /// Builds a minimal Tiptap document struct: `{type:"doc",content:[{type:"paragraph",content:[{type:"text",text:"…"}]}]}`.
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

#Preview {
    CreateConductEntrySheet()
        .environment(AppState())
}
