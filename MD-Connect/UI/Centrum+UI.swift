import SwiftUI
import SwiftProtobuf

/// Navigation routes for the centrum module. Using a distinct type instead of
/// a bare `Int64` allows registering a single `navigationDestination` on the
/// non-lazy container (`CentrumView`) without conflicts between dispatch and
/// unit ids.
enum CentrumRoute: Hashable {
    case dispatch(Int64)
    case unit(Int64)
}

extension Color {
    /// Creates a color from a `#RRGGBB` hex string (e.g. unit/marker colors
    /// from the server). Returns nil for malformed input.
    init?(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Kompaktes Capsule-ID-Badge (z.B. `CIT-<id>`, `DOC-<id>`, `QUAL-<id>`).
/// Gemeinsames Design für alle IDs in Listen-Zeilen (Web `IDCopyBadge`).
struct IDBadge: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(verbatim: text)
            .font(.caption2.monospaced().weight(.semibold))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

extension Resources_Centrum_Dispatches_StatusDispatch {
    var label: String {
        switch self {
        case .unspecified: return "Unbekannt"
        case .new: return "Neu"
        case .unassigned: return "Nicht zugewiesen"
        case .updated: return "Aktualisiert"
        case .unitAssigned: return "Einheit zugewiesen"
        case .unitUnassigned: return "Einheit entfernt"
        case .unitAccepted: return "Einheit akzeptiert"
        case .unitDeclined: return "Einheit abgelehnt"
        case .enRoute: return "Auf dem Weg"
        case .onScene: return "Am Einsatzort"
        case .needAssistance: return "Braucht Hilfe"
        case .completed: return "Abgeschlossen"
        case .cancelled: return "Abgebrochen"
        case .archived: return "Archiviert"
        case .deleted: return "Gelöscht"
        case .UNRECOGNIZED: return "Unbekannt"
        }
    }

    var color: Color {
        switch self {
        case .new: return .red
        case .unassigned: return .orange
        case .updated: return .blue
        case .unitAssigned: return .teal
        case .unitUnassigned: return .red
        case .unitAccepted: return .blue
        case .unitDeclined: return .pink
        case .enRoute: return .yellow
        case .onScene: return .green
        case .needAssistance: return .red
        case .completed: return .green
        case .cancelled: return .gray
        case .archived: return .gray
        case .deleted: return .gray
        default: return .secondary
        }
    }
}

// MARK: - Document approval status

/// Approval-Status eines Dokuments nach Web `ApprovalBadge.vue`
/// („Genehmigt“ / „Abgelehnt“ / „Nicht genehmigt“).
enum DocumentApprovalStatus {
    case none
    case approved
    case declined
    case unapproved

    init(meta: Resources_Documents_DocumentMeta) {
        guard meta.hasApPoliciesActive, meta.apPoliciesActive > 0 else {
            self = .none
            return
        }
        if meta.hasApproved, meta.approved {
            self = .approved
        } else if meta.hasApDeclinedCount, meta.apDeclinedCount > 0 {
            self = .declined
        } else {
            self = .unapproved
        }
    }

    var label: String {
        switch self {
        case .none: return ""
        case .approved: return "Genehmigt"
        case .declined: return "Abgelehnt"
        case .unapproved: return "Nicht genehmigt"
        }
    }

    var color: Color {
        switch self {
        case .none: return .gray
        case .approved: return .green
        case .declined: return .red
        case .unapproved: return .orange
        }
    }
}

/// Compact approval status badge (Web `ApprovalBadge`).
struct DocumentApprovalBadge: View {
    let meta: Resources_Documents_DocumentMeta

    var body: some View {
        let status = DocumentApprovalStatus(meta: meta)
        if status != .none {
            Text(status.label)
                .font(.caption2.bold())
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xxs)
                .foregroundStyle(.white)
                .background(status.color)
                .clipShape(Capsule())
        }
    }
}


extension Resources_Centrum_Units_StatusUnit {
    var label: String {
        switch self {
        case .unspecified: return "Unbekannt"
        case .unknown: return "Unbekannt"
        case .userAdded: return "Hinzugefügt"
        case .userRemoved: return "Entfernt"
        case .unavailable: return "Nicht verfügbar"
        case .available: return "Verfügbar"
        case .onBreak: return "Pause"
        case .busy: return "Beschäftigt"
        case .UNRECOGNIZED: return "Unbekannt"
        }
    }

    var color: Color {
        switch self {
        case .available: return .green
        case .onBreak: return .blue
        case .busy: return .orange
        case .unavailable: return .red
        default: return .secondary
        }
    }
}

extension Resources_Centrum_Dispatches_DispatchAttribute {
    var label: String {
        switch self {
        case .unspecified: return "–"
        case .multiple: return "Mehrfach"
        case .duplicate: return "Duplikat"
        case .tooOld: return "Zu alt"
        case .automatic: return "Automatisch"
        case .UNRECOGNIZED: return "–"
        }
    }
}

func formatTimestamp(_ timestamp: Resources_Timestamp_Timestamp) -> String {
    timestamp.timestamp.date.formatted(date: .abbreviated, time: .shortened)
}

func formatRelative(_ timestamp: Resources_Timestamp_Timestamp) -> String {
    timestamp.timestamp.date.formatted(.relative(presentation: .named))
}

/// Formats a number of seconds as a human-readable duration like "8h 30m".
/// Mirrors the web `fromSecondsToFormattedDuration`.
func formatDuration(seconds: Int64) -> String {
    let seconds = max(0, seconds)
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }
    return "\(minutes)m"
}

/// Formats a timeclock spent time (stored in hours) as a duration string.
func formatSpentTime(hours: Float) -> String {
    formatDuration(seconds: Int64(hours * 3600))
}

/// Formats a dispatch id the way the web client does: `DSP-<id>`.
func formatDispatchID(_ id: Int64) -> String {
    "DSP-\(id)"
}

/// Formats a document id as a DOC-<id> string without any number grouping.
/// (SwiftUI's `LocalizedStringKey` interpolation would otherwise render a
/// decimal id like DOC-71.350 instead of DOC-71350.)
func formatDocumentID(_ id: Int64) -> String {
    "DOC-\(id)"
}

/// Formats a user's short name (first + last name).
func userShortName(_ user: Resources_Users_Short_UserShort) -> String {
    [user.firstname, user.lastname]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

/// Formats a phone number as (480) 800-8961 when possible.
func formatPhoneNumber(_ number: String) -> String {
    let digits = number.filter { $0.isNumber }
    guard !digits.isEmpty else { return number }
    if digits.count == 10 {
        let ndc = String(digits.prefix(3))
        let mid = String(digits.dropFirst(3).prefix(3))
        let last = String(digits.dropFirst(6))
        return "(\(ndc)) \(mid)-\(last)"
    }
    return number
}

/// Builds a `UserShort` from a full `User` (for the clipboard / template data).
func userShort(from user: Resources_Users_User) -> Resources_Users_Short_UserShort {
    Resources_Users_Short_UserShort.with { short in
        short.userID = user.userID
        short.job = user.job
        short.jobLabel = user.jobLabel
        short.jobGrade = user.jobGrade
        short.jobGradeLabel = user.jobGradeLabel
        short.firstname = user.firstname
        short.lastname = user.lastname
        short.dateofbirth = user.dateofbirth
        short.phoneNumber = user.phoneNumber
    }
}

/// Fallback "nicht gesetzt" marker for optional detail values.
func orNA(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "k.A." }
    return value
}

/// Resolves the sender of a dispatch: "Gesendet von <name>".
func sentByLabel(_ dispatch: Resources_Centrum_Dispatches_Dispatch) -> String {
    if dispatch.anon {
        return "Gesendet von Anonym"
    }
    let user = dispatch.creator
    let name = [user.firstname, user.lastname].filter { !$0.isEmpty }.joined(separator: " ")
    guard !name.isEmpty else { return "Gesendet von Unbekannt" }
    return "Gesendet von \(name)"
}

/// Name of a colleague (feed entries / unit members).
func colleagueName(_ colleague: Resources_Jobs_Colleagues_Colleague) -> String {
    let name = [colleague.firstname, colleague.lastname].filter { !$0.isEmpty }.joined(separator: " ")
    return name.isEmpty ? "Benutzer" : name
}

/// Reconstructs the previous grade for each grade-change activity entry.
/// `GradeChange` only carries the target grade, so the "old" grade is taken
/// from the next older grade-change entry in the (newest-first) list.
func previousGradeLookup(for activity: [Resources_Jobs_Colleagues_Activity_ColleagueActivity]) -> [Int64: Int32] {
    var lookup: [Int64: Int32] = [:]
    var previousGrade: Int32?
    for entry in activity.reversed() {
        if case .gradeChange(let change)? = entry.data.data {
            if let previousGrade {
                lookup[entry.id] = previousGrade
            }
            previousGrade = change.grade
        }
    }
    return lookup
}

/// Human-readable details of a colleague activity entry (rank change, absence
/// date, label/name changes) plus the stored reason. Shared by the colleague
/// detail and the global activity feed so both show the same detail.
func colleagueActivitySubtitle(
    _ entry: Resources_Jobs_Colleagues_Activity_ColleagueActivity,
    previousGrade: Int32? = nil,
    includeTimestamp: Bool = true
) -> String {
    var parts: [String] = []
    if includeTimestamp, entry.hasCreatedAt, entry.createdAt.timestamp.date.timeIntervalSince1970 > 0 {
        parts.append(formatRelative(entry.createdAt))
    }
    if let data = entry.data.data {
        switch data {
        case .gradeChange(let change):
            var gradeParts: [String] = []
            if let from = previousGrade {
                gradeParts.append("von Rang \(from)")
            }
            let toLabel = change.gradeLabel.isEmpty ? String(change.grade) : change.gradeLabel
            gradeParts.append("auf \(toLabel)")
            parts.append(gradeParts.joined(separator: " "))
        case .absenceDate(let change):
            if change.hasAbsenceBegin && change.hasAbsenceEnd {
                let begin = change.absenceBegin.timestamp.date.formatted(date: .abbreviated, time: .omitted)
                let end = change.absenceEnd.timestamp.date.formatted(date: .abbreviated, time: .omitted)
                parts.append("\(begin) – \(end)")
            } else {
                parts.append("Aufgehoben")
            }
        case .labelsChange(let change):
            var labelParts: [String] = []
            if !change.added.isEmpty {
                labelParts.append("+ \(change.added.map(\.name).joined(separator: ", "))")
            }
            if !change.removed.isEmpty {
                labelParts.append("− \(change.removed.map(\.name).joined(separator: ", "))")
            }
            if !labelParts.isEmpty {
                parts.append(labelParts.joined(separator: " "))
            }
        case .nameChange(let change):
            var nameParts: [String] = []
            if change.hasPrefix {
                nameParts.append("Präfix: \(change.prefix.isEmpty ? "–" : change.prefix)")
            }
            if change.hasSuffix {
                nameParts.append("Suffix: \(change.suffix.isEmpty ? "–" : change.suffix)")
            }
            if !nameParts.isEmpty {
                parts.append(nameParts.joined(separator: " · "))
            }
        }
    }
    if !entry.reason.isEmpty {
        parts.append(entry.reason)
    }
    return parts.joined(separator: " · ")
}

/// Ignore the generic plugin default messages ("Notruf" / "Manueller Notruf")
/// and only surface actual dispatch messages.
func dispatchMessageText(_ dispatch: Resources_Centrum_Dispatches_Dispatch) -> String? {
    let message = dispatch.message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty else { return nil }
    let genericDefaults: Set<String> = ["Notruf", "Manueller Notruf", "Manual Dispatch", "911"]
    guard !genericDefaults.contains(message) else { return nil }
    return message
}

extension Resources_Centrum_Dispatches_DispatchStatus {
    var feedLabel: String {
        switch status {
        case .unspecified: return "Unbekannter Einsatz-Status"
        case .new: return "Einsatz erstellt"
        case .unassigned: return "Keine Einheiten an Einsatz zugewiesen"
        case .updated: return "Einsatz aktualisiert"
        case .unitAssigned: return "Einheit an Einsatz zugewiesen"
        case .unitUnassigned: return "Einheit von Einsatz abgezogen"
        case .unitAccepted: return "Einsatz von Einheit akzeptiert"
        case .unitDeclined: return "Einsatz von Einheit abgelehnt"
        case .enRoute: return "Auf dem Weg zum Einsatz"
        case .onScene: return "Vor Ort zum Einsatz"
        case .needAssistance: return "Einheit benötigt Verstärkung"
        case .completed: return "Einsatz abgeschlossen"
        case .cancelled: return "Einsatz abgebrochen"
        case .archived: return "Einsatz archiviert"
        case .deleted: return "Einsatz gelöscht"
        case .UNRECOGNIZED: return "Unbekannter Einsatz-Status"
        }
    }

    var feedIcon: String {
        switch status {
        case .new, .updated: return "shippingbox"
        case .unassigned: return "person.crop.circle.badge.exclamationmark"
        case .unitAssigned: return "person.badge.plus"
        case .unitUnassigned: return "person.badge.minus"
        case .unitAccepted: return "checkmark.seal"
        case .unitDeclined: return "xmark.seal"
        case .enRoute: return "car"
        case .onScene: return "mappin.and.ellipse"
        case .needAssistance: return "exclamationmark.bubble"
        case .completed: return "checkmark"
        case .cancelled: return "xmark"
        case .archived: return "archivebox"
        case .deleted: return "trash"
        case .unspecified, .UNRECOGNIZED: return "questionmark"
        }
    }
}

extension Resources_Centrum_Units_UnitStatus {
    var feedLabel: String {
        switch status {
        case .unspecified: return "Unbekannter Einheiten-Status"
        case .unknown: return "Unbekannter Einheiten-Status"
        case .userAdded: return "Mitglied zu Einheit hinzugefügt"
        case .userRemoved: return "Mitglied von Einheit entfernt"
        case .unavailable: return "Einheit nicht verfügbar"
        case .available: return "Einheit verfügbar"
        case .onBreak: return "Einheit auf Pause"
        case .busy: return "Einheit beschäftigt"
        case .UNRECOGNIZED: return "Unbekannter Einheiten-Status"
        }
    }

    var feedIcon: String {
        switch status {
        case .userAdded: return "person.badge.plus"
        case .userRemoved: return "person.badge.minus"
        case .unavailable: return "stop.circle"
        case .available: return "play.circle"
        case .onBreak: return "cup.and.saucer"
        case .busy: return "briefcase"
        case .unspecified, .unknown, .UNRECOGNIZED: return "questionmark"
        }
    }
}

/// Shared row for activity feed entries (unit / dispatch status history).
struct ActivityRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 24, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }
}

/// Shows a transient confirmation toast (e.g. "Kopiert") anchored to the
/// bottom of the content. Automatically hides after a short delay.
private struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let systemImage: String
    let duration: Duration

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isPresented {
                    Label(message, systemImage: systemImage)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, Theme.Spacing.xl)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.quaternary))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                        .padding(.bottom, Theme.Spacing.lg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            Task {
                                try? await Task.sleep(for: duration)
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isPresented = false
                                }
                            }
                        }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isPresented)
    }
}

extension View {
    /// Presents a transient bottom toast while `isPresented` is `true`.
    func toast(isPresented: Binding<Bool>, message: String, systemImage: String = "checkmark.circle.fill", duration: Duration = .seconds(1.6)) -> some View {
        modifier(ToastModifier(isPresented: isPresented, message: message, systemImage: systemImage, duration: duration))
    }
}

extension Resources_Jobs_Conduct_ConductType {
    /// SF Symbol shown for this conduct register type.
    var icon: String {
        switch self {
        case .positive: return "hand.thumbsup"
        case .negative: return "hand.thumbsdown"
        case .warning: return "exclamationmark.triangle"
        case .suspension: return "pause.circle"
        case .note: return "note.text"
        case .neutral, .unspecified, .UNRECOGNIZED: return "circle.lefthalf.filled"
        }
    }

    /// German label for the conduct register type.
    var label: String {
        switch self {
        case .positive: return "Positiv"
        case .negative: return "Negativ"
        case .warning: return "Verwarnung"
        case .suspension: return "Suspendierung"
        case .note: return "Notiz"
        case .neutral, .unspecified, .UNRECOGNIZED: return "Neutral"
        }
    }

    /// Row/tint color for the conduct register type. Mirrors the web
    /// `conductTypesToBadgeColor` (helpers.ts): positive→green, negative→red,
    /// warning→orange, suspension→blue, note→gray, neutral→white/neutral.
    var tint: Color {
        switch self {
        case .positive: return .green
        case .negative: return .red
        case .warning: return .orange
        case .suspension: return .blue
        case .note: return .gray
        case .neutral, .unspecified, .UNRECOGNIZED: return .primary.opacity(0.85)
        }
    }
}

extension Resources_Jobs_Timeclock_TimeclockMode {
    /// German label for the timeclock mode.
    var label: String {
        switch self {
        case .daily: return "Täglich"
        case .weekly: return "Wöchentlich"
        case .range: return "Zeitraum"
        case .timeline: return "Timeline"
        case .unspecified, .UNRECOGNIZED: return "Zeitraum"
        }
    }
}

extension Resources_Jobs_Timeclock_TimeclockViewMode {
    /// German label for the timeclock view mode.
    var label: String {
        switch self {
        case .self_: return "Eigene"
        case .all: return "Alle"
        case .unspecified, .UNRECOGNIZED: return "Alle"
        }
    }
}
