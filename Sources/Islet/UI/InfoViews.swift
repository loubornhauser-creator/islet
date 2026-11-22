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

    var body: some View {
        switch cal.status {
        case .fullAccess:
            if cal.events.isEmpty {
                emptyState(symbol: "calendar", title: days == 1 ? "Heute keine weiteren Termine" : "Keine Termine in den nächsten \(days) Tagen")
            } else {
                list
            }
        case .notDetermined:
            emptyState(symbol: "calendar", title: "Islet kann deine nächsten Termine zeigen",
                       button: ("Zugriff erlauben", { cal.requestAccess() }))
        default:
            emptyState(symbol: "calendar.badge.exclamationmark", title: "Kein Zugriff auf den Kalender",
                       detail: "In den Systemeinstellungen unter Datenschutz → Kalender für Islet erlauben.",
                       button: ("Einstellungen öffnen", {
                           if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") { NSWorkspace.shared.open(u) }
                       }))
        }
    }

    private struct Group: Identifiable { let id: Date; let label: String; let items: [CalEvent] }

    private var groups: [Group] {
        let cal = Calendar.current
        let now = Date()
        let byDay = Dictionary(grouping: self.cal.events) { cal.startOfDay(for: max($0.start, now)) }
        return byDay.keys.sorted().map { day in
            let label: String
            if cal.isDateInToday(day) { label = "Heute" }
            else if cal.isDateInTomorrow(day) { label = "Morgen" }
            else { label = day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Locale(identifier: "de_DE"))) }
            return Group(id: day, label: label, items: byDay[day] ?? [])
        }
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(groups) { g in
                    Text(g.label.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.6)
                        .foregroundStyle(.white.opacity(0.4)).padding(.top, 4).padding(.leading, 4)
                    ForEach(g.items) { EventRow(event: $0) }
                }
            }
        }
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
