import AppKit
import CoreGraphics

/// How many seconds one app held focus in a minute, and the last window title seen.
struct AppSlice: Codable {
    let name: String
    let bundleId: String
    let seconds: Int
    let title: String?
}

/// Samples the frontmost app once a second. The app name needs no permission; the
/// window title rides on the Screen Recording grant we already hold, so for browsers
/// it usually carries the page title ("Gmail – Inkorg") without asking for more.
final class AppUsageMonitor {
    static let shared = AppUsageMonitor()
    static let didSample = Notification.Name("AppUsageMonitorDidSample")

    private var timer: Timer?
    private var seconds: [String: Int] = [:]
    private var names: [String: String] = [:]
    private var titles: [String: String] = [:]

    private(set) var currentApp: String?
    private(set) var currentTitle: String?

    private init() {}

    var isRunning: Bool { timer != nil }

    func start() {
        guard !isRunning else { return }
        reset()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.sample()
        }
        sample()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        reset()
    }

    /// Apps used this minute, busiest first, then clears for the next minute.
    func closeMinute() -> [AppSlice] {
        defer { reset() }
        return seconds
            .sorted { $0.value > $1.value }
            .map { bundleId, secs in
                AppSlice(
                    name: names[bundleId] ?? bundleId,
                    bundleId: bundleId,
                    seconds: secs,
                    title: titles[bundleId])
            }
    }

    private func reset() {
        seconds.removeAll()
        names.removeAll()
        titles.removeAll()
    }

    private func sample() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier
        else { return }

        let name = app.localizedName ?? bundleId
        seconds[bundleId, default: 0] += 1
        names[bundleId] = name

        let title = frontWindowTitle(pid: app.processIdentifier)
        if let title, !title.isEmpty {
            titles[bundleId] = title
        }

        currentApp = name
        currentTitle = titles[bundleId]
        NotificationCenter.default.post(name: Self.didSample, object: nil)
    }

    /// Title of the app's front window, read from the window list (z-ordered front to back).
    private func frontWindowTitle(pid: pid_t) -> String? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        for window in windows {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0
            else { continue }
            return window[kCGWindowName as String] as? String
        }
        return nil
    }
}
