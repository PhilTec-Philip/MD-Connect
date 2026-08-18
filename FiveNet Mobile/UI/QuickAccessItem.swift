import SwiftUI

/// Schnellzugriffs-Ziel auf der Startseite: entweder ein ganzes Modul oder ein
/// direktes Tab-Ziel innerhalb eines Moduls (z. B. Leitstelle → Einsätze).
enum QuickAccessItem: Hashable, Identifiable {
    case module(FiveNetModule)
    case tab(QuickAccessTab)

    /// Stabiles, persistierbares Identifikations-Token (`module-livemap` /
    /// `tab-centrum-dispatches`). In UserDefaults pro Server gespeichert.
    var id: String {
        switch self {
        case .module(let module): "module-\(module.rawValue)"
        case .tab(let tab): "tab-\(tab.rawValue)"
        }
    }

    /// Rekonstruiert ein Item aus seinem persistierten `id`-Token.
    init?(id: String) {
        if id.hasPrefix("module-"),
           let module = FiveNetModule(rawValue: String(id.dropFirst("module-".count))) {
            self = .module(module)
        } else if id.hasPrefix("tab-"),
                  let tab = QuickAccessTab(rawValue: String(id.dropFirst("tab-".count))) {
            self = .tab(tab)
        } else {
            return nil
        }
    }

    var module: FiveNetModule {
        switch self {
        case .module(let module): module
        case .tab(let tab): tab.module
        }
    }

    /// Das Tab-Ziel (nil für reine Modul-Einträge).
    var tab: QuickAccessTab? {
        if case .tab(let tab) = self { return tab }
        return nil
    }

    var title: String {
        switch self {
        case .module(let module): module.title
        case .tab(let tab): tab.label
        }
    }

    var icon: String {
        switch self {
        case .module(let module): module.icon
        case .tab(let tab): tab.icon
        }
    }
}

/// Direkte Tab-Ziele innerhalb von Modulen mit Tabs, die im Schnellzugriff
/// per One-Tap erreicht werden können. `module` + `label`/`icon` beschreiben
/// das Ziel; die Modul-Wurzel (Centrum/Jobs/Livemap) wählt den Tab aus.
enum QuickAccessTab: String, CaseIterable, Hashable, Identifiable {
    // Leitstelle
    case centrumDispatches
    case centrumUnits
    case centrumActivity
    case centrumArchive
    // Berufe
    case jobsOverview
    case jobsColleagues
    case jobsGroups
    case jobsActivity
    case jobsTimeclock
    case jobsConduct
    // Livemap
    case livemapDuty
    case livemapMap
    case livemapUnits
    // Mail
    case mailInbox
    case mailArchive
    // Qualifikationen
    case qualificationsOwn
    case qualificationsAll

    var id: String { rawValue }

    var module: FiveNetModule {
        switch self {
        case .centrumDispatches, .centrumUnits, .centrumActivity, .centrumArchive: .centrum
        case .jobsOverview, .jobsColleagues, .jobsGroups, .jobsActivity, .jobsTimeclock, .jobsConduct: .jobs
        case .livemapDuty, .livemapMap, .livemapUnits: .livemap
        case .mailInbox, .mailArchive: .mailer
        case .qualificationsOwn, .qualificationsAll: .qualifications
        }
    }

    var label: String {
        switch self {
        case .centrumDispatches: "Einsätze"
        case .centrumUnits: "Einheiten"
        case .centrumActivity: "Aktivität"
        case .centrumArchive: "Archiv"
        case .jobsOverview: "Übersicht"
        case .jobsColleagues: "Kollegen"
        case .jobsGroups: "Gruppen"
        case .jobsActivity: "Aktivität"
        case .jobsTimeclock: "Stempeluhr"
        case .jobsConduct: "Führungsregister"
        case .livemapDuty: "Meine Einheit"
        case .livemapMap: "Karte"
        case .livemapUnits: "Einheiten"
        case .mailInbox: "Posteingang"
        case .mailArchive: "Archiv"
        case .qualificationsOwn: "Ihre Qualifizierungen"
        case .qualificationsAll: "Alle Qualifizierungen"
        }
    }

    var icon: String {
        switch self {
        case .centrumDispatches: "exclamationmark.triangle"
        case .centrumUnits: "building.2"
        case .centrumActivity: "list.bullet"
        case .centrumArchive: "archivebox"
        case .jobsOverview: "house"
        case .jobsColleagues: "person.2"
        case .jobsGroups: "person.3"
        case .jobsActivity: "list.bullet"
        case .jobsTimeclock: "clock.badge.checkmark"
        case .jobsConduct: "list.clipboard"
        case .livemapDuty: "person.crop.circle"
        case .livemapMap: "map"
        case .livemapUnits: "building.2"
        case .mailInbox: "tray"
        case .mailArchive: "archivebox"
        case .qualificationsOwn: "checkmark.seal"
        case .qualificationsAll: "books.vertical"
        }
    }
}