import SwiftUI

/// Shared placeholder for the Berufe tabs that are not implemented yet.
/// Shows which functionality will follow, based on the web module.
struct JobTabPlaceholderView: View {
    let icon: String
    let title: String
    let planned: [String]

    var body: some View {
        List {
            Section {
                LabeledContent("Status", value: "Folgt in einer späteren Version")
            }

            Section("Geplante Funktionen") {
                ForEach(planned, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Aktivität: colleague activity feed (hired/fired/promoted/…).
struct JobActivityPlaceholderView: View {
    var body: some View {
        JobTabPlaceholderView(
            icon: "list.bullet",
            title: "Aktivität",
            planned: [
                "Aktivitäts-Feed der Kollegen (Eingestellt, Entlassen, Befördert, Degradiert, …)",
                "Filter nach Aktivitäts-Typ",
                "Filter nach Kollege",
                "Seitennavigation (Prev/Next)",
            ]
        )
    }
}

/// Stempeluhr: timeclock listing + statistics + inactive employees.
struct JobTimeclockPlaceholderView: View {
    var body: some View {
        JobTabPlaceholderView(
            icon: "clock.badge.checkmark",
            title: "Stempeluhr",
            planned: [
                "Stempeluhr-Liste (täglich / wöchentlich / Zeitraum)",
                "Statistik (Summe, Ø, Max)",
                "Inaktive Kollegen (Untermenü)",
                "Ansicht: eigene Daten / alle Kollegen",
            ]
        )
    }
}

/// Führungsregister: conduct register entries (warnings, suspensions, …).
struct JobConductPlaceholderView: View {
    var body: some View {
        JobTabPlaceholderView(
            icon: "list.clipboard",
            title: "Führungsregister",
            planned: [
                "Führungsregister-Einträge (Neutral, Positiv, Negativ, Verwarnung, Suspendierung, Notiz)",
                "Detail-Ansicht mit Verfasser und Zielperson",
                "Filter nach Typ und Entwurf/abgelaufen",
                "Erstellen und Bearbeiten von Einträgen",
            ]
        )
    }
}

#Preview("Aktivität") {
    NavigationStack {
        JobActivityPlaceholderView()
    }
}

#Preview("Stempeluhr") {
    NavigationStack {
        JobTimeclockPlaceholderView()
    }
}

#Preview("Führungsregister") {
    NavigationStack {
        JobConductPlaceholderView()
    }
}
