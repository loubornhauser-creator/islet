import AppKit

/// Timer + Pomodoro mit Pause. Die Anzeige nutzt `Text(timerInterval:)`, dadurch ist kein eigener Tick nötig.
final class CountdownTimer: ObservableObject {
    static let shared = CountdownTimer()

    enum Phase { case idle, timer, work, rest }

    @Published var phase: Phase = .idle
    @Published var endDate: Date?
    @Published var startDate: Date?
    @Published var cycles = 0
    /// Gesetzt, solange der Timer pausiert ist (Restzeit in Sekunden).
    @Published var pausedRemaining: TimeInterval?
    private var fire: Timer?

    var running: Bool { phase != .idle }
    var isPaused: Bool { pausedRemaining != nil }
    var label: String {
        if isPaused { return "Pausiert" }
        switch phase {
        case .idle, .timer: return "Timer"
        case .work: return "Fokus"
        case .rest: return "Pause"
        }
    }

    func start(minutes: Double) { begin(.timer, seconds: minutes * 60) }
    func startDefault() { start(minutes: max(1, Double(Pref.int("timerDefaultMinutes")))) }

    func startPomodoro() {
        cycles = 0
        begin(.work, seconds: max(1, Pref.double("pomoWork")) * 60)
    }

    func stop() {
        fire?.invalidate(); fire = nil
        phase = .idle; endDate = nil; startDate = nil; pausedRemaining = nil
    }

    func togglePause() {
        if let rest = pausedRemaining {
            pausedRemaining = nil
            schedule(seconds: rest)
        } else if let end = endDate {
            pausedRemaining = max(1, end.timeIntervalSinceNow)
            fire?.invalidate(); fire = nil
            endDate = nil
        }
    }

    func add(minutes: Double) {
        if let rest = pausedRemaining { pausedRemaining = rest + minutes * 60; return }
        guard let end = endDate else { return }
        schedule(seconds: end.timeIntervalSinceNow + minutes * 60)
    }

    private func begin(_ p: Phase, seconds: Double) {
        phase = p
        startDate = Date()
        pausedRemaining = nil
        schedule(seconds: seconds)
    }

    private func schedule(seconds: Double) {
        fire?.invalidate()
        let end = Date().addingTimeInterval(seconds)
        endDate = end
        let t = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in self?.finished() }
        RunLoop.main.add(t, forMode: .common)
        fire = t
    }

    private func finished() {
        if Pref.bool("timerSound") { NSSound(named: "Glass")?.play() }
        IslandState.shared.peek()
        switch phase {
        case .work:
            cycles += 1
            begin(.rest, seconds: max(1, Pref.double("pomoBreak")) * 60)
        case .rest:
            begin(.work, seconds: max(1, Pref.double("pomoWork")) * 60)
        default:
            stop()
        }
    }
}
