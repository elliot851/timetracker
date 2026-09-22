import AppKit

/// The Warnings page: every inactivity event, with who it was, the evidence
/// screenshot and what they chose. Admins see everyone; a user sees only their own.
final class WarningsView: NSView {
    private let headerLabel = NSTextField.label("", size: 20, weight: .bold)
    private let subtitle = NSTextField.label("", size: 12, color: Palette.textSecondary)
    private let scroll = ScrollingColumn(spacing: 12)

    init() {
        super.init(frame: .zero)
        build()
        for name in [WarningStore.didChange, AccountStore.didChange] {
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
        let account = AccountStore.shared
        let records = account.isAdmin
            ? WarningStore.allUsers()
            : WarningStore.all(for: account.current.id).sorted { $0.startedAt > $1.startedAt }

        headerLabel.stringValue = account.isAdmin ? "Warnings" : "Your warnings"
        let paused = records.reduce(0) { $0 + $1.pausedSeconds }
        subtitle.stringValue = records.isEmpty
            ? "No warnings recorded."
            : "\(records.count) events  ·  \(Format.compact(paused)) paused time in total"
            + (account.isAdmin ? "  ·  whole team" : "")

        scroll.replaceRows(with: records.map(card))
    }

    private func card(for record: WarningRecord) -> NSView {
        // Evidence on the left, large enough to actually read.
        let thumb = NSImageView()
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 8
        thumb.layer?.masksToBounds = true
        thumb.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        thumb.image = WarningStore.screenshotURL(for: record).flatMap {
            GalleryView.thumbnail(for: $0)
        }
        thumb.translatesAutoresizingMaskIntoConstraints = false
        thumb.widthAnchor.constraint(equalToConstant: 208).isActive = true
        thumb.heightAnchor.constraint(equalToConstant: 122).isActive = true

        // Headline: who, and the big number that matters — how long was lost.
        let name = NSTextField.label(record.userName, size: 15, weight: .semibold)
        let pausedValue = NSTextField.label(
            Format.compact(record.pausedSeconds), size: 22, weight: .bold, color: Palette.danger)
        let pausedCaption = NSTextField.label("paused time", size: 10, color: Palette.textSecondary)
        let pausedBlock = NSStackView(views: [pausedValue, pausedCaption])
        pausedBlock.orientation = .vertical
        pausedBlock.alignment = .trailing
        pausedBlock.spacing = 0

        let titleRow = NSStackView(views: [name, NSView(), pausedBlock])
        titleRow.orientation = .horizontal
        titleRow.alignment = .top

        let when = NSTextField.label(
            "Idle from \(Format.time.string(from: record.startedAt))  ·  "
                + DateFormatter.day.string(from: record.startedAt),
            size: 12, color: Palette.textSecondary)

        var detail = "Activity \(record.activity)%"
        if let app = record.app { detail += "  ·  \(app)" }
        let detailLabel = NSTextField.label(detail, size: 12, color: Palette.textSecondary)

        let text = NSStackView(views: [titleRow, when, detailLabel, NSView(), outcomePill(record)])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleRow.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true

        // A colour stripe on the edge reads as "this is an incident" at a glance.
        let stripe = NSView()
        stripe.wantsLayer = true
        stripe.layer?.backgroundColor =
            (record.outcome == .resumed ? Palette.success : Palette.danger).cgColor
        stripe.layer?.cornerRadius = 2
        stripe.translatesAutoresizingMaskIntoConstraints = false
        stripe.widthAnchor.constraint(equalToConstant: 4).isActive = true

        let row = NSStackView(views: [stripe, thumb, text])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 16)
        stripe.heightAnchor.constraint(equalTo: thumb.heightAnchor).isActive = true
        row.asCard(radius: 14)
        return row
    }

    private func outcomePill(_ record: WarningRecord) -> NSView {
        let resumed = record.outcome == .resumed
        let color: NSColor = record.outcome == nil
            ? Palette.textSecondary : (resumed ? Palette.success : Palette.danger)
        let label = NSTextField.label(
            record.outcome?.label ?? "Awaiting response", size: 11, weight: .semibold, color: color)
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 10
        pill.layer?.backgroundColor = color.withAlphaComponent(0.14).cgColor
        pill.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -10),
        ])
        return pill
    }
}
