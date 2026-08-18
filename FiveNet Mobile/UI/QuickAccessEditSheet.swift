import SwiftUI

/// Sheet zum Bearbeiten des Schnellzugriffs der Startseite: Module und direkte
/// Tab-Ziele auswählen, anordnen und entfernen. Wird pro Server gespeichert.
struct QuickAccessEditSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var items: [QuickAccessItem] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if items.isEmpty {
                        Text("Noch keine Schnellzugriffe konfiguriert. Füge unten Module oder Tabs hinzu.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, Theme.Spacing.sm)
                    } else {
                        ForEach(items) { item in
                            row(item)
                        }
                        .onMove { indices, newOffset in
                            items.move(fromOffsets: indices, toOffset: newOffset)
                        }
                        .onDelete { indices in
                            items.remove(atOffsets: indices)
                        }
                    }
                } header: {
                    Text("Schnellzugriff")
                } footer: {
                    Text("Wischen zum Entfernen, Ziehen zum Sortieren. Ein Tab öffnet das Modul direkt auf der ausgewählten Ansicht.")
                }

                if !addableModules.isEmpty || !addableTabs.isEmpty {
                    Section("Hinzufügen") {
                        if !addableModules.isEmpty {
                            ForEach(addableModules) { module in
                                Button {
                                    withAnimation {
                                        items.append(.module(module))
                                    }
                                } label: {
                                    Label(module.title, systemImage: module.icon)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }

                        if !addableTabs.isEmpty {
                            ForEach(addableTabs) { tab in
                                Button {
                                    withAnimation {
                                        items.append(.tab(tab))
                                    }
                                } label: {
                                    HStack {
                                        Label(tab.label, systemImage: tab.icon)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(tab.module.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Schnellzugriff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") {
                        appState.setQuickAccessItems(items)
                        dismiss()
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .onAppear {
                items = appState.effectiveQuickAccess
            }
        }
    }

    /// Aktuelle Zeile mit Drag-Handle (Reihenfolge) und direktem Entfernen.
    private func row(_ item: QuickAccessItem) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: item.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(item.module.tint)
                .frame(width: 28, height: 28)
                .background(item.module.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(item.title)
                    .foregroundStyle(.primary)
                Text(item.module.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    /// Zugängliche Module, die noch nicht als ganzes Modul im Schnellzugriff
    /// sind (ein bereits enthaltener Tab schließt das Modul selbst nicht aus).
    private var addableModules: [FiveNetModule] {
        appState.accessibleModules.filter { module in
            !items.contains { if case .module(let m) = $0 { return m == module }; return false }
        }
    }

    /// Zugängliche Tab-Ziele, die noch nicht als Tab im Schnellzugriff sind.
    /// Ein als ganzes Modul angeheftetes Modul schließt seine Tabs NICHT aus —
    /// so kann man gezielt einzelne Ansichten anheften, auch wenn das Modul
    /// selbst bereits im Schnellzugriff ist.
    private var addableTabs: [QuickAccessTab] {
        QuickAccessTab.allCases.filter { tab in
            appState.accessibleModules.contains(tab.module)
                && !items.contains { if case .tab(let existing) = $0 { return existing == tab }; return false }
        }
    }
}