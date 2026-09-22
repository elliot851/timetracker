import AppKit

/// Admin overview of everyone: who is working right now, today's hours, activity and
/// warnings. Picking someone opens their activity — no account switching involved.
final class TeamView: NSView {
    /// Called with a user id when the admin wants to inspect that person.
    var onInspect: ((String) -> Void)?

    private let headerLabel = NSTextField.label("Team", size: 20, weight: .bold)
    private let subtitle = NSTextField.label(
        "Pick a person to review their activity", size: 12, color: Palette.textSecondary)
    private let scroll = ScrollingColumn(spacing: 10)

    init() {
        super.init(frame: .zero)
        build()
        for name in [AccountStore.didChange, ShiftStore.didChange, WarningStore.didChange] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(reload), name: name, object: nil)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let head = NSStackView(views: [headerLabel, subtitle])
        head.orientation = .vertical
        head.alignment = .leading
        head.spacing = 3
        head.translatesAutoresizingMaskIntoConstraints = false
        addSubview(head)
        addSubview(scroll)

        NSLayoutConstraint.activate([
            head.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            head.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            scroll.topAnchor.constraint(equalTo: head.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc func reload() {
        scroll.replaceRows(with: AccountStore.shared.allUsers().map(row))
    }

    private func row(for user: UserProfile) -> NSView {
        let today = Date()
        let isMe = user.id == AccountStore.shared.current.id
        let active = isMe
            ? ShiftStore.shared.active
            : ShiftStore.activeShift(for: user.id)

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = (active != nil ? Palette.success : Palette.textSecondary).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 10).isActive = true

        let nameText = isMe ? "\(user.name)  (you)" : user.name
        let name = NSTextField.label(nameText, size: 14, weight: .semibold)
        let status = NSTextField.label(
            active.map { "Clocked in since \(Format.time.string(from: $0.start))" } ?? "Clocked out",
            size: 12, color: active != nil ? Palette.success : Palette.textSecondary)

        let nameBlock = NSStackView(views: [name, status])
        nameBlock.orientation = .vertical
        nameBlock.alignment = .leading
        nameBlock.spacing = 2

        let identity = NSStackView(views: [dot, nameBlock])
        identity.orientation = .horizontal
        identity.alignment = .centerY
        identity.spacing = 10
        identity.translatesAutoresizingMaskIntoConstraints = false
        identity.widthAnchor.constraint(equalToConstant: 240).isActive = true

        let hours = isMe
            ? ShiftStore.shared.total(on: today)
            : DayData.totalWorked(on: today, user: user.id)
        let activity = DayData.averageActivity(on: today, user: user.id)
        let warnings = WarningStore.all(for: user.id)
            .filter { Calendar.current.isDateInToday($0.startedAt) }.count

        let inspect = NSButton(title: "Review", target: self, action: #selector(inspectTapped(_:)))
        inspect.bezelStyle = .rounded
        inspect.identifier = NSUserInterfaceItemIdentifier(user.id)

        let row = NSStackView(views: [
            identity,
            metric("Today", Format.compact(hours), Palette.textPrimary),
            metric("Activity", activity.map { "\($0)%" } ?? "—",
                   activity.map { ActivityColor.of($0) } ?? Palette.textSecondary),
            metric("Warnings", "\(warnings)",
                   warnings > 0 ? Palette.danger : Palette.textSecondary),
            NSView(),
            inspect,
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 20
        row.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        row.asCard()
        return row
    }

    private func metric(_ title: String, _ value: String, _ color: NSColor) -> NSView {
        let valueLabel = NSTextField.label(value, size: 16, weight: .semibold, color: color)
        let stack = NSStackView(views: [
            NSTextField.label(title, size: 10, color: Palette.textSecondary), valueLabel,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 96).isActive = true
        return stack
    }

    @objc private func inspectTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        onInspect?(id)
    }
}
