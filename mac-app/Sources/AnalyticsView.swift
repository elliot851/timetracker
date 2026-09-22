import AppKit

/// The monitoring hub: headline numbers with trends, how work classifies, when it
/// happens, what apps it happens in, and how each person compares. Admins see the
/// whole team; a user sees themselves.
final class AnalyticsView: NSView {
    private var period: Analytics.Period = .today
    private var scopeUserId: String?

    private let scopeSelector = NSPopUpButton()
    private let periodSelector = NSSegmentedControl(
        labels: Analytics.Period.allCases.map(\.label),
        trackingMode: .selectOne, target: nil, action: nil)

    private let kpiRow = NSStackView()
    private let midRow = NSStackView()
    private let classBox = NSStackView()
    private let hourlyBox = NSStackView()
    private let appsBox = NSStackView()
    private let peopleBox = NSStackView()
    private let scroll = ScrollingColumn(spacing: 16)

    init() {
        super.init(frame: .zero)
        build()
        for name in [ShiftStore.didChange, WarningStore.didChange, AccountStore.didChange] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(reload), name: name, object: nil)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    private func build() {
        let title = NSTextField.label("Analytics", size: 20, weight: .bold)
        periodSelector.selectedSegment = 0
        periodSelector.target = self
        periodSelector.action = #selector(periodChanged)

        scopeSelector.target = self
        scopeSelector.action = #selector(scopeChanged)
        scopeSelector.translatesAutoresizingMaskIntoConstraints = false
        scopeSelector.widthAnchor.constraint(equalToConstant: 190).isActive = true

        let filters = NSStackView(views: [title, periodSelector, scopeSelector, NSView()])
        filters.orientation = .horizontal
        filters.alignment = .centerY
        filters.spacing = 16

        kpiRow.orientation = .horizontal
        kpiRow.distribution = .fillEqually
        kpiRow.spacing = 12

        for box in [classBox, hourlyBox, appsBox, peopleBox] {
            box.orientation = .vertical
            box.alignment = .width
            box.spacing = 12
            box.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
            box.asCard()
        }
        classBox.alignment = .centerX
        classBox.translatesAutoresizingMaskIntoConstraints = false
        classBox.widthAnchor.constraint(equalToConstant: 260).isActive = true

        midRow.orientation = .horizontal
        midRow.alignment = .top
        midRow.spacing = 16
        midRow.setViews([classBox, hourlyBox], in: .leading)

        scroll.replaceRows(with: [filters, kpiRow, midRow, appsBox, peopleBox])
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - Actions

    @objc private func periodChanged() {
        period = Analytics.Period(rawValue: periodSelector.selectedSegment) ?? .today
        reload()
    }

    @objc private func scopeChanged() {
        scopeUserId = scopeSelector.selectedItem?.representedObject as? String
        reload()
    }

    // MARK: - Render

    @objc func reload() {
        let account = AccountStore.shared
        rebuildScopeSelector()

        let users: [UserProfile]
        if account.isAdmin {
            users = scopeUserId.flatMap { id in account.allUsers().filter { $0.id == id } }
                ?? account.allUsers()
        } else {
            users = [account.current]
        }
        let dates = Analytics.dates(for: period)

        renderKPIs(users: users, dates: dates)
        renderClassification(users: users, dates: dates)
        renderHourly(users: users, dates: dates)
        renderApps(users: users, dates: dates)
        renderPeople(users: account.isAdmin ? account.allUsers() : [account.current], dates: dates)
    }

    private func rebuildScopeSelector() {
        let account = AccountStore.shared
        scopeSelector.isHidden = !account.isAdmin
        guard account.isAdmin else { return }
        let previous = scopeUserId
        scopeSelector.removeAllItems()
        scopeSelector.addItem(withTitle: "Whole team")
        scopeSelector.lastItem?.representedObject = nil
        for user in account.allUsers() {
            scopeSelector.addItem(withTitle: user.name)
            scopeSelector.lastItem?.representedObject = user.id
        }
        if let previous, let name = account.allUsers().first(where: { $0.id == previous })?.name {
            scopeSelector.selectItem(withTitle: name)
        }
    }

    // MARK: KPI cards

    private func renderKPIs(users: [UserProfile], dates: [Date]) {
        kpiRow.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let worked = Analytics.totalWorked(users, dates: dates)
        let activity = Analytics.averageActivity(users, dates: dates)
        let warnings = Analytics.warningCount(users, dates: dates)
        let active = Analytics.workingNow(users).count
        let daily = Analytics.daily(users, dates: dates)

        kpiRow.addArrangedSubview(kpi(
            "Time worked", Format.compact(worked), Palette.textPrimary,
            spark: daily.map(\.minutes), sparkColor: Palette.accent))
        kpiRow.addArrangedSubview(kpi(
            "Avg. activity", activity.map { "\($0)%" } ?? "—",
            activity.map { ActivityColor.of($0) } ?? Palette.textSecondary,
            spark: daily.map { $0.activity ?? 0 },
            sparkColor: activity.map { ActivityColor.of($0) } ?? Palette.textSecondary))
        kpiRow.addArrangedSubview(kpi(
            "Warnings", "\(warnings)", warnings > 0 ? Palette.danger : Palette.textPrimary))
        kpiRow.addArrangedSubview(kpi(
            "Working now", "\(active) of \(users.count)",
            active > 0 ? Palette.success : Palette.textSecondary))
    }

    private func kpi(
        _ title: String, _ value: String, _ color: NSColor,
        spark: [Int]? = nil, sparkColor: NSColor = Palette.accent
    ) -> NSView {
        let head = NSTextField.label(title.uppercased(), size: 10, weight: .semibold,
                                     color: Palette.textSecondary)
        let big = NSTextField.label(value, size: 26, weight: .bold, color: color)
        let stack = NSStackView(views: [head, big])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4

        if let spark, spark.count > 1 {
            let line = SparklineView()
            line.values = spark
            line.color = sparkColor
            line.translatesAutoresizingMaskIntoConstraints = false
            line.heightAnchor.constraint(equalToConstant: 34).isActive = true
            stack.addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.asCard()
        return stack
    }

    // MARK: Classification ring

    private func renderClassification(users: [UserProfile], dates: [Date]) {
        classBox.arrangedSubviews.forEach { $0.removeFromSuperview() }
        classBox.addArrangedSubview(leftLabel(NSTextField.sectionLabel("Work quality")))

        let c = Analytics.classification(users, dates: dates)
        let ring = RingView()
        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.widthAnchor.constraint(equalToConstant: 150).isActive = true
        ring.heightAnchor.constraint(equalToConstant: 150).isActive = true
        ring.segments = [
            .init(value: c.core, color: Palette.success),
            .init(value: c.light, color: NSColor(srgbRed: 0.953, green: 0.663, blue: 0.216, alpha: 1)),
            .init(value: c.idle, color: Palette.danger),
        ]
        let corePct = c.total > 0 ? c.core * 100 / c.total : 0
        ring.centerText = "\(corePct)%"
        ring.centerCaption = "focused"
        classBox.addArrangedSubview(ring)

        classBox.addArrangedSubview(legend("Focused", pct(c.core, c.total), Palette.success))
        classBox.addArrangedSubview(legend(
            "Light activity", pct(c.light, c.total),
            NSColor(srgbRed: 0.953, green: 0.663, blue: 0.216, alpha: 1)))
        classBox.addArrangedSubview(legend("Idle", pct(c.idle, c.total), Palette.danger))
    }

    private func legend(_ title: String, _ value: String, _ color: NSColor) -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = color.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let name = NSTextField.label(title, size: 12)
        let valueLabel = NSTextField.label(value, size: 12, weight: .semibold,
                                           color: Palette.textSecondary)
        let row = NSStackView(views: [dot, name, NSView(), valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 228).isActive = true
        return row
    }

    private func pct(_ part: Int, _ total: Int) -> String {
        total > 0 ? "\(part * 100 / total)%" : "—"
    }

    // MARK: Hourly

    private func renderHourly(users: [UserProfile], dates: [Date]) {
        hourlyBox.arrangedSubviews.forEach { $0.removeFromSuperview() }
        hourlyBox.addArrangedSubview(leftLabel(NSTextField.sectionLabel("When work happens")))

        let buckets = Analytics.hourly(users, dates: dates)
        guard !buckets.isEmpty else {
            hourlyBox.addArrangedSubview(leftLabel(emptyLabel("No tracked time in this period.")))
            return
        }
        hourlyBox.addArrangedSubview(leftLabel(NSTextField.label(
            "Tracked minutes per hour. Colour shows average activity.",
            size: 11, color: Palette.textSecondary)))

        let maxMinutes = max(buckets.map(\.minutes).max() ?? 1, 1)
        let columns = NSStackView()
        columns.orientation = .horizontal
        columns.alignment = .bottom
        columns.spacing = 6
        for bucket in buckets { columns.addArrangedSubview(hourColumn(bucket, maxMinutes: maxMinutes)) }
        hourlyBox.addArrangedSubview(leftLabel(columns))
    }

    private func hourColumn(_ bucket: Analytics.HourBucket, maxMinutes: Int) -> NSView {
        let height = max(4, CGFloat(bucket.minutes) / CGFloat(maxMinutes) * 120)
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor =
            (bucket.activity.map { ActivityColor.of($0) } ?? Palette.textSecondary).cgColor
        bar.layer?.cornerRadius = 4
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: height).isActive = true
        bar.widthAnchor.constraint(equalToConstant: 22).isActive = true
        bar.toolTip = "\(bucket.hour):00 — \(bucket.minutes) min"
            + (bucket.activity.map { ", \($0)% activity" } ?? "")
        let label = NSTextField.label(String(format: "%02d", bucket.hour), size: 9,
                                      color: Palette.textSecondary)
        let column = NSStackView(views: [bar, label])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 5
        return column
    }

    // MARK: Apps

    private func renderApps(users: [UserProfile], dates: [Date]) {
        appsBox.arrangedSubviews.forEach { $0.removeFromSuperview() }
        appsBox.addArrangedSubview(leftLabel(NSTextField.sectionLabel("Most used apps")))
        let apps = Analytics.topApps(users, dates: dates)
        guard let top = apps.first else {
            appsBox.addArrangedSubview(leftLabel(emptyLabel("No app usage recorded.")))
            return
        }
        for app in apps { appsBox.addArrangedSubview(appRow(app, max: top.seconds)) }
    }

    private func appRow(_ app: Analytics.AppTotal, max maxSeconds: Int) -> NSView {
        let name = NSTextField.label(app.name, size: 12)
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        name.widthAnchor.constraint(equalToConstant: 190).isActive = true

        let track = NSView()
        track.wantsLayer = true
        track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        track.layer?.cornerRadius = 5
        track.translatesAutoresizingMaskIntoConstraints = false
        track.heightAnchor.constraint(equalToConstant: 10).isActive = true
        track.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let fill = NSView()
        fill.wantsLayer = true
        fill.layer?.backgroundColor = Palette.accent.cgColor
        fill.layer?.cornerRadius = 5
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)
        let ratio = max(0.02, CGFloat(app.seconds) / CGFloat(maxSeconds))
        NSLayoutConstraint.activate([
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: ratio),
        ])

        let value = NSTextField.label(Format.compact(TimeInterval(app.seconds)), size: 12,
                                      weight: .medium, color: Palette.textSecondary)
        value.translatesAutoresizingMaskIntoConstraints = false
        value.widthAnchor.constraint(equalToConstant: 70).isActive = true

        let row = NSStackView(views: [name, track, value])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    // MARK: People

    private func renderPeople(users: [UserProfile], dates: [Date]) {
        peopleBox.arrangedSubviews.forEach { $0.removeFromSuperview() }
        peopleBox.addArrangedSubview(leftLabel(NSTextField.sectionLabel("Per person")))
        for stats in Analytics.perPerson(users, dates: dates) {
            peopleBox.addArrangedSubview(personRow(stats))
        }
    }

    private func personRow(_ stats: Analytics.PersonStats) -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor =
            (stats.isWorkingNow ? Palette.success : Palette.textSecondary).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 10).isActive = true

        let name = NSTextField.label(stats.user.name, size: 13, weight: .medium)
        name.translatesAutoresizingMaskIntoConstraints = false
        name.widthAnchor.constraint(equalToConstant: 180).isActive = true

        let identity = NSStackView(views: [dot, name])
        identity.orientation = .horizontal
        identity.spacing = 10

        let spark = SparklineView()
        spark.values = Analytics.sparkline(for: stats.user.id)
        spark.color = stats.activity.map { ActivityColor.of($0) } ?? Palette.textSecondary
        spark.translatesAutoresizingMaskIntoConstraints = false
        spark.widthAnchor.constraint(equalToConstant: 90).isActive = true
        spark.heightAnchor.constraint(equalToConstant: 28).isActive = true

        // Activity badge, like Hubstaff's coloured percentage chip.
        let badge = activityBadge(stats.activity)

        let row = NSStackView(views: [
            identity,
            NSView(),
            cell(Format.compact(stats.worked), 90),
            spark,
            badge,
            cell(stats.warnings > 0 ? "\(stats.warnings) ⚠" : "0", 70,
                 stats.warnings > 0 ? Palette.danger : Palette.textSecondary),
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        return row
    }

    private func activityBadge(_ activity: Int?) -> NSView {
        let color = activity.map { ActivityColor.of($0) } ?? Palette.textSecondary
        let label = NSTextField.label(activity.map { "\($0)%" } ?? "—", size: 12,
                                      weight: .semibold, color: color)
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 9
        pill.layer?.backgroundColor = color.withAlphaComponent(0.16).cgColor
        pill.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        NSLayoutConstraint.activate([
            pill.widthAnchor.constraint(equalToConstant: 54),
            label.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -4),
        ])
        return pill
    }

    private func cell(_ text: String, _ width: CGFloat, _ color: NSColor = Palette.textPrimary) -> NSView {
        let field = NSTextField.label(text, size: 13, color: color)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        return field
    }

    /// Wrap a view so it stays left-aligned inside a `.width`-stretched box row.
    private func leftLabel(_ view: NSView) -> NSView {
        let row = NSStackView(views: [view, NSView()])
        row.orientation = .horizontal
        row.spacing = 0
        return row
    }

    private func emptyLabel(_ text: String) -> NSTextField {
        NSTextField.label(text, size: 12, color: Palette.textSecondary)
    }
}
