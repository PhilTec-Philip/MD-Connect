import SwiftUI
import SwiftProtobuf

/// Einstellungen → Datenspeicher: listet die im Filestore abgelegten Dateien
/// und erlaubt das Löschen einzelner Dateien.
struct SettingsStorageView: View {
    @Environment(AppState.self) private var appState

    private static let pageSize: Int64 = 50

    @State private var files: [Resources_File_File] = []
    @State private var currentPage: Int64 = 0
    @State private var totalCount: Int64 = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var fileToDelete: Resources_File_File?

    private var totalPages: Int64 {
        max(1, Int64(ceil(Double(totalCount) / Double(Self.pageSize))))
    }

    private var hasMultiplePages: Bool {
        if totalCount >= 0 { return totalPages > 1 }
        return files.count == Int(Self.pageSize)
    }

    private var pageHeaderText: String {
        if totalCount >= 0 {
            return "Seite \(currentPage + 1) von \(totalPages)"
        }
        return "Seite \(currentPage + 1)"
    }

    private var canGoNext: Bool {
        if totalCount >= 0 { return currentPage + 1 < totalPages }
        return files.count == Int(Self.pageSize)
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    StatusLabelRow(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .cardRow()
                }
            }

            if isLoading && files.isEmpty {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonListRow()
                }
            } else if files.isEmpty {
                Section {
                    EmptyStateView(
                        "externaldrive",
                        color: FiveNetModule.settings.tint,
                        title: "Keine Dateien",
                        message: "Im Datenspeicher wurden noch keine Dateien abgelegt."
                    )
                    .cardRow()
                }
            } else {
                Section {
                    ForEach(files) { file in
                        SettingsStorageRow(file: file)
                            .cardRow()
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    fileToDelete = file
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
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
        .navigationTitle("Datenspeicher")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog(
            "Datei löschen?",
            isPresented: Binding(get: { fileToDelete != nil }, set: { if !$0 { fileToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                if let file = fileToDelete {
                    delete(file)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Datei wird dauerhaft vom Server entfernt.")
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await appState.listFiles(offset: currentPage * Self.pageSize, pageSize: Self.pageSize)
            files = response.files
            totalCount = response.pagination.totalCount
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func delete(_ file: Resources_File_File) {
        Task {
            do {
                try await appState.deleteFile(parentID: file.hasParentID ? file.parentID : 0, fileID: file.id)
                files.removeAll { $0.id == file.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Karten-Zeile für eine Datei.
private struct SettingsStorageRow: View {
    let file: Resources_File_File

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(FiveNetModule.settings.tint.opacity(0.14))
                Image(systemName: file.isDir ? "folder.fill" : "doc.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FiveNetModule.settings.tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(fileName)
                    .font(.headline)
                    .lineLimit(1)
                Text(file.filePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: Theme.Spacing.md) {
                    if !file.contentType.isEmpty {
                        Text(file.contentType)
                    }
                    Text(formatBytes(file.byteSize))
                }
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

    private var fileName: String {
        let path = file.filePath
        if let last = path.split(separator: "/").last, !last.isEmpty {
            return String(last)
        }
        return "Datei #\(file.id)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    NavigationStack {
        SettingsStorageView()
    }
}
