import EventKit
import SwiftUI

struct CalEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let location: String?
    let color: Color
}

struct CalInfo: Identifiable {
    let id: String
    let title: String
    let source: String
    let color: Color
}

/// Nächste Termine über EventKit. Der Store wird nur angelegt, solange das Modul an ist.
/// Aktualisierung ereignisgesteuert (Kalender-Änderungen, Tageswechsel, Aufwachen) plus ein
/// einziger Timer auf den nächsten relevanten Zeitpunkt, kein Polling.
final class CalendarModule: ObservableObject {
    static let shared = CalendarModule()

    @Published var events: [CalEvent] = []
    /// Termin, der in den nächsten Minuten beginnt (für die kompakte Insel).
    @Published var soon: CalEvent?
    @Published var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    private var store: EKEventStore?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var boundary: Timer?
    private var signature = ""

    var authorized: Bool { status == .fullAccess }

    // MARK: Start/Stop

    func start() {
        guard store == nil else { return }
        store = EKEventStore()
        status = EKEventStore.authorizationStatus(for: .event)
        let nc = NotificationCenter.default
        let reload: (Notification) -> Void = { [weak self] _ in self?.refresh() }
        observers.append((nc, nc.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main, using: reload)))
        observers.append((nc, nc.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: reload)))
        let ws = NSWorkspace.shared.notificationCenter
        observers.append((ws, ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: reload)))
        if status == .notDetermined { requestAccess() } else { refresh() }
    }

    func stop() {
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        boundary?.invalidate(); boundary = nil
        store = nil
        events = []; soon = nil
    }

    func requestAccess() {
        let s = store ?? EKEventStore()
        s.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.status = EKEventStore.authorizationStatus(for: .event)
                self?.refresh()
            }
        }
    }

    // MARK: Einstellungen

    static func excludedList() -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(Pref.string("calendarExcluded").utf8))) ?? []
    }

    static func setExcluded(_ ids: [String]) {
        if let d = try? JSONEncoder().encode(ids.sorted()), let s = String(data: d, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: "calendarExcluded")
        }
    }

    /// Alle Kalender für die Auswahl in den Einstellungen.
    func allCalendars() -> [CalInfo] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let s = store ?? EKEventStore()
        return s.calendars(for: .event)
            .map { CalInfo(id: $0.calendarIdentifier, title: $0.title, source: $0.source?.title ?? "", color: Color(nsColor: $0.color)) }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
    }

    /// Wird bei jeder Defaults-Änderung aufgerufen, lädt aber nur neu, wenn sich etwas Relevantes geändert hat.
    func reloadIfSettingsChanged() {
        guard store != nil else { return }
        let sig = "\(Pref.int("calendarDays"))|\(Pref.bool("calendarAllDay"))|\(Pref.int("calendarSoonMinutes"))|\(Pref.string("calendarExcluded"))"
        if sig != signature { refresh() }
    }

    // MARK: Laden

    func refresh() {
        signature = "\(Pref.int("calendarDays"))|\(Pref.bool("calendarAllDay"))|\(Pref.int("calendarSoonMinutes"))|\(Pref.string("calendarExcluded"))"
        status = EKEventStore.authorizationStatus(for: .event)
        boundary?.invalidate(); boundary = nil
        guard let store, status == .fullAccess else { events = []; soon = nil; return }

        let now = Date()
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: max(1, Pref.int("calendarDays")), to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let excluded = Set(Self.excludedList())
        let calendars = store.calendars(for: .event).filter { !excluded.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { events = []; soon = nil; return }

        let showAllDay = Pref.bool("calendarAllDay")
        let found = store.events(matching: store.predicateForEvents(withStart: now, end: end, calendars: calendars))
            .filter { $0.status != .canceled }
            .filter { e in !(e.attendees ?? []).contains { $0.isCurrentUser && $0.participantStatus == .declined } }
            .filter { showAllDay || !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        events = found.prefix(14).map {
            CalEvent(id: "\($0.eventIdentifier ?? UUID().uuidString)-\($0.startDate.timeIntervalSince1970)",
                     title: $0.title ?? "Ohne Titel", start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay,
                     location: ($0.location?.isEmpty ?? true) ? nil : $0.location,
                     color: Color(nsColor: $0.calendar.color))
        }
        updateSoon()
        scheduleBoundary()
    }

    private func updateSoon() {
        let limit = Double(max(1, Pref.int("calendarSoonMinutes"))) * 60
        let now = Date()
        soon = events.first { !$0.allDay && $0.start > now && $0.start.timeIntervalSince(now) <= limit }
    }

    /// Ein Timer auf den nächsten Zeitpunkt, an dem sich etwas ändert (Hinweis-Fenster, Start, Ende).
    private func scheduleBoundary() {
        let now = Date()
        let lead = Double(max(1, Pref.int("calendarSoonMinutes"))) * 60
        var next = now.addingTimeInterval(3600)
        for e in events where !e.allDay {
            for t in [e.start.addingTimeInterval(-lead), e.start, e.end] where t > now && t < next { next = t }
        }
        let t = Timer(fire: next.addingTimeInterval(0.5), interval: 0, repeats: false) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        boundary = t
    }
}
