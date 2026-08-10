import SwiftUI
import SwiftProtobuf

/// Ein Abwesenheitszeitraum eines Kollegen (Urlaub), abgeleitet aus den
/// Colleague-Props (`absenceBegin`/`absenceEnd`).
struct CalendarAbsence: Identifiable {
    let colleague: Resources_Jobs_Colleagues_Colleague

    var id: Int32 { colleague.userID }

    var name: String {
        [colleague.firstname, colleague.lastname]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var begin: Date { colleague.props.absenceBegin.timestamp.date }
    var end: Date { colleague.props.absenceEnd.timestamp.date }

    func covers(_ day: Date, calendar: Calendar) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        let b = calendar.startOfDay(for: begin)
        let e = calendar.startOfDay(for: end)
        return dayStart >= b && dayStart <= e
    }

    /// "12.08." / "12.–18.08.2026" (deutsches Datumsformat).
    var rangeText: String {
        let dayFmt = "dd.MM."
        let fullFmt = "dd.MM.yyyy"
        let b = Self.dateFormatter(fullFmt).string(from: begin)
        let e = Self.dateFormatter(fullFmt).string(from: end)
        let sameDay = Self.dateFormatter(dayFmt).string(from: begin) == Self.dateFormatter(dayFmt).string(from: end)
        if sameDay { return b }
        return "\(b) – \(e)"
    }

    private static func dateFormatter(_ format: String = "dd.MM.yyyy") -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = format
        return f
    }
}

/// Ein Eintrag eines FiveNet-Kalenders (z. B. HCTM-Dienstplan oder Geburtstage)
/// innerhalb des sichtbaren Monats. Der Server expandiert wiederkehrende Einträge
/// und Geburtstage zu konkreten Terminen je Monat.
struct CalendarEvent: Identifiable {
    let entry: Resources_Calendar_Entries_CalendarEntry

    var id: Int64 { entry.id }

    var title: String { entry.title }

    var start: Date { entry.startTime.timestamp.date }
    var end: Date { entry.hasEndTime ? entry.endTime.timestamp.date : start }

    var isBirthday: Bool { entry.occurrence.kind == .birthday }

    var isAllDay: Bool { entry.occurrence.allDay || !entry.hasEndTime }

    /// Whether the server delivered an actual entry content to show.
    var hasContent: Bool { entry.hasContent }

    var calendarName: String {
        entry.hasCalendar ? entry.calendar.name : ""
    }

    /// Farbe aus dem Kalender-`color`-Hex; Geburtstage bekommen einen festen
    /// Ton, Abwesenheiten bleiben konsequent Orange (siehe Grid).
    var color: Color {
        if isBirthday { return Theme.Palette.info }
        if entry.hasCalendar,
           !entry.calendar.color.isEmpty,
           let parsed = Color(hex: entry.calendar.color) {
            return parsed
        }
        return Theme.Palette.accent
    }

    func covers(_ day: Date, calendar: Calendar) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        let s = calendar.startOfDay(for: start)
        let e = calendar.startOfDay(for: end)
        return dayStart >= s && dayStart <= e
    }

    /// "Ganztägig" / "14:00" / "14:00 – 16:30".
    var timeText: String {
        if isAllDay {
            return "Ganztägig"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        if entry.hasEndTime, end > start {
            return "\(f.string(from: start)) – \(f.string(from: end))"
        }
        return f.string(from: start)
    }
}

/// Kalender-Modul: kombiniert die Urlaube/Abwesenheiten der Mitarbeiter mit den
/// hinterlegten FiveNet-Kalendern (Job-Kalender wie HCTM, Geburtstage, …) in
/// einem kompakten Monatskalender mit Tages-Detail.
struct CalendarView: View {
    @Environment(AppState.self) private var appState

    init() {
        _visibleMonth = State(initialValue: CalendarView.monthStart(for: Date()))
        _selectedDay = State(initialValue: Calendar.current.startOfDay(for: Date()))
    }

    @State private var visibleMonth: Date
    @State private var selectedDay: Date
    @State private var absences: [CalendarAbsence] = []
    @State private var events: [CalendarEvent] = []
    @State private var calendarIDs: [Int64] = []
    @State private var isLoading = false
    @State private var isLoadingEntries = false
    @State private var errorMessage: String?
    @State private var selectedEvent: CalendarEvent?
    @State private var selectedColleagueID: Int32?

    /// Kalender mit Montag als Wochenstart (deutsche Woche).
    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    private let weekdaySymbols = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    private var monthFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "MMMM yyyy"
        return f
    }

    private static func monthStart(for date: Date) -> Date {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        return Calendar.current.date(from: comps) ?? date
    }

    private func absences(on day: Date) -> [CalendarAbsence] {
        absences.filter { $0.covers(day, calendar: calendar) }
    }

    private func events(on day: Date) -> [CalendarEvent] {
        events.filter { $0.covers(day, calendar: calendar) }
    }

    var body: some View {
        Group {
            List {
                if isLoading && absences.isEmpty && events.isEmpty {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonListRow()
                    }
                } else if let errorMessage, absences.isEmpty && events.isEmpty {
                    EmptyStateView(
                        "exclamationmark.triangle",
                        color: Theme.Palette.danger,
                        title: "Laden fehlgeschlagen",
                        message: errorMessage,
                        actionTitle: "Erneut versuchen"
                    ) {
                        Task { await load() }
                    }
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            monthNav
                            weekdayHeader
                            dayGrid
                            legend
                        }
                        .padding(Theme.Spacing.lg)
                        .background(
                            Theme.Palette.surface,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        )
                        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                        .cardRow()
                    } header: {
                        SectionHeader("Übersicht")
                    }

                    Section {
                        if selectedList.isEmpty {
                            SectionCard {
                                Text("Keine Abwesenheiten oder Einträge für diesen Tag.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .cardRow()
                        } else {
                            ForEach(selectedList) { item in
                                switch item {
                                case .absence(let absence):
                                    Button {
                                        selectedColleagueID = absence.colleague.userID
                                    } label: {
                                        CalendarRow(
                                            icon: "person.crop.circle.fill",
                                            color: Theme.Palette.warning,
                                            title: absence.name,
                                            subtitle: "Abwesenheit · \(absence.rangeText)",
                                            showsChevron: true
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .cardRow()
                                case .event(let event):
                                    Button {
                                        selectedEvent = event
                                    } label: {
                                        CalendarRow(
                                            icon: event.isBirthday ? "gift.fill" : "calendar",
                                            color: event.color,
                                            title: event.title,
                                            subtitle: event.timeText + (event.calendarName.isEmpty ? "" : " · \(event.calendarName)")
                                        )
                                    }
                                    .buttonStyle(.borderless)
                                    .cardRow()
                                }
                            }
                        }
                    } header: {
                        SectionHeader(dayTitle)
                    }
                }
            }
            .cardListStyle()
            .pendingAlarmBell()
            .moduleNavTitle(.calendar)
            .navConnectionDot()
            .task { await load() }
            .onChange(of: visibleMonth) {
                Task { await loadEntries() }
            }
            .sheet(item: $selectedEvent) { event in
                CalendarEventDetailSheet(event: event)
            }
        }
        .navigationDestination(item: $selectedColleagueID) { userID in
            ColleagueDetailView(userID: userID)
        }
    }

    /// Alle Markierungen des gewählten Tages, sortiert nach Abwesenheiten und
    /// Kalendereinträgen (nach Startzeit).
    private var selectedList: [CalendarSelection] {
        let a = absences(on: selectedDay).map(CalendarSelection.absence)
        let e = events(on: selectedDay)
            .sorted { $0.start < $1.start }
            .map(CalendarSelection.event)
        return a + e
    }

    private var dayTitle: String {
        Self.dayFormatter.string(from: selectedDay)
    }

    private static var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, dd. MMMM yyyy"
        return f
    }

    private var monthNav: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)

            Spacer()

            Text(monthFormatter.string(from: visibleMonth))
                .font(Theme.Typography.headline)

            Spacer()

            Button {
                visibleMonth = Self.monthStart(for: Date())
                selectedDay = Calendar.current.startOfDay(for: Date())
            } label: {
                Image(systemName: "calendar")
                    .font(.headline)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { index in
                Text(weekdaySymbols[index])
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 16)
            }
        }
    }

    private var dayGrid: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                if let cell {
                    dayCell(cell)
                } else {
                    Color.clear
                        .frame(height: 34)
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: Theme.Spacing.md) {
            Circle()
                .fill(Theme.Palette.warning)
                .frame(width: 7, height: 7)
            Text("Urlaub / Abwesenheit")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !events.isEmpty {
                Circle()
                    .fill(Theme.Palette.accent)
                    .frame(width: 7, height: 7)
                Text("Kalendereinträge")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, Theme.Spacing.xs)
    }

    /// Kompakte Tageszelle: Tag-Nummer plus bis zu drei farbige Punkte.
    private func dayCell(_ cell: CalendarDay) -> some View {
        let dots = dayDots(on: cell.date)
        let isToday = calendar.isDateInToday(cell.date)
        let isSelected = calendar.isDate(cell.date, inSameDayAs: selectedDay)
        let isOffMonth = calendar.isDate(cell.date, equalTo: visibleMonth, toGranularity: .month) == false

        return Button {
            selectedDay = calendar.startOfDay(for: cell.date)
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: cell.date))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isOffMonth ? Color.secondary : (isSelected ? Color.white : Color.primary))
                    .frame(maxWidth: .infinity)
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(index < dots.count ? dots[index] : Color.clear)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(height: 34)
            .background(
                isSelected ? AnyShapeStyle(Theme.Palette.accent) : AnyShapeStyle(Color.clear),
                in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
            )
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .stroke(Theme.Palette.accent.opacity(0.5), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Bis zu drei repräsentative Farben eines Tages: Urlaub zuerst, dann
    /// Kalendereinträge (höchstens drei, eindeutig nach Farbe).
    private func dayDots(on day: Date) -> [Color] {
        var dots: [Color] = []
        if !absences(on: day).isEmpty {
            dots.append(Theme.Palette.warning)
        }
        for event in events(on: day).sorted(by: { $0.start < $1.start }) {
            guard dots.count < 3 else { break }
            if !dots.contains(event.color) {
                dots.append(event.color)
            }
        }
        return dots
    }

    private var cells: [CalendarDay?] {
        let firstDay = visibleMonth
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstDay)?.count ?? 30
        let firstWeekDay = calendar.component(.weekday, from: firstDay)
        let leading = (firstWeekDay + 5) % 7

        var result: [CalendarDay?] = []
        result.append(contentsOf: repeatElement(nil, count: leading))
        for day in 0..<daysInMonth {
            let date = calendar.date(byAdding: .day, value: day, to: firstDay)!
            result.append(CalendarDay(date: date))
        }
        while result.count % 7 != 0 {
            result.append(nil)
        }
        return result
    }

    private func changeMonth(by delta: Int) {
        if let new = calendar.date(byAdding: .month, value: delta, to: visibleMonth) {
            visibleMonth = Self.monthStart(for: new)
        }
    }

    // MARK: - Loading

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            var collected: [Resources_Jobs_Colleagues_Colleague] = []
            var offset: Int64 = 0
            let pageSize: Int64 = 50
            while true {
                let response = try await appState.listColleagues(offset: offset, pageSize: pageSize)
                let page = response.colleagues
                collected.append(contentsOf: page)
                let total = response.pagination.totalCount
                if total > 0 && Int64(collected.count) >= total { break }
                if page.count < pageSize { break }
                offset += Int64(page.count)
                if offset > 2000 { break }  // Sicherheitsgrenze
            }

            let filtered = collected.filter { $0.props.hasAbsenceBegin && $0.props.hasAbsenceEnd }
            absences = filtered.map(CalendarAbsence.init)
                .sorted { $0.begin < $1.begin }
        } catch {
            errorMessage = error.localizedDescription
        }

        // Kalender-IDs für die Eintrags-Abfrage sammeln. Schlägt das fehl,
        // werden die Einträge trotzdem (ohne Filter) versucht.
        calendarIDs = await loadCalendarIDs()
        await loadEntries()
    }

    /// Lädt alle zugänglichen Kalender (Seite für Seite) und liefert deren IDs.
    /// Eine leere Liste bedeutet: alle Kalender einschließen.
    private func loadCalendarIDs() async -> [Int64] {
        var ids: [Int64] = []
        var offset: Int64 = 0
        while true {
            guard let response = try? await appState.listCalendars(offset: offset, pageSize: 50) else { break }
            ids.append(contentsOf: response.calendars.map { $0.id })
            let total = response.pagination.totalCount
            if total > 0 && Int64(ids.count) >= total { break }
            if response.calendars.count < 50 { break }
            offset += Int64(response.calendars.count)
            if offset > 1000 { break }
        }
        return ids
    }

    /// Lädt die Kalendereinträge des sichtbaren Monats (einschließlich
    /// Geburtstagen und wiederkehrender Termine, die der Server expandiert).
    private func loadEntries() async {
        guard !isLoadingEntries else { return }
        isLoadingEntries = true
        defer { isLoadingEntries = false }

        let comps = calendar.dateComponents([.year, .month], from: visibleMonth)
        guard let year = comps.year, let month = comps.month else { return }
        do {
            events = try await appState.listCalendarEntries(year: Int32(year), month: Int32(month), calendarIds: calendarIDs)
                .map(CalendarEvent.init)
        } catch {
            // Fehlende Kalender-Berechtigung o. Ä. darf den Urlaubs-Teil des
            // Kalenders nicht kaputt machen — Einträge bleiben dann einfach leer.
            if events.isEmpty, errorMessage == nil {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Gemeinsame Zeile für Abwesenheiten und Kalendereinträge im Tages-Detail.
private struct CalendarRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    var showsChevron = false

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(color)
                .frame(width: 5)
                .padding(.vertical, Theme.Spacing.md)

            HStack(spacing: Theme.Spacing.lg) {
                IconTile(icon, color: color, size: 34)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.leading, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.xs)

            if showsChevron {
                CardChevron()
                    .padding(.leading, Theme.Spacing.sm)
            }
        }
        .padding(Theme.Spacing.md)
        .padding(.trailing, showsChevron ? Theme.Spacing.sm : Theme.Spacing.xs)
        .background(
            Theme.Palette.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

/// Vereinheitlichtes Tag-Modell für die Detail-Liste.
enum CalendarSelection: Identifiable {
    case absence(CalendarAbsence)
    case event(CalendarEvent)

    var id: String {
        switch self {
        case .absence(let a): return "a-\(a.id)"
        case .event(let e): return "e-\(e.id)"
        }
    }
}

/// Ein Tag im Kalender-Grid.
private struct CalendarDay: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}

/// Detail-Sheet eines Kalendereintrags: Titel, Zeit/Kalender und der vom Server
/// gelieferte Inhalt (rendert via `WikiContentView`).
private struct CalendarEventDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let event: CalendarEvent

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text(event.title)
                            .font(Theme.Typography.title3)
                        Label(
                            event.timeText + (event.calendarName.isEmpty ? "" : " · \(event.calendarName)"),
                            systemImage: event.isBirthday ? "gift.fill" : "calendar"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }

                if event.hasContent {
                    Section("Inhalt") {
                        WikiContentView(content: event.entry.content)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
            }
            .navigationTitle("Eintrag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
