import SwiftUI
import SwiftProtobuf
import Observation

/// Inline-Editor für den Inhalt eines Dokuments. Anders als ein reiner
/// Text-Editor arbeitet er blockbasiert auf dem originalen Tiptap-JSON:
/// - Absätze und Überschriften (nur Text-Kinder) sind editierbare Felder.
/// - Alle anderen Blöcke (Bilder, Listen, Checkboxen, Zitate, Code, Trennlinien,
///   Absätze mit eingebetteten Bildern) werden unverändert gerendert und bleiben
///   beim Speichern byte-identisch erhalten.
/// - Nur in tatsächlich editierten Absätzen werden Inline-Markierungen (fett,
///   kursiv, Links …) zu Klartext; unveränderte Blöcke verlieren nichts.
@Observable
final class DocumentContentEditorModel {
    let supportsEditing: Bool
    private let originalDoc: Google_Protobuf_Struct?
    var rows: [DocumentEditorRow] = []

    init(content: Resources_Common_Content_Content) {
        guard content.hasTiptapJson else {
            supportsEditing = false
            originalDoc = nil
            return
        }
        let doc = content.tiptapJson
        originalDoc = doc
        supportsEditing = true
        rows = Self.buildRows(from: doc)
    }

    /// True, sobald in mindestens einem Absatz Text geändert wurde.
    var hasChanges: Bool {
        rows.contains { row in
            switch row.kind {
            case .paragraph, .heading:
                return row.text != row.originalText
            case .readOnly:
                return false
            }
        }
    }

    /// Baut das (veränderte) Dokument aus den bearbeiteten Zeilen wieder auf.
    /// Unveränderte Zeilen tragen ihren Original-Knoten; nur editierten
    /// Absätzen/Überschriften wird ein einzelner Text-Knoten zugewiesen.
    func buildContent() -> Resources_Common_Content_Content {
        var content = Resources_Common_Content_Content()
        content.contentType = .tiptapJson
        guard let originalDoc else { return content }

        var doc = Google_Protobuf_Struct()
        for (key, value) in originalDoc.fields where key != "content" {
            doc.fields[key] = value
        }
        var values: [Google_Protobuf_Value] = []
        for row in rows {
            let node: Google_Protobuf_Struct
            switch row.kind {
            case .paragraph, .heading:
                node = (row.text != row.originalText)
                    ? Self.rebuiltNode(from: row.originalNode, text: row.text)
                    : row.originalNode
            case .readOnly:
                node = row.originalNode
            }
            values.append(.with { $0.structValue = node })
        }
        if !values.isEmpty {
            doc.fields["content"] = .with { $0.listValue = .with { $0.values = values } }
        }
        content.tiptapJson = doc
        return content
    }

    // MARK: - Row building

    private static func buildRows(from doc: Google_Protobuf_Struct) -> [DocumentEditorRow] {
        guard let values = doc.fields["content"]?.listValue.values else { return [] }
        return values.compactMap { value -> DocumentEditorRow? in
            guard case .structValue(let node)? = value.kind else { return nil }
            let type = node.fields["type"]?.stringValue ?? ""
            let children = node.fields["content"]?.listValue.values ?? []
            let childStructs = children.compactMap { child -> Google_Protobuf_Struct? in
                guard case .structValue(let childStruct)? = child.kind else { return nil }
                return childStruct
            }
            let onlyText = childStructs.allSatisfy { child in
                let childType = child.fields["type"]?.stringValue ?? ""
                return childType == "text" || childType == "hardBreak"
            }
            if (type == "paragraph" || type == "heading") && onlyText {
                if type == "heading" {
                    let level = Int(node.fields["attrs"]?.structValue.fields["level"]?.numberValue ?? 1)
                    return DocumentEditorRow(
                        node: node,
                        kind: .heading(level: min(max(level, 1), 6)),
                        text: plainText(node: node)
                    )
                }
                return DocumentEditorRow(node: node, kind: .paragraph, text: plainText(node: node))
            }
            return DocumentEditorRow(node: node, kind: .readOnly(block(for: node)), text: "")
        }
    }

    /// Renders a single Tiptap node to blocks by wrapping it in a temporary doc.
    private static func block(for node: Google_Protobuf_Struct) -> [WikiBlock] {
        var temp = Resources_Common_Content_Content()
        temp.contentType = .tiptapJson
        temp.tiptapJson = wrappingDoc(node)
        return WikiContent.blocks(for: temp)
    }

    private static func wrappingDoc(_ node: Google_Protobuf_Struct) -> Google_Protobuf_Struct {
        var doc = Google_Protobuf_Struct()
        doc.fields["type"] = .with { $0.stringValue = "doc" }
        doc.fields["content"] = .with { $0.listValue = .with {
            $0.values = [Google_Protobuf_Value.with { $0.structValue = node }]
        } }
        return doc
    }

    /// Concatenates the visible text of a paragraph/heading node (Tiptap JSON).
    private static func plainText(node: Google_Protobuf_Struct) -> String {
        let type = node.fields["type"]?.stringValue ?? ""
        var parts: [String] = []
        if type == "text", let text = node.fields["text"]?.stringValue {
            parts.append(text)
        }
        if let children = node.fields["content"]?.listValue.values {
            for child in children {
                guard case .structValue(let childStruct)? = child.kind else { continue }
                let value = plainText(node: childStruct)
                if !value.isEmpty { parts.append(value) }
            }
        }
        var result = parts.joined()
        if type == "hardBreak" {
            result += "\n"
        }
        return result
    }

    /// Rebuilds a paragraph/heading node keeping type + attrs (z. B. heading
    /// level) but replacing the content with a single text node.
    private static func rebuiltNode(from original: Google_Protobuf_Struct, text: String) -> Google_Protobuf_Struct {
        var node = Google_Protobuf_Struct()
        for (key, value) in original.fields where key == "type" || key == "attrs" {
            node.fields[key] = value
        }
        var textNode = Google_Protobuf_Struct()
        textNode.fields["type"] = .with { $0.stringValue = "text" }
        textNode.fields["text"] = .with { $0.stringValue = text }
        node.fields["content"] = .with { $0.listValue = .with {
            $0.values = [Google_Protobuf_Value.with { $0.structValue = textNode }]
        } }
        return node
    }
}

enum DocumentEditorKind {
    case paragraph
    case heading(level: Int)
    case readOnly([WikiBlock])
}

/// A single row of the content editor. Reference type so SwiftUI bindings
/// (`@Bindable`) observe text edits on the underlying @Observable object.
@Observable
final class DocumentEditorRow: Identifiable {
    let id = UUID()
    let originalNode: Google_Protobuf_Struct
    let kind: DocumentEditorKind
    var text: String
    let originalText: String

    init(node: Google_Protobuf_Struct, kind: DocumentEditorKind, text: String) {
        self.originalNode = node
        self.kind = kind
        self.text = text
        self.originalText = text
    }
}

/// Editable representation of a document's content in the detail view.
struct DocumentContentEditorView: View {
    @Environment(AppState.self) private var appState
    @Bindable var model: DocumentContentEditorModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ForEach(model.rows) { row in
                rowView(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func rowView(_ row: DocumentEditorRow) -> some View {
        @Bindable var row = row
        switch row.kind {
        case .paragraph:
            TextField("Absatz…", text: $row.text, axis: .vertical)
                .lineLimit(1...8)
                .textFieldStyle(.plain)
        case .heading(let level):
            TextField("Überschrift…", text: $row.text, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: Self.headingSize(for: level), weight: .bold))
                .textFieldStyle(.plain)
        case .readOnly(let blocks):
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                ForEach(blocks.indices, id: \.self) { index in
                    WikiBlockView(block: blocks[index], baseURL: appState.client?.baseURL)
                }
            }
        }
    }

    private static func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return 24
        case 2: return 21
        case 3: return 19
        case 4: return 17
        default: return 16
        }
    }
}
