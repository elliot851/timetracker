import AppKit
import CoreGraphics

/// When activity flatlines during a shift the timer is paused at the moment input
/// stopped, a warning is recorded with an evidence screenshot, and the user must
/// choose: get back to work, or clock out. The paused stretch is never counted.
final class InactivityWarning {
    static let shared = InactivityWarning()

    /// Seconds of no input before the warning fires.
    /// Override: `defaults write com.artush.timetracker inactivityThreshold 30`
    private var threshold: TimeInterval {
        let custom = UserDefaults.standard.double(forKey: "inactivityThreshold")
        return custom > 0 ? custom : 60
    }

    private var showing = false

    private let inputEvents: [CGEventType] = [
        .keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown,
        .leftMouseDragged, .scrollWheel,
    ]

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(tick), name: ActivityMonitor.didTick, object: nil)
    }

    @objc private func tick() {
        guard !showing, ShiftStore.shared.isClockedIn else { return }
        let idle = idleSeconds()
        guard idle >= threshold else { return }
        trigger(idleSince: Date().addingTimeInterval(-idle))
    }

    private func idleSeconds() -> TimeInterval {
        inputEvents
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }

    private func trigger(idleSince: Date) {
        showing = true

        let account = AccountStore.shared.current
        let active = ShiftStore.shared.active
        // Never blame time before the shift even began.
        let since = max(idleSince, active?.start ?? idleSince)

        // Pause first: end the shift where input stopped, so the idle stretch is
        // excluded whether or not the person ever answers.
        ShiftStore.shared.clockOut(at: since)
        Tracker.shared.stop()
        Log.write("Idle: timer paused at \(Format.time.string(from: since))")

        Task { @MainActor in
            let shot = try? await Capturer().captureActiveDisplay().first
            let relative = shot.map { "\($0.deletingLastPathComponent().lastPathComponent)/\($0.lastPathComponent)" }
            if let shot { Sync.uploadScreenshots([shot], on: Date()) }

            var record = WarningRecord(
                id: UUID().uuidString,
                userId: account.id,
                userName: account.name,
                startedAt: since,
                resolvedAt: nil,
                outcome: nil,
                screenshot: relative,
                activity: 0,
                app: AppUsageMonitor.shared.currentApp)
            WarningStore.append(record)

            let resumed = self.askUser(since: since)
            record.resolvedAt = Date()
            record.outcome = resumed ? .resumed : .clockedOut
            WarningStore.update(record)

            if resumed {
                ShiftStore.shared.clockIn()
                Tracker.shared.start()
                Log.write("Idle: resumed work")
            } else {
                Log.write("Idle: clocked out")
            }
            self.showing = false
        }
    }

    /// Returns true when the user chose to get back to work.
    private func askUser(since: Date) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "You have been idle"
        alert.informativeText = """
            No activity since \(Format.time.string(from: since)).

            The timer is paused and this time is NOT counted as worked. \
            A warning has been recorded and is visible to your admin.

            Get back to work to restart the timer, or clock out.
            """
        alert.addButton(withTitle: "Back to work")
        alert.addButton(withTitle: "Clock out")

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
