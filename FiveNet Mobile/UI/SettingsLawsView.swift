import SwiftUI
import SwiftProtobuf

/// Einstellungen → Gesetzbücher: listet die Gesetzbücher, erlaubt Anlegen/
/// Löschen und den Einstieg in die Gesetze eines Buches.
struct SettingsLawsView: View {
    @Environment(AppState.self) private var appState

    @State private var books: [Resources_Laws_LawBook] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateBook = false
    @State private var bookToDelete: Resources_Laws_LawBook?
    @State private var selectedBookID: Int64?

    private var canEdit: Bool {
        appState.can("settings.LawsService/CreateOrUpdateLawBook")
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

                if isLoading && books.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in
                        SkeletonListRow()
                    }
                } else if books.isEmpty {
                    Section {
                        EmptyStateView(
                            "scale.3d",
                            color: FiveNetModule.settings.tint,
                            title: "Keine Gesetzbücher",
                            message: "Es wurden noch keine Gesetzbücher angelegt."
                        )
                        .cardRow()
                    }
                } else {
                    Section {
                        ForEach(books) { book in
                            Button {
                                selectedBookID = book.id
                            } label: {
                                SettingsLawBookRow(book: book)
                            }
                            .cardRow()
                            .swipeActions(edge: .trailing) {
                                if canEdit {
                                    Button(role: .destructive) {
                                        bookToDelete = book
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .cardListStyle()
            .contentMargins(.top, Theme.Spacing.xl, for: .scrollContent)
            .navigationTitle("Gesetzbücher")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .toolbar {
                if canEdit {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showCreateBook = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Gesetzbuch erstellen")
                    }
                }
            }
            .sheet(isPresented: $showCreateBook) {
                SettingsLawBookEditSheet(onSaved: {
                    showCreateBook = false
                    Task { await load() }
                })
            }
            .confirmationDialog(
                "Gesetzbuch löschen?",
                isPresented: Binding(get: { bookToDelete != nil }, set: { if !$0 { bookToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Löschen", role: .destructive) {
                    if let book = bookToDelete {
                        deleteBook(book)
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Alle enthaltenen Gesetze werden ebenfalls entfernt.")
            }
        }
        .navigationDestination(item: $selectedBookID) { bookID in
            SettingsLawBookDetailView(bookID: bookID)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            books = try await appState.listLawBooks()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteBook(_ book: Resources_Laws_LawBook) {
        Task {
            do {
                try await appState.deleteLawBook(id: book.id)
                books.removeAll { $0.id == book.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Karten-Zeile für ein Gesetzbuch.
private struct SettingsLawBookRow: View {
    let book: Resources_Laws_LawBook

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(FiveNetModule.settings.tint.opacity(0.14))
                Image(systemName: "scale.3d")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FiveNetModule.settings.tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(book.name.isEmpty ? "Unbenannt" : book.name)
                    .font(.headline)
                if book.hasDescription_p, !book.description_p.isEmpty {
                    Text(book.description_p)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text("\(book.laws.count) Gesetze")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
            CardChevron()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

/// Sheet zum Erstellen eines Gesetzbuchs.
struct SettingsLawBookEditSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var onSaved: () -> Void

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Gesetzbuch") {
                    TextField("Name", text: $name)
                    TextField("Beschreibung", text: $descriptionText, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let errorMessage {
                    Section {
                        StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    }
                }
            }
            .navigationTitle("Gesetzbuch erstellen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen") {
                        save()
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        var book = Resources_Laws_LawBook()
        book.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDescription.isEmpty {
            book.description_p = trimmedDescription
        }
        Task {
            do {
                _ = try await appState.createOrUpdateLawBook(book)
                onSaved()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

/// Einstellungen → Gesetzbuch: zeigt die Gesetze eines Buches und erlaubt
/// Anlegen/Bearbeiten/Löschen einzelner Gesetze.
struct SettingsLawBookDetailView: View {
    @Environment(AppState.self) private var appState

    let bookID: Int64

    @State private var book: Resources_Laws_LawBook?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var lawToDelete: Resources_Laws_Law?
    @State private var lawToEdit: Resources_Laws_Law?
    @State private var showCreateLaw = false

    private var canEdit: Bool {
        appState.can("settings.LawsService/CreateOrUpdateLawBook")
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .cardRow()
                }
            }

            if isLoading && book == nil {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonListRow()
                }
            } else if let book {
                if book.hasDescription_p, !book.description_p.isEmpty {
                    Section {
                        StatusLabelRow(book.description_p, systemImage: "text.book.closed", tint: .secondary)
                            .cardRow()
                    }
                }

                if book.laws.isEmpty {
                    Section {
                        EmptyStateView(
                            "doc.text",
                            color: FiveNetModule.settings.tint,
                            title: "Keine Gesetze",
                            message: "Diesem Gesetzbuch sind noch keine Gesetze zugeordnet."
                        )
                        .cardRow()
                    }
                } else {
                    Section {
                        ForEach(book.laws.sorted(by: { $0.sortOrder < $1.sortOrder })) { law in
                            Button {
                                lawToEdit = law
                            } label: {
                                SettingsLawRow(law: law)
                            }
                            .cardRow()
                            .swipeActions(edge: .trailing) {
                                if canEdit {
                                    Button(role: .destructive) {
                                        lawToDelete = law
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }

                if canEdit {
                    Section {
                        Button {
                            showCreateLaw = true
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "plus.circle.fill")
                                Text("Neues Gesetz")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(Theme.Spacing.md)
                            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                        .cardRow()
                    }
                }
            } else {
                Section {
                    EmptyStateView(
                        "scale.3d",
                        color: FiveNetModule.settings.tint,
                        title: "Gesetzbuch nicht gefunden",
                        message: "Das Gesetzbuch konnte nicht geladen werden."
                    )
                    .cardRow()
                }
            }
        }
        .cardListStyle()
        .contentMargins(.top, Theme.Spacing.xl, for: .scrollContent)
        .navigationTitle(book?.name.isEmpty == false ? book!.name : "Gesetzbuch")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $lawToEdit) { law in
            SettingsLawEditSheet(bookID: bookID, law: law, onSaved: {
                lawToEdit = nil
                Task { await load() }
            })
        }
        .sheet(isPresented: $showCreateLaw) {
            SettingsLawEditSheet(bookID: bookID, law: nil, onSaved: {
                showCreateLaw = false
                Task { await load() }
            })
        }
        .confirmationDialog(
            "Gesetz löschen?",
            isPresented: Binding(get: { lawToDelete != nil }, set: { if !$0 { lawToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                if let law = lawToDelete {
                    deleteLaw(law)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let all = try await appState.listLawBooks()
            book = all.first { $0.id == bookID }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteLaw(_ law: Resources_Laws_Law) {
        Task {
            do {
                try await appState.deleteLaw(id: law.id)
                if var updated = book {
                    updated.laws.removeAll { $0.id == law.id }
                    book = updated
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Karten-Zeile für ein Gesetz.
private struct SettingsLawRow: View {
    let law: Resources_Laws_Law

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(law.name.isEmpty ? "Unbenannt" : law.name)
                    .font(.headline)
                if law.hasDescription_p, !law.description_p.isEmpty {
                    Text(law.description_p)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: Theme.Spacing.md) {
                    if law.hasFine, law.fine > 0 {
                        Text("Strafe: \(law.fine)$")
                    }
                    if law.hasDetentionTime, law.detentionTime > 0 {
                        Text("Haft: \(law.detentionTime) min")
                    }
                    if law.hasStvoPoints, law.stvoPoints > 0 {
                        Text("Punkte: \(law.stvoPoints)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer()
            CardChevron()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

/// Sheet zum Erstellen/Bearbeiten eines Gesetzes.
struct SettingsLawEditSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let bookID: Int64
    let law: Resources_Laws_Law?
    var onSaved: () -> Void

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var hint = ""
    @State private var fine: UInt32 = 0
    @State private var detentionTime: UInt32 = 0
    @State private var stvoPoints: UInt32 = 0
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Gesetz") {
                    TextField("Name", text: $name)
                    TextField("Beschreibung", text: $descriptionText, axis: .vertical)
                        .lineLimit(2...5)
                    TextField("Hinweis", text: $hint, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Strafen") {
                    Stepper("Geldstrafe: \(fine)$", value: $fine, in: 0...1_000_000)
                    Stepper("Haftzeit: \(detentionTime) min", value: $detentionTime, in: 0...60_000)
                    Stepper("Punkte: \(stvoPoints)", value: $stvoPoints, in: 0...100)
                }

                if let errorMessage {
                    Section {
                        StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    }
                }
            }
            .navigationTitle(law == nil ? "Neues Gesetz" : "Gesetz bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        save()
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                seedIfNeeded()
            }
        }
    }

    private func seedIfNeeded() {
        guard let law else { return }
        name = law.name
        descriptionText = law.hasDescription_p ? law.description_p : ""
        hint = law.hasHint ? law.hint : ""
        fine = law.hasFine ? law.fine : 0
        detentionTime = law.hasDetentionTime ? law.detentionTime : 0
        stvoPoints = law.hasStvoPoints ? law.stvoPoints : 0
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        var updated = law ?? Resources_Laws_Law()
        updated.lawbookID = bookID
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDescription.isEmpty {
            updated.clearDescription_p()
        } else {
            updated.description_p = trimmedDescription
        }
        let trimmedHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedHint.isEmpty {
            updated.clearHint()
        } else {
            updated.hint = trimmedHint
        }
        if fine > 0 {
            updated.fine = fine
        } else {
            updated.clearFine()
        }
        if detentionTime > 0 {
            updated.detentionTime = detentionTime
        } else {
            updated.clearDetentionTime()
        }
        if stvoPoints > 0 {
            updated.stvoPoints = stvoPoints
        } else {
            updated.clearStvoPoints()
        }
        Task {
            do {
                _ = try await appState.createOrUpdateLaw(updated)
                onSaved()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsLawsView()
    }
}
