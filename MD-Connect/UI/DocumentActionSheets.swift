import SwiftUI
import SwiftProtobuf

// MARK: - Edit sheet

/// Sheet zum Bearbeiten von Titel + Kategorie eines Dokuments. Der Inhalt wird
/// in der Detailansicht selbst bearbeitet (Inline-Editor); UpdateDocument
/// verlangt vollständige Content-/Meta-Felder.
struct DocumentEditSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let document: Resources_Documents_Document
    var onSaved: (Resources_Documents_Document) -> Void

    @State private var title: String
    @State private var selectedCategoryID: Int64?
    @State private var categories: [Resources_Documents_Category_Category] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(document: Resources_Documents_Document, onSaved: @escaping (Resources_Documents_Document) -> Void) {
        self.document = document
        self.onSaved = onSaved
        _title = State(initialValue: document.title)
        _selectedCategoryID = State(initialValue: document.hasCategoryID ? document.categoryID : nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Titel") {
                    TextField("Titel", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Kategorie") {
                    Picker("Kategorie", selection: $selectedCategoryID) {
                        Text("Keine").tag(Int64?.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(Int64?.some(category.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Palette.danger)
                    }
                }
            }
            .navigationTitle("Dokument bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        Task { await save() }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                }
            }
            .task {
                await loadCategories()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func loadCategories() async {
        do {
            let response = try await appState.listCategories()
            categories = response.categories
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let content = document.hasContent ? document.content : Resources_Common_Content_Content()
            let data = document.hasData ? document.data : nil
            let meta = Resources_Documents_DocumentMeta.with {
                $0.documentID = document.id
                $0.closed = document.meta.closed
                $0.draft = document.meta.draft
                $0.public = document.meta.public
                $0.state = document.meta.state
            }
            let updated = try await appState.updateDocument(
                documentID: document.id,
                title: trimmed,
                categoryID: selectedCategoryID,
                content: content,
                contentType: document.contentType,
                data: data,
                meta: meta
            )
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Requests sheet

/// Sheet „Anfragen“: Liste vorhandener Anfragen mit Genehmigen/Ablehnen/
/// Löschen plus neue Anfrage (Typ + Grund). Spiegelt Web `RequestDrawer.vue`.
struct DocumentRequestsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let documentID: Int64

    @State private var requests: [Resources_Documents_Requests_DocRequest] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var requestType: Resources_Documents_Activity_DocActivityType = .requestedClosure
    @State private var reason = ""
    @State private var isCreating = false

    private static let pageSize: Int64 = 50

    private var canCreate: Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 3 && !isCreating
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && requests.isEmpty {
                    ProgressView("Anfragen werden geladen …")
                        .frame(maxWidth: .infinity)
                } else {
                    Form {
                        if let errorMessage {
                            Section {
                                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.Palette.danger)
                            }
                        }

                        if appState.can("documents.DocumentsService/CreateDocumentReq") {
                            Section("Neue Anfrage") {
                                Picker("Typ", selection: $requestType) {
                                    ForEach(createableRequestTypes, id: \.rawValue) { type in
                                        Text(type.label).tag(type)
                                    }
                                }
                                .pickerStyle(.menu)

                                TextField("Grund (min. 3 Zeichen)", text: $reason, axis: .vertical)
                                    .lineLimit(2...4)

                                Button(isCreating ? "Erstelle …" : "Anfrage erstellen") {
                                    Task { await createRequest() }
                                }
                                .disabled(!canCreate)
                            }
                        }

                        Section("Bestehende Anfragen") {
                            if requests.isEmpty {
                                Text("Keine Anfragen vorhanden")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(requests) { request in
                                    DocumentRequestRow(
                                        request: request,
                                        canDecide: appState.can("documents.DocumentsService/CreateDocumentReq"),
                                        canDelete: appState.can("documents.DocumentsService/DeleteDocumentReq")
                                    ) { accepted in
                                        Task { await decide(request, accepted: accepted) }
                                    } onDelete: {
                                        Task { await delete(request) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Anfragen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .task {
                await load()
            }
        }
        .presentationDetents([.large])
    }

    private var createableRequestTypes: [Resources_Documents_Activity_DocActivityType] {
        [
            .requestedAccess,
            .requestedClosure,
            .requestedOpening,
            .requestedUpdate,
            .requestedOwnerChange,
            .requestedDeletion,
        ]
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await appState.listDocumentReqs(documentID: documentID, pageSize: Self.pageSize)
            requests = response.requests
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createRequest() async {
        guard !isCreating else { return }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await appState.createDocumentReq(documentID: documentID, requestType: requestType, reason: trimmed)
            reason = ""
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func decide(_ request: Resources_Documents_Requests_DocRequest, accepted: Bool) async {
        do {
            _ = try await appState.updateDocumentReq(documentID: documentID, requestID: request.id, accepted: accepted)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ request: Resources_Documents_Requests_DocRequest) async {
        do {
            try await appState.deleteDocumentReq(requestID: request.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DocumentRequestRow: View {
    let request: Resources_Documents_Requests_DocRequest
    let canDecide: Bool
    let canDelete: Bool
    var onDecide: (Bool) -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(request.requestType.label)
                .font(.subheadline.weight(.semibold))

            if request.hasReason, !request.reason.isEmpty {
                Text("Grund: \(request.reason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Theme.Spacing.xs) {
                Text("Von")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(userShortName(request.creator))
                    .font(.caption2.weight(.medium))
                if request.hasCreatedAt, request.createdAt.timestamp.date.timeIntervalSince1970 > 0 {
                    Text("· \(formatRelative(request.createdAt))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if request.hasAccepted {
                Text(request.accepted ? "Akzeptiert" : "Abgelehnt")
                    .font(.caption2.bold())
                    .foregroundStyle(request.accepted ? .green : .red)
            }

            if !request.hasAccepted, canDecide {
                HStack(spacing: Theme.Spacing.md) {
                    Button {
                        onDecide(true)
                    } label: {
                        Label("Genehmigen", systemImage: "checkmark")
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.Palette.success)

                    Button {
                        onDecide(false)
                    } label: {
                        Label("Ablehnen", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.Palette.danger)
                }
                .font(.caption)
            }

            if canDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Anfrage löschen", systemImage: "trash")
                }
                .font(.caption)
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }
}

// MARK: - Approval sheet

/// Sheet „Genehmigen“: zeigt Genehmigungs-Status und Aufgaben des Dokuments
/// (Web `ApprovalDrawer.vue`-Vereinfachung) und erlaubt Genehmigen/Ablehnen.
struct DocumentApprovalSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let documentID: Int64
    var onChanged: () -> Void

    @State private var tasks: [Resources_Documents_Approval_ApprovalTask] = []
    @State private var meta: Resources_Documents_DocumentMeta?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && tasks.isEmpty {
                    ProgressView("Genehmigungen werden geladen …")
                        .frame(maxWidth: .infinity)
                } else {
                    Form {
                        if let errorMessage {
                            Section {
                                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.Palette.danger)
                            }
                        }

                        if let meta {
                            Section("Status") {
                                let status = DocumentApprovalStatus(meta: meta)
                                if status != .none {
                                    Label(status.label, systemImage: "checkmark.seal")
                                        .foregroundStyle(status.color)
                                } else {
                                    Text("Keine Genehmigungsregeln aktiv")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Section("Aufgaben") {
                            if tasks.isEmpty {
                                Text("Keine Aufgaben vorhanden")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(tasks) { task in
                                    DocumentApprovalTaskRow(task: task) { newStatus in
                                        Task { await decide(task, newStatus: newStatus) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Genehmigen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .task {
                await load()
            }
        }
        .presentationDetents([.large])
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let tasksResponse = try await appState.listApprovalTasks(documentID: documentID)
            tasks = tasksResponse
            if let policyResponse = try? await appState.listApprovalPolicies(documentID: documentID) {
                meta = policyResponse.hasDocMeta ? policyResponse.docMeta : nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func decide(_ task: Resources_Documents_Approval_ApprovalTask, newStatus: Resources_Documents_Approval_ApprovalTaskStatus) async {
        do {
            try await appState.decideApproval(
                documentID: documentID,
                taskID: task.id,
                newStatus: newStatus,
                comment: ""
            )
            onChanged()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DocumentApprovalTaskRow: View {
    let task: Resources_Documents_Approval_ApprovalTask
    var onDecide: (Resources_Documents_Approval_ApprovalTaskStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(assigneeLabel)
                    .font(.subheadline.weight(.medium))
                Spacer()
                taskStatusBadge
            }

            if task.hasLabel, !task.label.isEmpty {
                Text(task.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if task.hasComment, !task.comment.isEmpty {
                Text(task.comment)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if task.status == .pending {
                HStack(spacing: Theme.Spacing.md) {
                    Button {
                        onDecide(.approved)
                    } label: {
                        Label("Genehmigen", systemImage: "checkmark")
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.Palette.success)

                    Button {
                        onDecide(.declined)
                    } label: {
                        Label("Ablehnen", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.Palette.danger)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }

    private var assigneeLabel: String {
        if task.hasUser, !task.user.firstname.isEmpty || !task.user.lastname.isEmpty {
            return userShortName(task.user)
        }
        if task.hasJobLabel, !task.jobLabel.isEmpty {
            return task.jobLabel
        }
        if task.hasJob, !task.job.isEmpty {
            return task.job
        }
        return "Unbekannter Genehmiger"
    }

    private var taskStatusBadge: some View {
        let label: String
        let color: Color
        switch task.status {
        case .approved, .completed: label = "Genehmigt"; color = .green
        case .declined: label = "Abgelehnt"; color = .red
        case .pending: label = "Ausstehend"; color = .orange
        case .expired: label = "Abgelaufen"; color = .gray
        case .cancelled: label = "Storniert"; color = .gray
        default: label = "Unbekannt"; color = .secondary
        }
        return Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxs)
            .foregroundStyle(.white)
            .background(color)
            .clipShape(Capsule())
    }
}

// MARK: - Reminder sheet

/// Sheet „Erinnerung“: legt eine persönliche Erinnerung für ein Dokument an.
/// Spiegelt Web `ReminderDrawer.vue`.
struct DocumentReminderSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let documentID: Int64
    var onSaved: () -> Void

    @State private var reminderDate = Date().addingTimeInterval(24 * 3600)
    @State private var message = ""
    @State private var maxReminderCount: Int32 = 10
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Zeitpunkt") {
                    DatePicker("Erinnerung", selection: $reminderDate, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Nachricht") {
                    TextField("Nachricht", text: $message)
                }

                Section("Wiederholungen") {
                    Stepper(value: $maxReminderCount, in: 1...10) {
                        Text("Maximal \(maxReminderCount) Erinnerung(en)")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Palette.danger)
                    }
                }
            }
            .navigationTitle("Erinnerung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let time = toTimestampProto(reminderDate)
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            try await appState.setDocumentReminder(
                documentID: documentID,
                reminderTime: time,
                message: trimmedMessage.isEmpty ? nil : trimmedMessage,
                maxReminderCount: maxReminderCount
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Label helpers

private extension Resources_Documents_Activity_DocActivityType {
    var label: String {
        switch self {
        case .requestedAccess: return "Zugriff anfragen"
        case .requestedClosure: return "Schließen anfragen"
        case .requestedOpening: return "Öffnen anfragen"
        case .requestedUpdate: return "Änderung anfragen"
        case .requestedOwnerChange: return "Besitzwechsel anfragen"
        case .requestedDeletion: return "Löschen anfragen"
        case .requestedApproval: return "Genehmigung anfragen"
        default: return "Anfrage"
        }
    }
}
