import SwiftUI
import SwiftProtobuf

/// Berufe "Kollegen → Labels": manage the job's colleague labels (name, color,
/// sort order). Mirrors the web labels page.
struct JobsLabelsView: View {
    @Environment(AppState.self) private var appState

    @State private var labels: [Resources_Jobs_Labels_Label] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var deletedLabelIDs: [Int64] = []

    var body: some View {
        Form {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Palette.danger)
                }
            }

            Section("Labels") {
                if isLoading && labels.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonListRow()
                    }
                } else if labels.isEmpty {
                    EmptyStateView(
                        "tag",
                        color: Theme.Palette.accent,
                        title: "Keine Labels",
                        message: "Füge das erste Label für deinen Beruf hinzu."
                    )
                } else {
                    ForEach($labels) { $label in
                        LabelEditorRow(label: $label)
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            let id = labels[offset].id
                            if id > 0 {
                                deletedLabelIDs.append(id)
                            }
                        }
                        labels.remove(atOffsets: offsets)
                    }
                }

                Button {
                    labels.append(Resources_Jobs_Labels_Label.with {
                        $0.color = "#5c7aff"
                    })
                } label: {
                    Label("Label hinzufügen", systemImage: "plus")
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else {
                        Text("Speichern")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("Labels")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .toast(isPresented: $showToast, message: toastMessage)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            labels = try await appState.getColleagueLabels()
            deletedLabelIDs = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            for label in labels {
                let saved = try await appState.createOrUpdateLabel(label)
                if saved.id > 0, let index = labels.firstIndex(where: { $0.id == label.id }) {
                    labels[index] = saved
                }
            }
            for id in deletedLabelIDs {
                try await appState.deleteLabel(id: id)
            }
            try await appState.reorderLabels(labels.map(\.id))
            deletedLabelIDs = []
            toastMessage = "Labels gespeichert"
            showToast = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Editable row for a single label (name + color).
private struct LabelEditorRow: View {
    @Binding var label: Resources_Jobs_Labels_Label

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                TextField("Name", text: $label.name)
                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
            }

            Text(label.name.isEmpty ? "–" : label.name)
                .font(.caption)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .background(color, in: Capsule())
                .foregroundStyle(textColor)
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }

    private var color: Color {
        Color(hex: label.color) ?? .secondary
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { color },
            set: { newValue in
                label.color = newValue.hexString ?? "#5c7aff"
            }
        )
    }

    private var textColor: Color {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        return luminance > 0.6 ? .black : .white
    }
}

extension Color {
    /// Converts the color to a `#RRGGBB` hex string (used when saving labels).
    var hexString: String? {
        guard let components = UIColor(self).getRedGreenBlue() else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int(round(components.red * 255)),
            Int(round(components.green * 255)),
            Int(round(components.blue * 255))
        )
    }
}

private extension UIColor {
    func getRedGreenBlue() -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return (red, green, blue)
    }
}

#Preview {
    NavigationStack {
        JobsLabelsView()
            .environment(AppState())
    }
}
