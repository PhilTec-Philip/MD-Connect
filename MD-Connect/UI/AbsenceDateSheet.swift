import SwiftUI
import SwiftProtobuf

/// Sheet for setting/resetting the absence date (Urlaub) of a colleague.
/// Mirrors the web `SelfServiceAbsenceDateModal`.
struct AbsenceDateSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let colleague: Resources_Jobs_Colleagues_Colleague?

    @State private var reason = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(86400)
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isConfirmingReset = false

    /// Called with the updated colleague after a successful save.
    @Environment(\.absenceSavedHandler) private var onAbsenceSaved

    var body: some View {
        NavigationStack {
            Form {
                Section("Zeitraum") {
                    DatePicker("Von", selection: $start, displayedComponents: .date)
                    DatePicker("Bis", selection: $end, displayedComponents: .date)
                }

                Section("Grund") {
                    TextField("Grund (mind. 3 Zeichen)", text: $reason)
                }

                if existingAbsence != nil {
                    Section {
                        Button("Aktuellen Urlaub aufheben", role: .destructive) {
                            isConfirmingReset = true
                        }
                        .disabled(isSaving)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Palette.danger)
                    }
                }
            }
            .navigationTitle("Urlaub eintragen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        Task { await save(reset: false) }
                    }
                    .disabled(isSaving || reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .confirmationDialog(
            "Aktuellen Urlaub wirklich aufheben?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Aufheben", role: .destructive) {
                Task { await save(reset: true) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der eingetragene Urlaub wird entfernt und der Kollege ist wieder verfügbar.")
        }
        .onAppear {
            if let props = colleague?.props, props.hasAbsenceBegin, props.hasAbsenceEnd {
                start = props.absenceBegin.timestamp.date
                end = props.absenceEnd.timestamp.date
            }
        }
    }

    private var existingAbsence: Resources_Jobs_Colleagues_ColleagueProps? {
        guard let props = colleague?.props, props.hasAbsenceBegin || props.hasAbsenceEnd else { return nil }
        return props
    }

    private func save(reset: Bool) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let userID = colleague?.userID ?? appState.character?.userID ?? 0
            var props = Resources_Jobs_Colleagues_ColleagueProps()
            props.userID = userID
            props.job = appState.character?.job ?? ""
            if !reset {
                props.absenceBegin = toTimestamp(start)
                props.absenceEnd = toTimestamp(end)
            }
            let saved = try await appState.setColleagueProps(props, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines))
            var updated = colleague ?? Resources_Jobs_Colleagues_Colleague()
            updated.props = saved
            onAbsenceSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AbsenceSavedKey: EnvironmentKey {
    static let defaultValue: (Resources_Jobs_Colleagues_Colleague) -> Void = { _ in }
}

extension EnvironmentValues {
    var absenceSavedHandler: (Resources_Jobs_Colleagues_Colleague) -> Void {
        get { self[AbsenceSavedKey.self] }
        set { self[AbsenceSavedKey.self] = newValue }
    }
}

extension View {
    /// Applies a callback that fires when a presented `AbsenceDateSheet`
    /// reports a saved absence date (used to refresh the presenting view).
    func onAbsenceSaved(_ handler: @escaping (Resources_Jobs_Colleagues_Colleague) -> Void) -> some View {
        environment(\.absenceSavedHandler, handler)
    }
}

/// Converts a Swift `Date` to the FiveNet timestamp proto.
private func toTimestamp(_ date: Date) -> Resources_Timestamp_Timestamp {
    Resources_Timestamp_Timestamp.with {
        $0.timestamp.seconds = Int64(date.timeIntervalSince1970)
    }
}

#Preview {
    AbsenceDateSheet(colleague: nil)
        .environment(AppState())
}
