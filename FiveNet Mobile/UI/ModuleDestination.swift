import SwiftUI

/// Meldet an den AppState, welches Modul gerade geöffnet ist (für den
/// Bildschirmschoner). Wird an die Modul-Wurzel gehängt: Erscheint sie,
/// wird das Modul gesetzt. Das Zurücksetzen auf `nil` übernimmt die
/// Overview-/Quick-Wurzel (`.onAppear`), sobald der Nutzer zurücknavigiert.
private struct ModuleTrackingModifier: ViewModifier {
    @Environment(AppState.self) private var appState
    let module: FiveNetModule

    func body(content: Content) -> some View {
        content
            .onAppear {
                appState.setActiveModule(module)
            }
    }
}

extension View {
    /// Registriert das Modul als „aktiv" im AppState (Bildschirmschoner-Gating).
    func trackingModule(_ module: FiveNetModule) -> some View {
        modifier(ModuleTrackingModifier(module: module))
    }
}

/// Liefert die Wurzel-View eines Moduls für die Navigation in einem
/// NavigationStack. Von der Übersicht und der Quick-Ansicht gemeinsam genutzt,
/// damit die Modul-Registrierung nicht doppelt gepflegt werden muss. Optional
/// wird ein direktes Tab-Ziel (Schnellzugriff) vorausgewählt.
@ViewBuilder
func moduleRootView(_ module: FiveNetModule, initialTab: QuickAccessTab? = nil) -> some View {
    Group {
        switch module {
        case .centrum:
            CentrumView(initialTab: initialTab)
        case .livemap:
            LiveMapView(initialTab: initialTab)
        case .jobs:
            JobsView(initialTab: initialTab)
        case .wiki:
            WikiView()
        case .citizens:
            CitizensListView()
        case .vehicles:
            VehiclesListView()
        case .documents:
            DocumentsListView()
        case .qualifications:
            QualificationsView(initialTab: initialTab)
        case .calendar:
            CalendarView()
        case .mailer:
            MailView(initialTab: initialTab)
        case .settings:
            SettingsView()
        }
    }
    .trackingModule(module)
}

/// Registriert die modulübergreifenden Detail-Ziele auf einem NavigationStack.
/// Wird von der Übersicht UND der Quick-Ansicht angewandt, damit Details (z. B.
/// Kollege aus einer Einheiten-Info) in beiden Stacks erreichbar sind.
struct ModuleDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: CitizenRoute.self) { route in
                CitizenDetailView(userID: route.userID)
            }
            .navigationDestination(for: UnitRoute.self) { route in
                UnitDetailView(unitID: route.unitID)
            }
            .navigationDestination(for: ColleagueRoute.self) { route in
                ColleagueDetailView(userID: route.userID)
            }
            .navigationDestination(for: ConductRoute.self) { route in
                ConductEntryDetailView(entryID: route.entryID)
            }
            .navigationDestination(for: QualificationRoute.self) { route in
                QualificationDetailView(qualificationID: route.qualificationID)
            }
            .navigationDestination(for: GroupRoute.self) { route in
                JobGroupDetailView(groupID: route.groupID)
            }
    }
}

extension View {
    func moduleDestinations() -> some View {
        modifier(ModuleDestinations())
    }
}
