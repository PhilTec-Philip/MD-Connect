import SwiftUI

/// Liefert die Wurzel-View eines Moduls für die Navigation in einem
/// NavigationStack. Von der Übersicht und der Quick-Ansicht gemeinsam genutzt,
/// damit die Modul-Registrierung nicht doppelt gepflegt werden muss.
@ViewBuilder
func moduleRootView(_ module: FiveNetModule) -> some View {
    switch module {
    case .centrum:
        CentrumView()
    case .livemap:
        LiveMapView()
    case .wiki:
        WikiView()
    case .citizens:
        CitizensListView()
    case .vehicles:
        VehiclesListView()
    case .documents:
        DocumentsListView()
    case .jobs:
        JobsView()
    case .qualifications:
        QualificationsView()
    case .calendar:
        CalendarView()
    case .mailer:
        MailView()
    case .settings:
        SettingsView()
    }
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
    }
}

extension View {
    func moduleDestinations() -> some View {
        modifier(ModuleDestinations())
    }
}
