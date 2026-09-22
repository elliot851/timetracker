import Foundation

/// Drives tracking while a shift is open: activity and app usage are closed out
/// every minute (analytics, warnings and the timeline all count minutes), while a
/// screenshot is only taken every `screenshotEvery` minutes.
final class Tracker {
    static let shared = Tracker()

    private let capturer = Capturer()
    private var timer: Timer?
    private var ticks = 0

    /// Length of one activity record. Override for testing:
    /// `defaults write com.artush.timetracker captureInterval 10`
    private var interval: TimeInterval {
        let custom = UserDefaults.standard.double(forKey: "captureInterval")
        return custom > 0 ? custom : 60
    }

    /// Take a screenshot every N ticks (default 10 minutes). Override:
    /// `defaults write com.artush.timetracker screenshotEveryMinutes 1`
    private var screenshotEvery: Int {
        let custom = UserDefaults.standard.integer(forKey: "screenshotEveryMinutes")
        return custom > 0 ? custom : 10
    }

    static let didCapture = Notification.Name("TrackerDidCapture")

    private init() {}

    var isRunning: Bool { timer != nil }

    func start() {
        guard !isRunning else { return }
        ActivityMonitor.shared.start()
        AppUsageMonitor.shared.start()
        ticks = 0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // The first minute of a shift always gets a screenshot.
        captureNow(withScreenshot: true)
    }

    /// One minute has passed: close the activity record, with a screenshot every Nth time.
    private func tick() {
        ticks += 1
        captureNow(withScreenshot: ticks % screenshotEvery == 0)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        ActivityMonitor.shared.stop()
        AppUsageMonitor.shared.stop()
    }

    /// Closes the current minute; `withScreenshot` also captures the active display.
    /// Called with no arguments (menu "Take screenshot now") it always captures.
    func captureNow(withScreenshot: Bool = true) {
        Task { @MainActor in
            var saved: [URL] = []
            if withScreenshot {
                Log.write("Taking screenshot (permission: \(Capturer.hasPermission()))")
                do {
                    saved = try await capturer.captureActiveDisplay()
                    if saved.isEmpty {
                        Log.write("No displays found to capture")
                    }
                    for url in saved {
                        Log.write("Saved \(url.path)")
                    }
                } catch {
                    Log.write("Screenshot failed: \(error)")
                }
            }

            // Activity is only meaningful inside a shift; a manual shot while clocked
            // out just saves the image. A failed capture still keeps its minute.
            if ActivityMonitor.shared.isRunning {
                let activity = ActivityMonitor.shared.closeMinute()
                let apps = AppUsageMonitor.shared.closeMinute()
                let now = Date()
                let record = MinuteRecord(
                    timestamp: now,
                    screenshots: saved.map { $0.lastPathComponent },
                    seconds: activity.seconds,
                    keyboard: activity.keyboard,
                    mouse: activity.mouse,
                    overall: activity.overall,
                    apps: apps)
                Storage.appendMinute(record)
                let top = apps.first.map { "\($0.name) \($0.seconds)s" } ?? "no app"
                Log.write("Activity: \(activity.overall)% over \(activity.seconds)s · top: \(top)")

                // Mirror to the server for the website.
                Sync.pushMinute(record)
                Sync.uploadScreenshots(saved, on: now)
            }

            NotificationCenter.default.post(name: Self.didCapture, object: nil)
        }
    }
}
