import SwiftUI
import EventKit

private func emptyState(symbol: String, title: String, detail: String? = nil, button: (String, () -> Void)? = nil) -> some View {
    VStack(spacing: 8) {
        Image(systemName: symbol).font(.system(size: 24, weight: .light))
        Text(title).font(.system(size: 12, weight: .medium)).opacity(0.75)
        if let detail { Text(detail).font(.system(size: 10)).opacity(0.45).multilineTextAlignment(.center) }
        if let button { PillButton(title: button.0, action: button.1) }
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

// MARK: Kalender

struct CalendarView: View {
    @ObservedObject private var cal = CalendarModule.shared
    @AppStorage("calendarDays") private var days = 2
    @AppStorage("calendarReminders") private var showReminders = true

    private var hasAccess: Bool { cal.status == .fullAccess || (showReminders && cal.reminderStatus == .fullAccess) }
    private var isEmpty: Bool { cal.events.isEmpty && (!showReminders || cal.reminders.isEmpty) }

    var body: some View {
        if hasAccess {
            if isEmpty {
                emptyState(symbol: "calendar", title: days == 1 ? "Heute nichts mehr zu tun" : "Keine Termine in den nächsten \(days) Tagen")
            } else {
                list
            }
        } else if cal.status == .notDetermined {
            emptyState(symbol: "calendar", title: "Islet kann deine nächsten Termine und Erinnerungen zeigen",
                       button: ("Zugriff erlauben", { cal.requestAccess() }))
        } else {
            emptyState(symbol: "calendar.badge.exclamationmark", title: "Kein Zugriff auf den Kalender",
                       detail: "In den Systemeinstellungen unter Datenschutz → Kalender für Islet erlauben.",
                       button: ("Einstellungen öffnen", {
                           if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") { NSWorkspace.shared.open(u) }
                       }))
        }
    }

    private enum Entry: Identifiable {
        case event(CalEvent), reminder(ReminderItem)
        var id: String { switch self { case .event(let e): return "e-" + e.id; case .reminder(let r): return "r-" + r.id } }
        var date: Date { switch self { case .event(let e): return e.start; case .reminder(let r): return r.due ?? .distantFuture } }
    }

    private struct Group: Identifiable { let id: Date; let label: String; let items: [Entry]; let overdue: Bool }

    private var groups: [Group] {
        let cal = Calendar.current
        let now = Date(), today = cal.startOfDay(for: now)
        var all: [Entry] = self.cal.events.map { .event($0) }
        if showReminders { all += self.cal.reminders.map { .reminder($0) } }
        // Überfällige Erinnerungen (vor heute) bilden eine eigene Gruppe ganz oben.
        let overdue = all.filter { if case .reminder(let r) = $0, let d = r.due { return d < today }; return false }
        let rest = all.filter { e in !overdue.contains { $0.id == e.id } }
        let byDay = Dictionary(grouping: rest) { cal.startOfDay(for: max($0.date, now)) }
        var out: [Group] = []
        if !overdue.isEmpty { out.append(Group(id: .distantPast, label: "Überfällig", items: overdue.sorted { $0.date < $1.date }, overdue: true)) }
        for day in byDay.keys.sorted() {
            let label: String
            if cal.isDateInToday(day) { label = "Heute" }
            else if cal.isDateInTomorrow(day) { label = "Morgen" }
            else { label = day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Locale(identifier: "de_DE"))) }
            out.append(Group(id: day, label: label, items: (byDay[day] ?? []).sorted { $0.date < $1.date }, overdue: false))
        }
        return out
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(groups) { g in
                    Text(g.label.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.6)
                        .foregroundStyle(g.overdue ? Color.red.opacity(0.85) : .white.opacity(0.4)).padding(.top, 4).padding(.leading, 4)
                    ForEach(g.items) { entry in
                        switch entry {
                        case .event(let e): EventRow(event: e)
                        case .reminder(let r): ReminderRow(item: r, overdue: g.overdue)
                        }
                    }
                }
            }
        }
    }
}

struct ReminderRow: View {
    let item: ReminderItem
    let overdue: Bool
    @State private var hover = false
    @State private var done = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                withAnimation(.easeOut(duration: 0.2)) { done = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { CalendarModule.shared.complete(item) }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(done ? Color.green : item.color)
                    .frame(width: 22, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Als erledigt markieren")
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).strikethrough(done)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(overdue ? Color.red.opacity(0.9) : .white.opacity(0.55)).lineLimit(1)
            }
            Spacer(minLength: 6)
            if item.priority > 0 && item.priority <= 4 { Image(systemName: "exclamationmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.orange) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(.white.opacity(hover ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hover = $0 }
        .opacity(done ? 0.5 : 1)
    }

    private var subtitle: String {
        guard let due = item.due else { return item.list }
        let when = item.hasTime ? due.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE")))
                                : due.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "de_DE")))
        return "\(when) · \(item.list)"
    }
}

struct EventRow: View {
    let event: CalEvent
    @State private var hover = false
    @AppStorage("activeHex") private var activeHex = "#30D158"

    var body: some View {
        Button {
            Haptics.tap()
            if let u = URL(string: "calshow:\(event.start.timeIntervalSinceReferenceDate)") { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 10) {
                Capsule().fill(event.color).frame(width: 3, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Text(subtitle).font(.system(size: 10)).opacity(0.55).lineLimit(1)
                }
                Spacer(minLength: 6)
                trailing
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(.white.opacity(hover ? 0.14 : 0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Im Kalender öffnen")
    }

    /// „in 25 Min“ / „in 1 Std 29 Min“ (unabhängig von der Systemsprache).
    static func until(_ date: Date, from now: Date) -> String {
        let m = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        if m < 60 { return "in \(m) Min" }
        return m % 60 == 0 ? "in \(m / 60) Std" : "in \(m / 60) Std \(m % 60) Min"
    }

    private var subtitle: String {
        var s = event.allDay ? "Ganztägig" : "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
        if let l = event.location { s += " · \(l)" }
        return s
    }

    @ViewBuilder private var trailing: some View {
        let now = Date()
        if !event.allDay && event.start <= now && now < event.end {
            Text("Läuft").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: activeHex))
        } else if !event.allDay && event.start > now && event.start.timeIntervalSinceNow < 3 * 3600 {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                Text(Self.until(event.start, from: ctx.date)).font(.system(size: 10)).monospacedDigit().opacity(0.5)
            }
        }
    }
}

// MARK: Geräte

struct DevicesView: View {
    @ObservedObject private var dev = Devices.shared

    var body: some View {
        Group {
            if dev.connected.isEmpty {
                if dev.refreshing {
                    emptyState(symbol: "headphones", title: "Suche verbundene Geräte …")
                } else {
                    emptyState(symbol: "headphones", title: "Keine Bluetooth-Geräte verbunden",
                               detail: "AirPods, Maus, Tastatur und mehr erscheinen hier mit Akkustand.")
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) { ForEach(dev.connected) { DeviceRow(device: $0) } }
                }
            }
        }
        .onAppear { dev.refresh() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in dev.refresh(force: true) }
    }
}

struct DeviceRow: View {
    let device: BTDevice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.symbol).font(.system(size: 22)).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(device.kindLabel).font(.system(size: 10)).opacity(0.5)
            }
            Spacer(minLength: 8)
            if device.batteries.isEmpty {
                Text("Verbunden").font(.system(size: 10)).opacity(0.45)
            } else {
                HStack(spacing: 12) { ForEach(device.batteries) { BatteryChip(battery: $0) } }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct BatteryChip: View {
    let battery: BTBattery
    @AppStorage("activeHex") private var activeHex = "#30D158"

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().stroke(.white.opacity(0.18), lineWidth: 3)
                Circle().trim(from: 0, to: CGFloat(battery.percent) / 100)
                    .stroke(battery.percent <= 20 ? Color.red : Color(hex: activeHex), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(battery.percent)").font(.system(size: 9, weight: .bold)).monospacedDigit()
            }
            .frame(width: 30, height: 30)
            Text(battery.label).font(.system(size: 9, weight: .medium)).opacity(0.6)
        }
    }
}

// MARK: Claude-Limits

struct ClaudeView: View {
    @ObservedObject private var usage = ClaudeUsage.shared
    @AppStorage("modClaude") private var enabled = false

    var body: some View {
        Group {
            if !enabled {
                emptyState(symbol: "sparkles", title: "Claude-Limits live in der Insel",
                           detail: "Islet liest dafür die Anmeldung von Claude Code aus dem Schlüsselbund (macOS fragt einmal) und fragt api.anthropic.com ab. Nichts wird geändert oder gespeichert.",
                           button: ("Aktivieren", { enabled = true }))
            } else {
                switch usage.state {
                case .ok: content
                case .loading, .off: emptyState(symbol: "sparkles", title: "Lade Limits …")
                case .noLogin: emptyState(symbol: "person.crop.circle.badge.questionmark", title: "Claude Code ist nicht angemeldet", detail: "Melde dich einmal in Claude Code an (Befehl claude, dann /login).")
                case .expired: emptyState(symbol: "clock.badge.exclamationmark", title: "Anmeldung abgelaufen", detail: "Starte Claude Code kurz, es erneuert die Anmeldung. Danach aktualisiert sich die Anzeige.", button: ("Neu laden", { usage.refresh(force: true) }))
                case .denied: emptyState(symbol: "lock.trianglebadge.exclamationmark", title: "Schlüsselbund-Zugriff abgelehnt", detail: "Erlaube Islet den Zugriff auf „Claude Code-credentials“ und lade neu.", button: ("Neu laden", { usage.refresh(force: true) }))
                case .offline: emptyState(symbol: "wifi.slash", title: "Keine Verbindung", button: ("Neu laden", { usage.refresh(force: true) }))
                case .failed(let m): emptyState(symbol: "exclamationmark.triangle", title: "Abruf fehlgeschlagen", detail: m, button: ("Neu laden", { usage.refresh(force: true) }))
                }
            }
        }
        .onAppear { if enabled { usage.refresh() } }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in if enabled { usage.refresh() } }
    }

    private var content: some View {
        VStack(spacing: 6) {
            ForEach(usage.windows.prefix(3), id: \.title) { UsageRow(window: $0) }
            HStack {
                if !usage.plan.isEmpty { Text("Claude \(usage.plan)").font(.system(size: 10, weight: .semibold)).opacity(0.5) }
                Spacer()
                if let u = usage.updated { Text("Stand \(u.formatted(date: .omitted, time: .shortened))").font(.system(size: 10)).opacity(0.4) }
                Button { usage.refresh(force: true) } label: { Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain).opacity(0.5)
            }
            .foregroundStyle(.white)
        }
    }
}

struct UsageRow: View {
    let window: UsageWindow

    private var tint: Color {
        window.percent >= 90 ? Color(hex: "#FF453A") : (window.percent >= 70 ? Color(hex: "#FF9F0A") : Color(hex: "#30D158"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(window.title).font(.system(size: 12, weight: .semibold))
                if let r = window.resetsAt {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        Text(Self.resetText(r, from: ctx.date)).font(.system(size: 10)).opacity(0.5)
                    }
                }
                Spacer(minLength: 4)
                Text("\(Int(window.percent.rounded())) %").font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(tint)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                GeometryReader { g in Capsule().fill(tint).frame(width: max(6, g.size.width * min(1, window.percent / 100))) }
            }
            .frame(height: 6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    static func resetText(_ date: Date, from now: Date) -> String {
        let m = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        if m <= 0 { return "wird gerade zurückgesetzt" }
        if m < 60 { return "Reset in \(m) Min" }
        if m < 24 * 60 { return m % 60 == 0 ? "Reset in \(m / 60) Std" : "Reset in \(m / 60) Std \(m % 60) Min" }
        return "Reset " + date.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(Locale(identifier: "de_DE")))
    }
}
