import SwiftUI
import SwiftProtobuf

/// Displays a single document: metadata header, tabbed sections
/// (Inhalt, Beziehungen, Referenzen, Zugriff, Kommentare), and toolbar actions.
struct DocumentDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let documentID: Int64

    @State private var document: Resources_Documents_Document?
    @State private var relations: [Resources_Documents_Relations_DocumentRelation] = []
    @State private var references: [Resources_Documents_References_DocumentReference] = []
    @State private var access: Resources_Access_Access?
    @State private var comments: [Resources_Documents_Comment_Comment] = []
    @State private var selectedTab: DocumentTab = .content
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var copiedToClipboard = false

    @State private var showEditSheet = false
    @State private var showRequestsSheet = false
    @State private var showApprovalSheet = false
    @State private var showReminderSheet = false
    @State private var showTakeOwnershipConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showDeleteReasonPrompt = false
    @State private var deleteReason = ""
    @State private var deleteError: String?
    @State private var isDeleting = false

    @State private var isEditingContent = false
    @State private var contentEditorModel: DocumentContentEditorModel?
    @State private var isSavingContent = false
    @State private var showDiscardConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Palette.danger)
                }

                if isLoading && document == nil {
                    ProgressView("Dokument wird geladen …")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }

                if let document {
                    header(document)

                    Picker("Bereich", selection: $selectedTab) {
                        ForEach(DocumentTab.allCases) { tab in
                            Text(tab.label).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)

                    switch selectedTab {
                    case .content:
                        contentTab(document)
                    case .relations:
                        relationsTab
                    case .references:
                        referencesTab
                    case .access:
                        accessTab
                    case .comments:
                        commentsTab
                    }
                }
            }
            .padding()
        }
        .navigationTitle(documentTitle)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await load()
        }
        .task {
            await load()
        }
        .onChange(of: selectedTab) {
            Task { await loadTabIfNeeded() }
        }
        .toolbar {
            if isEditingContent {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Abbrechen") {
                        if contentEditorModel?.hasChanges == true {
                            showDiscardConfirm = true
                        } else {
                            stopEditingContent()
                        }
                    }
                    .disabled(isSavingContent)

                    Button("Fertig") {
                        Task { await saveContent() }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSavingContent)
                }
            } else if let document {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        appState.copyDocumentToClipboard(document)
                        copiedToClipboard = true
                    } label: {
                        Label("In Zwischenablage kopieren", systemImage: "doc.on.doc")
                    }

                    Button {
                        Task { await togglePin(document) }
                    } label: {
                        Label(
                            isPinned(document) ? "Pin entfernen" : "Anpinnen",
                            systemImage: isPinned(document) ? "pin.fill" : "pin"
                        )
                    }

                    Menu {
                        Button {
                            Task { await toggleClosed(document) }
                        } label: {
                            if document.meta.closed {
                                Label("Dokument öffnen", systemImage: "lock.open")
                            } else {
                                Label("Dokument schließen", systemImage: "lock.fill")
                            }
                        }

                        if canEdit(document) {
                            Button {
                                showEditSheet = true
                            } label: {
                                Label("Titel & Kategorie bearbeiten", systemImage: "pencil")
                            }

                            if document.hasContent, document.content.hasTiptapJson {
                                Button {
                                    selectedTab = .content
                                    startEditingContent()
                                } label: {
                                    Label("Inhalt bearbeiten", systemImage: "pencil.and.list.clipboard")
                                }
                            }
                        }

                        if appState.can("documents.DocumentsService/ListDocumentReqs") {
                            Button {
                                showRequestsSheet = true
                            } label: {
                                Label("Anfragen", systemImage: "questionmark.bubble")
                            }
                        }

                        if appState.can("documents.DocumentsService/ListDocuments") {
                            Button {
                                showApprovalSheet = true
                            } label: {
                                Label("Genehmigen", systemImage: "checkmark.seal")
                            }
                        }

                        if appState.can("documents.DocumentsService/SetDocumentReminder") {
                            Button {
                                showReminderSheet = true
                            } label: {
                                Label("Erinnerung", systemImage: "bell")
                            }
                        }

                        if canTakeOwnership(document) {
                            Button {
                                showTakeOwnershipConfirm = true
                            } label: {
                                Label("Besitz übernehmen", systemImage: "person.badge.key")
                            }
                        }

                        if canDelete(document) {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label(document.hasDeletedAt ? "Wiederherstellen" : "Löschen", systemImage: document.hasDeletedAt ? "arrow.uturn.backward" : "trash")
                            }
                        }
                    } label: {
                        Label("Aktionen", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog("Besitz übernehmen?", isPresented: $showTakeOwnershipConfirm, titleVisibility: .visible) {
            Button("Übernehmen") {
                Task { await takeOwnership() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Du wirst neuer Eigentümer dieses Dokuments.")
        }
        .confirmationDialog(
            document?.hasDeletedAt == true ? "Dokument wiederherstellen?" : "Dokument löschen?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(document?.hasDeletedAt == true ? "Wiederherstellen" : "Löschen", role: .destructive) {
                if document?.hasDeletedAt == true {
                    Task { await deleteDocument() }
                } else {
                    showDeleteReasonPrompt = true
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(document?.hasDeletedAt == true ? "Das Dokument wird wiederhergestellt." : "Das Dokument wird gelöscht. Gib im nächsten Schritt einen Grund an.")
        }
        .alert("Grund angeben", isPresented: $showDeleteReasonPrompt) {
            TextField("Grund (optional)", text: $deleteReason)
            Button("Löschen", role: .destructive) {
                Task { await deleteDocument(reason: deleteReason) }
            }
            Button("Abbrechen", role: .cancel) {
                deleteReason = ""
            }
        } message: {
            Text("Warum wird das Dokument gelöscht?")
        }
        .confirmationDialog("Änderungen verwerfen?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Verwerfen", role: .destructive) {
                stopEditingContent()
            }
            Button("Weiter bearbeiten", role: .cancel) {}
        } message: {
            Text("Ungespeicherte Änderungen am Inhalt gehen verloren.")
        }
        .sheet(isPresented: $showEditSheet) {
            DocumentEditSheet(document: document ?? Resources_Documents_Document()) { updated in
                document = updated
                showEditSheet = false
            }
            .environment(appState)
        }
        .sheet(isPresented: $showRequestsSheet) {
            DocumentRequestsSheet(documentID: documentID)
                .environment(appState)
        }
        .sheet(isPresented: $showApprovalSheet) {
            DocumentApprovalSheet(documentID: documentID) {
                Task { await load() }
            }
            .environment(appState)
        }
        .sheet(isPresented: $showReminderSheet) {
            DocumentReminderSheet(documentID: documentID) {
                Task { await load() }
            }
            .environment(appState)
        }
        .toast(isPresented: $copiedToClipboard, message: "Kopiert")
    }

    // MARK: - Header

    private func header(_ document: Resources_Documents_Document) -> some View {
        DetailHero(
            gradient: FiveNetModule.documents.gradient,
            icon: FiveNetModule.documents.icon,
            title: documentTitle,
            subtitle: document.hasCategory && !document.category.name.isEmpty ? document.category.name : nil,
            badges: heroBadges(document)
        )
    }

    private func heroBadges(_ document: Resources_Documents_Document) -> [String] {
        var result: [String] = []
        if document.meta.draft {
            result.append("Entwurf")
        }
        result.append(contentsOf: badges(document).map(\.title))
        return result
    }

    private var documentTitle: String {
        guard let document else { return "Dokument" }
        let name = document.title.isEmpty ? "Unbenanntes Dokument" : document.title
        return "\(formatDocumentID(document.id)) · \(name)"
    }

    private func badges(_ document: Resources_Documents_Document) -> [DocumentBadge] {
        var result: [DocumentBadge] = []
        if document.hasCreatedAt, document.createdAt.timestamp.date.timeIntervalSince1970 > 0 {
            result.append(DocumentBadge(title: "Erstellt \(formatTimestamp(document.createdAt))", icon: "calendar"))
        }
        if document.hasUpdatedAt, document.updatedAt.timestamp.date.timeIntervalSince1970 > 0 {
            result.append(DocumentBadge(title: "Aktualisiert \(formatTimestamp(document.updatedAt))", icon: "calendar.badge.plus"))
        }
        if document.meta.closed {
            result.append(DocumentBadge(title: "Geschlossen", icon: "lock.fill"))
        }
        if document.meta.public {
            result.append(DocumentBadge(title: "Öffentlich", icon: "globe"))
        }
        let approval = DocumentApprovalStatus(meta: document.meta)
        if approval != .none {
            result.append(DocumentBadge(title: approval.label, icon: "checkmark.seal"))
        }
        if !document.meta.state.isEmpty {
            result.append(DocumentBadge(title: document.meta.state, icon: "note.text"))
        }
        if document.hasDeletedAt {
            result.append(DocumentBadge(title: "Gelöscht", icon: "trash"))
        }
        let creatorName = userShortName(document.creator)
        if !creatorName.isEmpty {
            result.append(DocumentBadge(
                title: "Erstellt von \(creatorName)",
                icon: "person.crop.circle",
                userID: document.creator.userID
            ))
        }
        return result
    }

    private func isPinned(_ document: Resources_Documents_Document) -> Bool {
        document.hasPin && document.pin.state
    }

    // MARK: - Tabs

    private func contentTab(_ document: Resources_Documents_Document) -> some View {
        Group {
            if isEditingContent, let contentEditorModel {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Bearbeitungsmodus — Medien und Struktur bleiben erhalten.", systemImage: "pencil.and.list.clipboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DocumentContentEditorView(model: contentEditorModel)
                }
                .padding(.top, 4)
            } else if document.hasContent {
                if WikiContent.blocks(for: document.content).isEmpty {
                    Text("Der Inhalt dieses Dokuments (\(document.content.contentType.rawValue)) kann nicht dargestellt werden.")
                        .foregroundStyle(.secondary)
                } else {
                    WikiContentView(content: document.content)
                }
            } else {
                Text("Dieses Dokument hat noch keinen Inhalt.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var relationsTab: some View {
        if isLoading && relations.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
        } else if relations.isEmpty {
            EmptyStateView("arrow.triangle.branch", title: "Keine Beziehungen", message: "Diesem Dokument sind keine Beziehungen zugeordnet.")
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(relations) { relation in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(relationLabel(relation))
                            .font(.subheadline.weight(.semibold))
                        relationPeopleView(relation)
                        if relation.hasDocument {
                            NavigationLink(value: DocumentRoute(documentID: relation.document.id)) {
                                Text(verbatim: "\(formatDocumentID(relation.document.id)) · \(relation.document.title)")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.tint)
                            }
                        }
                        if relation.hasCreatedAt, relation.createdAt.timestamp.date.timeIntervalSince1970 > 0 {
                            Text(formatRelative(relation.createdAt))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private var referencesTab: some View {
        if isLoading && references.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
        } else if references.isEmpty {
            EmptyStateView("link", title: "Keine Referenzen", message: "Dieses Dokument wird nirgendwo referenziert.")
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(references) { reference in
                    VStack(alignment: .leading, spacing: 4) {
                        NavigationLink(value: DocumentRoute(documentID: reference.targetDocumentID)) {
                            Text(verbatim: "\(formatDocumentID(reference.targetDocumentID)) · \(reference.targetDocument.title)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                        if reference.hasCreatedAt, reference.createdAt.timestamp.date.timeIntervalSince1970 > 0 {
                            Text(formatRelative(reference.createdAt))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private var accessTab: some View {
        if isLoading && access == nil {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
        } else if let access {
            if access.jobs.isEmpty && access.users.isEmpty {
                EmptyStateView("lock.open", title: "Keine Einschränkungen", message: "Das Dokument ist für alle sichtbar.")
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if !access.jobs.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Jobs").font(.headline)
                            ForEach(access.jobs, id: \.id) { jobAccess in
                                accessRow(
                                    label: [
                                        jobAccess.jobLabel.isEmpty ? jobAccess.job : jobAccess.jobLabel,
                                        jobAccess.jobGradeLabel,
                                    ].filter { !$0.isEmpty }.joined(separator: " - "),
                                    capability: accessLevelLabel(jobAccess.access),
                                    required: jobAccess.hasRequired && jobAccess.required
                                )
                            }
                        }
                    }
                    if !access.users.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nutzer").font(.headline)
                            ForEach(access.users, id: \.id) { userAccess in
                                accessRow(
                                    label: userShortName(userAccess.user),
                                    capability: accessLevelLabel(userAccess.access),
                                    required: userAccess.hasRequired && userAccess.required
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func accessRow(label: String, capability: String, required: Bool) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Text(capability)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            if required {
                Text("erforderlich")
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.Palette.warning)
            }
        }
    }

    private func accessLevelLabel(_ accessValue: Int32) -> String {
        let level = Resources_Documents_Access_AccessLevel(rawValue: Int(accessValue)) ?? .unspecified
        return level.label
    }

    @ViewBuilder
    private var commentsTab: some View {
        if isLoading && comments.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
        } else if comments.isEmpty {
            EmptyStateView("bubble.left", title: "Keine Kommentare", message: "Zu diesem Dokument gibt es noch keine Kommentare.")
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(userShortName(comment.creator))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if comment.hasCreatedAt, comment.createdAt.timestamp.date.timeIntervalSince1970 > 0 {
                                Text(formatRelative(comment.createdAt))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        if comment.hasContent {
                            WikiContentView(content: comment.content)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    // MARK: - Actions

    private func togglePin(_ document: Resources_Documents_Document) async {
        do {
            try await appState.toggleDocumentPin(documentID: document.id, state: !isPinned(document))
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func canEdit(_ document: Resources_Documents_Document) -> Bool {
        appState.can("documents.DocumentsService/UpdateDocument")
    }

    private func canTakeOwnership(_ document: Resources_Documents_Document) -> Bool {
        guard appState.can("documents.DocumentsService/ChangeDocumentOwner") else { return false }
        let activeJob = appState.character?.job ?? ""
        let sameJob = document.creatorJob == activeJob
        return sameJob || appState.isSuperuser
    }

    private func canDelete(_ document: Resources_Documents_Document) -> Bool {
        appState.can("documents.DocumentsService/DeleteDocument")
    }

    private func takeOwnership() async {
        do {
            try await appState.changeDocumentOwner(documentID: documentID)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteDocument(reason: String? = nil) async {
        guard !isDeleting else { return }
        isDeleting = true
        deleteError = nil
        defer { isDeleting = false }
        do {
            let wasDeleted = document?.hasDeletedAt == true
            try await appState.deleteDocument(documentID: documentID, reason: reason)
            deleteReason = ""
            // Soft-delete toggles between "Löschen" and "Wiederherstellen" —
            // after deleting, leave the detail and return to the list.
            if !wasDeleted {
                dismiss()
            } else {
                await load()
            }
        } catch {
            deleteError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    private func toggleClosed(_ document: Resources_Documents_Document) async {
        do {
            try await appState.toggleDocument(documentID: document.id, closed: !document.meta.closed)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Content editing

    private func startEditingContent() {
        guard let document, document.hasContent, document.content.hasTiptapJson else { return }
        contentEditorModel = DocumentContentEditorModel(content: document.content)
        isEditingContent = true
        errorMessage = nil
    }

    private func stopEditingContent() {
        isEditingContent = false
        contentEditorModel = nil
    }

    private func saveContent() async {
        guard let document, let contentEditorModel else { return }
        isSavingContent = true
        errorMessage = nil
        defer { isSavingContent = false }
        do {
            let content = contentEditorModel.buildContent()
            let meta = Resources_Documents_DocumentMeta.with {
                $0.documentID = document.id
                $0.closed = document.meta.closed
                $0.draft = document.meta.draft
                $0.public = document.meta.public
                $0.state = document.meta.state
            }
            let updated = try await appState.updateDocument(
                documentID: document.id,
                title: document.title,
                categoryID: document.hasCategoryID ? document.categoryID : nil,
                content: content,
                contentType: .tiptapJson,
                data: document.hasData ? document.data : nil,
                meta: meta
            )
            self.document = updated
            stopEditingContent()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await appState.getDocument(id: documentID)
            document = loaded
            if let data: Data = try? loaded.serializedBytes() {
                ViewedContentCache.shared.store(data, for: "doc-\(documentID)")
            }
        } catch {
            if let cached = ViewedContentCache.shared.load(for: "doc-\(documentID)"),
               let cachedDocument = try? Resources_Documents_Document(serializedBytes: cached) {
                document = cachedDocument
                errorMessage = "Offline-Inhalt\(cachedDocument.hasUpdatedAt ? " (Stand \(formatTimestamp(cachedDocument.updatedAt)))" : "")"
            } else {
                errorMessage = error.localizedDescription
            }
        }
        await loadTabIfNeeded()
    }

    private func loadTabIfNeeded() async {
        switch selectedTab {
        case .content:
            return
        case .relations:
            guard relations.isEmpty else { return }
            do {
                relations = try await appState.listDocumentRelations(documentID: documentID)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .references:
            guard references.isEmpty else { return }
            do {
                references = try await appState.listDocumentReferences(documentID: documentID)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .access:
            guard access == nil else { return }
            do {
                access = try await appState.getDocumentAccess(documentID: documentID)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .comments:
            guard comments.isEmpty else { return }
            do {
                comments = try await appState.listComments(documentID: documentID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    private func relationLabel(_ relation: Resources_Documents_Relations_DocumentRelation) -> String {
        switch relation.relation {
        case .mentioned: return "Erwähnt"
        case .targets: return "Ziel"
        case .caused: return "Verursacht"
        case .unspecified, .UNRECOGNIZED: return "Beziehung"
        }
    }

    @ViewBuilder
    private func relationPeopleView(_ relation: Resources_Documents_Relations_DocumentRelation) -> some View {
        let hasPeople = relation.hasSourceUser || relation.hasTargetUser
        if hasPeople {
            HStack(spacing: 4) {
                if relation.hasSourceUser {
                    Text("Von")
                    citizenLink(relation.sourceUser)
                }
                if relation.hasSourceUser && relation.hasTargetUser {
                    Text("·")
                }
                if relation.hasTargetUser {
                    Text("Zu")
                    citizenLink(relation.targetUser)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            Text(relationPeopleText(relation))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func citizenLink(_ user: Resources_Users_Short_UserShort) -> some View {
        let name = userShortName(user)
        if !name.isEmpty {
            NavigationLink(value: ColleagueRoute(userID: user.userID)) {
                Text(name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
            }
        }
    }

    private func relationPeopleText(_ relation: Resources_Documents_Relations_DocumentRelation) -> String {
        var parts: [String] = []
        if relation.hasSourceUser {
            let name = userShortName(relation.sourceUser)
            if !name.isEmpty { parts.append("Von \(name)") }
        }
        if relation.hasTargetUser {
            let name = userShortName(relation.targetUser)
            if !name.isEmpty { parts.append("Zu \(name)") }
        }
        return parts.joined(separator: " · ")
    }
}

private enum DocumentTab: String, CaseIterable, Identifiable {
    case content
    case relations
    case references
    case access
    case comments

    var id: String { rawValue }

    var label: String {
        switch self {
        case .content: return "Inhalt"
        case .relations: return "Beziehungen"
        case .references: return "Referenzen"
        case .access: return "Zugriff"
        case .comments: return "Kommentare"
        }
    }
}

private struct DocumentBadge: Hashable {
    let title: String
    let icon: String
    let userID: Int32?

    init(title: String, icon: String, userID: Int32? = nil) {
        self.title = title
        self.icon = icon
        self.userID = userID
    }
}

extension Resources_Documents_Access_AccessLevel {
    /// German label for the document access level ("Fähigkeit").
    var label: String {
        switch self {
        case .unspecified: return "Unbestimmt"
        case .blocked: return "Gesperrt"
        case .view: return "Ansehen"
        case .comment: return "Kommentieren"
        case .status: return "Status ansehen"
        case .access: return "Zugriff verwalten"
        case .edit: return "Bearbeiten"
        case .UNRECOGNIZED: return "Unbestimmt"
        }
    }
}

/// Simple horizontal wrapping layout for badge rows.
private struct BadgeFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width + (rowWidth == 0 ? 0 : spacing) > width {
                height += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                if rowWidth != 0 { rowWidth += spacing }
                rowWidth += size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
