import AppKit

/// The clock-in page: live timer, clock in/out, today's stats and shifts.
/// Hosted inside the main window rather than its own window.
final class DashboardView: NSView {
    private let store = ShiftStore.shared
    private let column: CGFloat = 460

    private let statusDot = NSView()
    private let statusPillLabel = NSTextField.label("", size: 12, weight: .semibold)
    private let statusPill = NSView()

    private let clockLabel = NSTextField.label(
        "00:00:00", size: 64, weight: .medium, monospacedDigits: true)
    private let statusLabel = NSTextField.label("", size: 13, color: Palette.textSecondary)
    private let actionButton = NSButton()

    private let todayValue = NSTextField.label("0m", size: 22, weight: .bold)
    private let weekValue = NSTextField.label("0m", size: 22, weight: .bold)
    private let activityValue = NSTextField.label("—", size: 22, weight: .bold)

    private let currentAppLabel = NSTextField.label("", size: 12, color: Palette.textSecondary)
    private let currentAppPill = NSView()
    private let shiftList = NSStackView()
    private let permissionBanner = NSStackView()

    private var ticker: Timer?

    init() {
        super.init(frame: .zero)
        build()
        for name in [ShiftStore.didChange, Tracker.didCapture] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(refresh), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateActivity), name: ActivityMonitor.didTick, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateCurrentApp), name: AppUsageMonitor.didSample, object: nil)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .centerX
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false

        root.addArrangedSubview(buildPermissionBanner())
        root.addArrangedSubview(buildStatusPill())
        root.setCustomSpacing(18, after: statusPill)
        root.addArrangedSubview(clockLabel)
        root.setCustomSpacing(4, after: clockLabel)
        root.addArrangedSubview(statusLabel)
        root.setCustomSpacing(26, after: statusLabel)

        root.addArrangedSubview(buildActionButton())
        root.setCustomSpacing(28, after: actionButton)

        root.addArrangedSubview(buildStatsRow())
        root.addArrangedSubview(buildCurrentAppPill())
        root.setCustomSpacing(24, after: currentAppPill)
        root.addArrangedSubview(buildShiftSection())

        addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor, constant: 44),
            root.centerXAnchor.constraint(equalTo: centerXAnchor),
            root.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            root.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24),
        ])
    }

    private func buildStatusPill() -> NSView {
        statusPill.wantsLayer = true
        statusPill.layer?.cornerRadius = 12
        statusPill.layer?.borderWidth = 1
        statusPill.translatesAutoresizingMaskIntoConstraints = false

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        statusDot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let row = NSStackView(views: [statusDot, statusPillLabel])
        row.orientation = .horizontal
        row.spacing = 7
        row.translatesAutoresizingMaskIntoConstraints = false
        statusPill.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: statusPill.topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: statusPill.bottomAnchor, constant: -6),
            row.leadingAnchor.constraint(equalTo: statusPill.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: statusPill.trailingAnchor, constant: -12),
        ])
        return statusPill
    }

    private func buildPermissionBanner() -> NSView {
        permissionBanner.orientation = .horizontal
        permissionBanner.spacing = 10
        permissionBanner.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        permissionBanner.wantsLayer = true
        permissionBanner.layer?.backgroundColor = Palette.danger.withAlphaComponent(0.15).cgColor
        permissionBanner.layer?.cornerRadius = 10

        let text = NSTextField.label(
            "Screen Recording is not allowed", size: 12, color: Palette.danger)
        let fix = NSButton(
            title: "Open Settings", target: self, action: #selector(openPermissionSettings))
        fix.bezelStyle = .inline
        fix.controlSize = .small
        permissionBanner.addArrangedSubview(text)
        permissionBanner.addArrangedSubview(fix)
        return permissionBanner
    }

    private func buildActionButton() -> NSView {
        actionButton.target = self
        actionButton.action = #selector(toggleShift)
        actionButton.isBordered = false
        actionButton.wantsLayer = true
        actionButton.layer?.cornerRadius = 13
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            actionButton.widthAnchor.constraint(equalToConstant: column),
            actionButton.heightAnchor.constraint(equalToConstant: 52),
        ])
        return actionButton
    }

    private func buildStatsRow() -> NSView {
        let row = NSStackView(views: [
            statTile("Today", symbol: "calendar", value: todayValue),
            statTile("This week", symbol: "calendar.badge.clock", value: weekValue),
            statTile("Activity", symbol: "bolt.fill", value: activityValue),
        ])
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: column).isActive = true
        return row
    }

    private func statTile(_ title: String, symbol: String, value: NSTextField) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = Palette.textSecondary
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)

        let head = NSStackView(views: [icon, NSTextField.label(
            title, size: 11, color: Palette.textSecondary)])
        head.orientation = .horizontal
        head.spacing = 5

        let stack = NSStackView(views: [head, value])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.asCard()
        return stack
    }

    private func buildCurrentAppPill() -> NSView {
        currentAppPill.wantsLayer = true
        currentAppPill.layer?.cornerRadius = 9
        currentAppPill.layer?.backgroundColor = Palette.card.cgColor
        currentAppPill.layer?.borderWidth = 1
        currentAppPill.layer?.borderColor = Palette.border.cgColor
        currentAppPill.translatesAutoresizingMaskIntoConstraints = false

        currentAppLabel.lineBreakMode = .byTruncatingTail
        currentAppLabel.maximumNumberOfLines = 1
        currentAppLabel.translatesAutoresizingMaskIntoConstraints = false
        currentAppPill.addSubview(currentAppLabel)
        NSLayoutConstraint.activate([
            currentAppPill.widthAnchor.constraint(equalToConstant: column),
            currentAppLabel.topAnchor.constraint(equalTo: currentAppPill.topAnchor, constant: 9),
            currentAppLabel.bottomAnchor.constraint(equalTo: currentAppPill.bottomAnchor, constant: -9),
            currentAppLabel.leadingAnchor.constraint(equalTo: currentAppPill.leadingAnchor, constant: 12),
            currentAppLabel.trailingAnchor.constraint(equalTo: currentAppPill.trailingAnchor, constant: -12),
        ])
        return currentAppPill
    }

    private func buildShiftSection() -> NSView {
        shiftList.orientation = .vertical
        shiftList.alignment = .leading
        shiftList.spacing = 8
        let section = NSStackView(views: [NSTextField.sectionLabel("Today's shifts"), shiftList])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 10
        section.translatesAutoresizingMaskIntoConstraints = false
        section.widthAnchor.constraint(equalToConstant: column).isActive = true
        return section
    }

    // MARK: - State

    @objc func refresh() {
        let clockedIn = store.isClockedIn
        permissionBanner.isHidden = Capturer.hasPermission()

        updateStatusPill(clockedIn: clockedIn)

        clockLabel.stringValue = Format.clock(store.active?.duration ?? 0)
        clockLabel.textColor = clockedIn ? Palette.textPrimary : Palette.textSecondary

        statusLabel.stringValue = store.active.map {
            "Clocked in since \(Format.time.string(from: $0.start))"
        } ?? "Press to start tracking time"

        styleButton(clockedIn: clockedIn)
        todayValue.stringValue = Format.compact(store.total(on: Date()))
        weekValue.stringValue = Format.compact(store.total(inWeekOf: Date()))
        updateActivity()
        updateCurrentApp()

        if clockedIn, ticker == nil {
            startTicker()
        } else if !clockedIn {
            stopTicker()
        }
        rebuildShiftList()
    }

    private func updateStatusPill(clockedIn: Bool) {
        let color = clockedIn ? Palette.success : Palette.textSecondary
        statusDot.layer?.backgroundColor = color.cgColor
        statusPill.layer?.borderColor = color.withAlphaComponent(0.4).cgColor
        statusPill.layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
        statusPillLabel.stringValue = clockedIn ? "Tracking time" : "Not clocked in"
        statusPillLabel.textColor = color
    }

    @objc private func updateActivity() {
        let monitor = ActivityMonitor.shared
        if monitor.isRunning {
            activityValue.stringValue = "\(monitor.livePercent)%"
            activityValue.textColor = ActivityColor.of(monitor.livePercent)
        } else {
            activityValue.stringValue = "—"
            activityValue.textColor = Palette.textPrimary
        }
    }

    @objc private func updateCurrentApp() {
        let monitor = AppUsageMonitor.shared
        guard monitor.isRunning, let app = monitor.currentApp else {
            currentAppPill.isHidden = true
            return
        }
        currentAppPill.isHidden = false
        if let title = monitor.currentTitle, !title.isEmpty {
            currentAppLabel.stringValue = "Using  ·  \(app) — \(title)"
        } else {
            currentAppLabel.stringValue = "Using  ·  \(app)"
        }
    }

    private func styleButton(clockedIn: Bool) {
        actionButton.layer?.backgroundColor =
            (clockedIn ? Palette.danger : Palette.accent).cgColor
        actionButton.attributedTitle = NSAttributedString(
            string: clockedIn ? "Clock out" : "Clock in",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            ])
    }

    private func rebuildShiftList() {
        shiftList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let today = store.shifts(on: Date()).reversed()
        guard !today.isEmpty else {
            let empty = NSTextField.label(
                "No shifts today yet", size: 12, color: Palette.textSecondary)
            shiftList.addArrangedSubview(empty)
            return
        }
        for shift in today {
            shiftList.addArrangedSubview(shiftRow(shift))
        }
    }

    private func shiftRow(_ shift: Shift) -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        dot.layer?.backgroundColor = (shift.isActive ? Palette.success : Palette.textSecondary).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 7).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 7).isActive = true

        let range = shift.isActive
            ? "\(Format.time.string(from: shift.start)) — ongoing"
            : "\(Format.time.string(from: shift.start)) — \(Format.time.string(from: shift.end!))"

        let left = NSStackView(views: [dot, NSTextField.label(range, size: 12)])
        left.orientation = .horizontal
        left.spacing = 9

        let duration = NSTextField.label(
            Format.compact(shift.duration), size: 12, weight: .semibold,
            color: shift.isActive ? Palette.success : Palette.textSecondary)

        let row = NSStackView(views: [left, duration])
        row.orientation = .horizontal
        row.distribution = .equalSpacing
        row.edgeInsets = NSEdgeInsets(top: 9, left: 12, bottom: 9, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: column).isActive = true
        row.asCard(radius: 10)
        return row
    }

    // MARK: - Actions

    @objc private func toggleShift() {
        if store.isClockedIn {
            store.clockOut()
            Tracker.shared.stop()
        } else {
            store.clockIn()
            Tracker.shared.start()
        }
        refresh()
    }

    @objc private func openPermissionSettings() {
        Capturer.requestPermission()
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
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
