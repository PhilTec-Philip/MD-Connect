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
