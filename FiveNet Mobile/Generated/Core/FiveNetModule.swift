import SwiftUI

/// The modules shown on the overview screen. Access is enforced server-side
/// by FiveNet; the app only presents the available modules.
enum FiveNetModule: String, CaseIterable, Identifiable {
    case citizens
    case vehicles
    case documents
    case jobs
    case centrum
    case calendar
    case livemap
    case wiki
    case qualifications
    case mailer
    case settings

    var id: String { rawValue }

    /// The gRPC service this module maps to (permission namespace).
    var service: String { rawValue }

    var title: String {
        switch self {
        case .citizens: "Bürger"
        case .vehicles: "Fahrzeuge"
        case .documents: "Dokumente"
        case .jobs: "Berufe"
        case .centrum: "Leitstelle"
        case .calendar: "Kalender"
        case .livemap: "Livemap"
        case .wiki: "Wiki"
        case .qualifications: "Qualifikationen"
        case .mailer: "Mail"
        case .settings: "Einstellungen"
        }
    }

    var subtitle: String {
        switch self {
        case .citizens: "Personen, Kontakte und Profile"
        case .vehicles: "Fahrzeugbestand und Eigentümer"
        case .documents: "Dokumente und Vorlagen"
        case .jobs: "Berufsverwaltung und Personal"
        case .centrum: "Leitstellendienst"
        case .calendar: "Termine und Schichten"
        case .livemap: "Live-Karte"
        case .wiki: "Wissensdatenbank"
        case .qualifications: "Qualifikationen der Mitarbeiter"
        case .mailer: "Mail-System"
        case .settings: "Server-Einstellungen"
        }
    }

    var icon: String {
        switch self {
        case .citizens: "person.2.fill"
        case .vehicles: "car.fill"
        case .documents: "doc.richtext.fill"
        case .jobs: "briefcase.fill"
        case .centrum: "building.2.fill"
        case .calendar: "calendar"
        case .livemap: "map.fill"
        case .wiki: "book.fill"
        case .qualifications: "checkmark.seal.fill"
        case .mailer: "envelope.fill"
        case .settings: "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .citizens: Self.citizenColor
        case .vehicles: Self.vehicleColor
        case .documents: Self.documentColor
        case .jobs: Self.jobColor
        case .centrum: Self.centrumColor
        case .calendar: Self.calendarColor
        case .livemap: Self.livemapColor
        case .wiki: Self.wikiColor
        case .qualifications: Self.qualificationColor
        case .mailer: Self.mailerColor
        case .settings: Self.settingsColor
        }
    }

    /// Kurated, dezente Modul-Farbpalette (Tailwind-artig, nicht die neon-
    /// Systemfarben), die über die ganze App konsistent für Badges, Icons und
    /// Kachel-Verläufe verwendet wird.
    private static let citizenColor = Color(red: 0.231, green: 0.510, blue: 0.965)
    private static let vehicleColor = Color(red: 0.973, green: 0.451, blue: 0.086)
    private static let documentColor = Color(red: 0.388, green: 0.400, blue: 0.945)
    private static let jobColor = Color(red: 0.133, green: 0.773, blue: 0.369)
    private static let centrumColor = Color(red: 0.545, green: 0.361, blue: 0.965)
    private static let calendarColor = Color(red: 0.937, green: 0.267, blue: 0.267)
    private static let livemapColor = Color(red: 0.957, green: 0.263, blue: 0.369)
    private static let wikiColor = Color(red: 0.024, green: 0.714, blue: 0.831)
    private static let qualificationColor = Color(red: 0.078, green: 0.722, blue: 0.651)
    private static let mailerColor = Color(red: 0.063, green: 0.725, blue: 0.506)
    private static let settingsColor = Color(red: 0.392, green: 0.451, blue: 0.545)

    /// Farb-Verlauf für Kacheln/Köpfe (von → bis), passend zum Modul-Tint.
    var gradient: [Color] {
        switch self {
        case .citizens: [Self.citizenColor, Self.documentColor]
        case .vehicles: [Self.vehicleColor, Self.calendarColor]
        case .documents: [Self.documentColor, Self.centrumColor]
        case .jobs: [Self.jobColor, Self.qualificationColor]
        case .centrum: [Self.centrumColor, Self.documentColor]
        case .calendar: [Self.calendarColor, Self.vehicleColor]
        case .livemap: [Self.livemapColor, Self.centrumColor]
        case .wiki: [Self.wikiColor, Self.citizenColor]
        case .qualifications: [Self.qualificationColor, Self.citizenColor]
        case .mailer: [Self.mailerColor, Self.wikiColor]
        case .settings: [Self.settingsColor, Color(red: 0.30, green: 0.34, blue: 0.42)]
        }
    }

    /// Module, die im Schnellzugriff der Startseite angeboten werden (falls
    /// zugänglich), in Prioritätsreihenfolge.
    static let quickAccessOrder: [FiveNetModule] = [
        .livemap, .centrum, .calendar, .jobs,
    ]

    var requiredPermission: String? { nil }
}
