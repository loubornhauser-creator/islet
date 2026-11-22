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

struct ReminderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let due: Date?
    /// Hat die Fälligkeit eine Uhrzeit (sonst nur ein Tag)?
    let hasTime: Bool
    let list: String
    let color: Color
    let priority: Int
}

struct CalInfo: Identifiable {
    let id: String
    let title: String
    let source: String
    let color: Color
    let isReminderList: Bool
}

/// Nächste Termine und Erinnerungen über EventKit. Der Store wird nur angelegt, solange das Modul an ist.
/// Aktualisierung ereignisgesteuert (Änderungen, Tageswechsel, Aufwachen) plus ein einziger Timer auf den nächsten
/// relevanten Zeitpunkt, kein Polling. Islet liest Termine nur. Bei Erinnerungen kann es einzelne abhaken.
final class CalendarModule: ObservableObject {
    static let shared = CalendarModule()

    @Published var events: [CalEvent] = []
    @Published var reminders: [ReminderItem] = []
    /// Termin, der in den nächsten Minuten beginnt (für die kompakte Insel).
    @Published var soon: CalEvent?
    @Published var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published var reminderStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)

    private var store: EKEventStore?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var boundary: Timer?
    private var signature = ""

    var authorized: Bool { status == .fullAccess }
    var remindersAuthorized: Bool { reminderStatus == .fullAccess }

    // MARK: Start/Stop

    func start() {
        guard store == nil else { return }
        store = EKEventStore()
        status = EKEventStore.authorizationStatus(for: .event)
        reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
        let nc = NotificationCenter.default
        let reload: (Notification) -> Void = { [weak self] _ in self?.refresh() }
        observers.append((nc, nc.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main, using: reload)))
        observers.append((nc, nc.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: reload)))
        let ws = NSWorkspace.shared.notificationCenter
        observers.append((ws, ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: reload)))
        if status == .notDetermined { requestAccess() } else { refresh() }
        if Pref.bool("calendarReminders"), reminderStatus == .notDetermined { requestRemindersAccess() }
    }

    func stop() {
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        boundary?.invalidate(); boundary = nil
        store = nil
        events = []; reminders = []; soon = nil
    }

    func requestAccess() {
        let s = store ?? EKEventStore()
        s.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.status = EKEventStore.authorizationStatus(for: .event)
                self?.refresh()
            }
        }
        if Pref.bool("calendarReminders") { requestRemindersAccess() }
    }

    func requestRemindersAccess() {
        let s = store ?? EKEventStore()
        s.requestFullAccessToReminders { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
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

    /// Alle Kalender und Erinnerungslisten für die Auswahl in den Einstellungen.
    func allCalendars() -> [CalInfo] {
        let s = store ?? EKEventStore()
        var out: [CalInfo] = []
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            out += s.calendars(for: .event).map { CalInfo(id: $0.calendarIdentifier, title: $0.title, source: $0.source?.title ?? "", color: Color(nsColor: $0.color), isReminderList: false) }
        }
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            out += s.calendars(for: .reminder).map { CalInfo(id: $0.calendarIdentifier, title: $0.title, source: "Erinnerungen", color: Color(nsColor: $0.color), isReminderList: true) }
        }
        return out.sorted { ($0.isReminderList ? 1 : 0, $0.source, $0.title) < ($1.isReminderList ? 1 : 0, $1.source, $1.title) }
    }

    private static var settingsSignature: String {
        "\(Pref.int("calendarDays"))|\(Pref.bool("calendarAllDay"))|\(Pref.int("calendarSoonMinutes"))|\(Pref.string("calendarExcluded"))|\(Pref.bool("calendarReminders"))"
    }

    /// Wird bei jeder Defaults-Änderung aufgerufen, lädt aber nur neu, wenn sich etwas Relevantes geändert hat.
    func reloadIfSettingsChanged() {
        guard store != nil else { return }
        if Self.settingsSignature != signature { refresh() }
    }

    // MARK: Laden

    func refresh() {
        signature = Self.settingsSignature
        status = EKEventStore.authorizationStatus(for: .event)
        reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
        boundary?.invalidate(); boundary = nil
        guard let store else { return }

        let now = Date()
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: max(1, Pref.int("calendarDays")), to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let excluded = Set(Self.excludedList())

        if status == .fullAccess {
            let calendars = store.calendars(for: .event).filter { !excluded.contains($0.calendarIdentifier) }
            let showAllDay = Pref.bool("calendarAllDay")
            let found = calendars.isEmpty ? [] : store.events(matching: store.predicateForEvents(withStart: now, end: end, calendars: calendars))
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
        } else {
            events = []
        }

        if reminderStatus == .fullAccess, Pref.bool("calendarReminders") {
            loadReminders(store: store, until: end, excluded: excluded)
        } else {
            reminders = []
        }
        updateSoon()
        scheduleBoundary()
    }

    /// Offene Erinnerungen: überfällige plus alle, die im Zeitraum fällig sind.
    private func loadReminders(store: EKEventStore, until end: Date, excluded: Set<String>) {
        let lists = store.calendars(for: .reminder).filter { !excluded.contains($0.calendarIdentifier) }
        guard !lists.isEmpty else { reminders = []; return }
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: lists)
        store.fetchReminders(matching: pred) { [weak self] found in
            let items = (found ?? []).compactMap { r -> ReminderItem? in
                guard let comps = r.dueDateComponents, let due = Calendar.current.date(from: comps) else { return nil }
                return ReminderItem(id: r.calendarItemIdentifier, title: r.title ?? "Ohne Titel", due: due,
                                    hasTime: comps.hour != nil, list: r.calendar.title,
                                    color: Color(nsColor: r.calendar.color), priority: r.priority)
            }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            DispatchQueue.main.async { self?.reminders = Array(items.prefix(20)) }
        }
    }

    /// Erinnerung abhaken (die einzige Änderung, die Islet an deinen Daten vornimmt, und nur auf deinen Klick).
    func complete(_ item: ReminderItem) {
        guard let store, let r = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        r.isCompleted = true
        try? store.save(r, commit: true)
        reminders.removeAll { $0.id == item.id }
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
