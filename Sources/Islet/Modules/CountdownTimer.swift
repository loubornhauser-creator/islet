import AppKit

/// Timer + Pomodoro. Die Anzeige nutzt `Text(timerInterval:)`, dadurch ist kein eigener Tick nötig.
final class CountdownTimer: ObservableObject {
    static let shared = CountdownTimer()

    enum Phase { case idle, timer, work, rest }

    @Published var phase: Phase = .idle
    @Published var endDate: Date?
    @Published var startDate: Date?
    @Published var cycles = 0
    private var fire: Timer?

    var running: Bool { phase != .idle }
    var label: String {
        switch phase {
        case .idle: return "Timer"
        case .timer: return "Timer"
        case .work: return "Fokus"
        case .rest: return "Pause"
        }
    }

    func start(minutes: Double) { begin(.timer, seconds: minutes * 60) }

    func startPomodoro() {
        cycles = 0
        begin(.work, seconds: max(1, Pref.double("pomoWork")) * 60)
    }

    func stop() {
        fire?.invalidate(); fire = nil
        phase = .idle; endDate = nil; startDate = nil
    }

    private func begin(_ p: Phase, seconds: Double) {
        fire?.invalidate()
        phase = p
        let now = Date()
        startDate = now
        endDate = now.addingTimeInterval(seconds)
        let t = Timer(fire: endDate!, interval: 0, repeats: false) { [weak self] _ in self?.finished() }
        RunLoop.main.add(t, forMode: .common)
        fire = t
    }

    private func finished() {
        NSSound(named: "Glass")?.play()
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
