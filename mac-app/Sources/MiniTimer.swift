import AppKit

/// A small always-on-top overlay showing the live timer and a clock in/out button,
/// so the shift stays visible on screen while working in other apps.
final class MiniTimerWindowController: NSWindowController {
    private let store = ShiftStore.shared

    private let clockLabel = NSTextField.label(
        "00:00:00", size: 30, weight: .medium, monospacedDigits: true)
    private let activityLabel = NSTextField.label("", size: 11, color: Palette.textSecondary)
    private let button = NSButton()
    private var ticker: Timer?

    convenience init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 128),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "TimeTracker"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isFloatingPanel = true
        window.level = .floating                 // stays above normal windows
        window.backgroundColor = Palette.background
        window.appearance = NSAppearance(named: .darkAqua)
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 170, height: 110)

        self.init(window: window)
        buildInterface()

        for name in [ShiftStore.didChange, ActivityMonitor.didTick] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(refresh), name: name, object: nil)
        }
    }

    private func buildInterface() {
        guard let content = window?.contentView else { return }

        let stack = NSStackView(views: [clockLabel, button, activityLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        button.title = ""
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 9
        button.target = self
        button.action = #selector(toggleShift)
        button.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 150),
            button.heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    func present() {
        window?.makeKeyAndOrderFront(nil)
        refresh()
        if store.isClockedIn { startTicker() }
    }

    @objc private func refresh() {
        let clockedIn = store.isClockedIn
        clockLabel.stringValue = Format.clock(store.active?.duration ?? 0)
        clockLabel.textColor = clockedIn ? Palette.textPrimary : Palette.textSecondary

        button.attributedTitle = NSAttributedString(
            string: clockedIn ? "Clock out" : "Clock in",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            ])
        button.layer?.backgroundColor = (clockedIn ? Palette.danger : Palette.accent).cgColor

        let monitor = ActivityMonitor.shared
        activityLabel.stringValue = monitor.isRunning ? "activity \(monitor.livePercent)%" : ""
    }

    @objc private func toggleShift() {
        if store.isClockedIn {
            store.clockOut()
            Tracker.shared.stop()
            stopTicker()
        } else {
            store.clockIn()
            Tracker.shared.start()
            startTicker()
        }
        refresh()
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let active = self.store.active else { return }
            self.clockLabel.stringValue = Format.clock(active.duration)
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
