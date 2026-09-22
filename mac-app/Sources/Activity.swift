import CoreGraphics
import Foundation

/// One minute of a shift: which screenshots were taken and how active the user was (0–100).
struct MinuteRecord: Codable {
    let timestamp: Date
    let screenshots: [String]
    /// How many seconds the percentages are based on. The clock-in shot lands after
    /// only a couple of seconds, so 0% there means "not enough data", not "idle".
    let seconds: Int
    let keyboard: Int
    let mouse: Int
    let overall: Int
    let apps: [AppSlice]
}

/// Samples input activity once a second. Only asks the OS *when* the last event
/// happened, never what it was, so no Accessibility permission is needed.
final class ActivityMonitor {
    static let shared = ActivityMonitor()
    static let didTick = Notification.Name("ActivityMonitorDidTick")

    private let keyboardEvents: [CGEventType] = [.keyDown, .flagsChanged]
    private let mouseEvents: [CGEventType] = [
        .mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .scrollWheel,
    ]

    private var timer: Timer?
    private var minute: [(keyboard: Bool, mouse: Bool)] = []
    private var rolling: [Bool] = []

    /// Live % reflects only the last few seconds, so genuine stillness drops to 0
    /// quickly instead of lingering because the whole minute is averaged.
    private let liveWindow = 20

    private init() {}

    var isRunning: Bool { timer != nil }

    func start() {
        guard !isRunning else { return }
        minute.removeAll()
        rolling.removeAll()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        minute.removeAll()
        rolling.removeAll()
    }

    /// Activity over the last 60 seconds, for the live display.
    var livePercent: Int {
        guard !rolling.isEmpty else { return 0 }
        return rolling.filter { $0 }.count * 100 / rolling.count
    }

    /// Returns percentages for the minute so far and starts a fresh one.
    func closeMinute() -> (seconds: Int, keyboard: Int, mouse: Int, overall: Int) {
        defer { minute.removeAll() }
        let count = minute.count
        guard count > 0 else { return (0, 0, 0, 0) }
        return (
            count,
            minute.filter { $0.keyboard }.count * 100 / count,
            minute.filter { $0.mouse }.count * 100 / count,
            minute.filter { $0.keyboard || $0.mouse }.count * 100 / count
        )
    }

    private func tick() {
        let keyboard = keyboardEvents.contains { secondsSince($0) < 1 }
        let mouse = mouseEvents.contains { secondsSince($0) < 1 }
        minute.append((keyboard, mouse))
        rolling.append(keyboard || mouse)
        if rolling.count > liveWindow { rolling.removeFirst() }
        NotificationCenter.default.post(name: Self.didTick, object: nil)
    }

    private func secondsSince(_ type: CGEventType) -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
    }
}
