import AppKit

/// The whole app in one window: a dark sidebar, a context-sensitive top bar, and a
/// content area.
///
/// Two ideas are kept strictly apart, because conflating them is what made the app
/// confusing: **my account** (who this machine records for — owns the timer) and
/// **viewing** (whose data I am looking at). Viewing never touches the timer.
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private enum Page: Int { case dashboard, activity, analytics, warnings, team }

    private let dashboard = DashboardView()
    private let gallery = GalleryView()
    private let analytics = AnalyticsView()
    private let warnings = WarningsView()
    private let team = TeamView()
    private let contentContainer = NSView()

    private var navButtons: [NSButton] = []
    private var teamButton: NSButton?
    private var selected: Page = .dashboard

    // Top bar
    private let dateNav = NSStackView()
    private let dateLabel = NSTextField.label("", size: 14, weight: .semibold)
    private let todayButton = NSButton(title: "Today", target: nil, action: nil)
    private let viewingStack = NSStackView()
    private let userSelector = NSPopUpButton()
    private var selectedDate = Calendar.current.startOfDay(for: Date())

    // "You are inspecting X" strip
    private let viewingBanner = NSStackView()
    private let viewingBannerLabel = NSTextField.label("", size: 12, weight: .medium)

    // Sidebar profile
    private let profileName = NSTextField.label("", size: 13, weight: .medium)
    private let profileRole = NSTextField.label("", size: 11, color: Palette.textSecondary)
    private let warningBadge = NSTextField.label("", size: 10, weight: .bold, color: .white)
    private let warningBadgeBubble = NSView()

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        f.locale = Locale(identifier: "en_GB")
        return f
    }()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "TimeTracker"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Palette.background
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 960, height: 620)
        window.center()
        self.init(window: window)
        window.delegate = self
        build()

        team.onInspect = { [weak self] id in self?.inspect(userId: id) }

        for name in [AccountStore.didChange, WarningStore.didChange] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(stateChanged), name: name, object: nil)
        }
        applyAccount()
        select(.dashboard)
    }

    // MARK: - Layout

    private func build() {
        guard let content = window?.contentView else { return }

        let sidebar = buildSidebar()
        content.addSubview(sidebar)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        for page in [dashboard, gallery, analytics, warnings, team] as [NSView] {
            page.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(page)
            NSLayoutConstraint.activate([
                page.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                page.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                page.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            ])
        }

        // Stacking these vertically lets the banner collapse when hidden.
        let topBar = buildTopBar()
        let banner = buildViewingBanner()
        let right = NSStackView(views: [topBar, banner, contentContainer])
        right.orientation = .vertical
        right.spacing = 0
        right.distribution = .fill
        right.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(right)

        // Without these the stack sizes each row to its content and leaves the rest
        // of the window empty, which squeezes the gallery into a narrow column.
        for row in [topBar, banner, contentContainer] {
            row.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
        }
        contentContainer.setContentHuggingPriority(.defaultLow, for: .vertical)

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 230),

            right.topAnchor.constraint(equalTo: content.topAnchor),
            right.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            right.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            right.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    // MARK: - Sidebar

    private func buildSidebar() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Palette.sidebar.cgColor
        bar.translatesAutoresizingMaskIntoConstraints = false

        let logo = NSImageView()
        logo.image = NSApp.applicationIconImage
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.widthAnchor.constraint(equalToConstant: 28).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let brand = NSStackView(views: [logo, NSTextField.label(
            "TimeTracker", size: 16, weight: .bold)])
        brand.orientation = .horizontal
        brand.spacing = 10
        brand.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(brand)

        let dash = navButton("Timer", symbol: "clock.fill", page: .dashboard)
        let activity = navButton("Activity", symbol: "photo.on.rectangle", page: .activity)
        let analys = navButton("Analytics", symbol: "chart.bar.xaxis", page: .analytics)
        let warn = navButton("Warnings", symbol: "exclamationmark.triangle.fill", page: .warnings)
        attachBadge(to: warn)
        let teamNav = navButton("Team", symbol: "person.2.fill", page: .team)
        teamButton = teamNav
        navButtons = [dash, activity, analys, warn, teamNav]

        let nav = NSStackView(views: [dash, activity, analys, warn, teamNav])
        nav.orientation = .vertical
        nav.alignment = .leading
        nav.spacing = 4
        nav.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(nav)

        let profile = buildProfile()
        bar.addSubview(profile)

        NSLayoutConstraint.activate([
            brand.topAnchor.constraint(equalTo: bar.topAnchor, constant: 48),
            brand.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 20),

            nav.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 28),
            nav.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            nav.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),

            profile.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            profile.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            profile.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -20),
        ])
        return bar
    }

    private func navButton(_ title: String, symbol: String, page: Page) -> NSButton {
        let button = NSButton(title: "  " + title, target: self, action: #selector(navTapped(_:)))
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.contentTintColor = .white
        button.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        button.tag = page.rawValue
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 38).isActive = true
        button.widthAnchor.constraint(equalToConstant: 206).isActive = true
        return button
    }

    private func attachBadge(to button: NSButton) {
        warningBadgeBubble.wantsLayer = true
        warningBadgeBubble.layer?.backgroundColor = Palette.danger.cgColor
        warningBadgeBubble.layer?.cornerRadius = 9
        warningBadgeBubble.isHidden = true
        warningBadgeBubble.translatesAutoresizingMaskIntoConstraints = false
        warningBadge.translatesAutoresizingMaskIntoConstraints = false
        warningBadgeBubble.addSubview(warningBadge)
        button.addSubview(warningBadgeBubble)

        NSLayoutConstraint.activate([
            warningBadgeBubble.trailingAnchor.constraint(
                equalTo: button.trailingAnchor, constant: -10),
            warningBadgeBubble.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            warningBadgeBubble.heightAnchor.constraint(equalToConstant: 18),
            warningBadgeBubble.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
            warningBadge.centerXAnchor.constraint(equalTo: warningBadgeBubble.centerXAnchor),
            warningBadge.centerYAnchor.constraint(equalTo: warningBadgeBubble.centerYAnchor),
            warningBadgeBubble.leadingAnchor.constraint(
                lessThanOrEqualTo: warningBadge.leadingAnchor, constant: -6),
        ])
    }

    private func buildProfile() -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = Palette.accent.cgColor
        dot.layer?.cornerRadius = 15
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 30).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let text = NSStackView(views: [profileName, profileRole])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 0

        let more = NSImageView()
        more.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
        more.contentTintColor = Palette.textSecondary

        let row = NSStackView(views: [dot, text, NSView(), more])
        row.orientation = .horizontal
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addGestureRecognizer(
            NSClickGestureRecognizer(target: self, action: #selector(openProfileMenu(_:))))
        return row
    }

    // MARK: - Top bar

    private func buildTopBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false

        let prev = iconButton("chevron.left", action: #selector(previousDay))
        let next = iconButton("chevron.right", action: #selector(nextDay))
        todayButton.target = self
        todayButton.action = #selector(goToday)
        todayButton.bezelStyle = .rounded

        dateNav.setViews([prev, next, dateLabel, todayButton], in: .leading)
        dateNav.orientation = .horizontal
        dateNav.spacing = 10
        dateNav.alignment = .centerY
        dateNav.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(dateNav)

        userSelector.target = self
        userSelector.action = #selector(userSelected)
        userSelector.translatesAutoresizingMaskIntoConstraints = false
        userSelector.widthAnchor.constraint(equalToConstant: 180).isActive = true

        viewingStack.setViews([
            NSTextField.label("VIEWING", size: 9, weight: .semibold, color: Palette.textSecondary),
            userSelector,
        ], in: .leading)
        viewingStack.orientation = .vertical
        viewingStack.alignment = .leading
        viewingStack.spacing = 2
        viewingStack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(viewingStack)

        let overlay = NSButton(title: "  Overlay", target: self, action: #selector(openOverlay))
        overlay.image = NSImage(systemSymbolName: "pip.enter", accessibilityDescription: nil)
        overlay.imagePosition = .imageLeading
        overlay.bezelStyle = .rounded
        overlay.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(overlay)

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = Palette.border.cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(separator)

        NSLayoutConstraint.activate([
            bar.heightAnchor.constraint(equalToConstant: 66),
            dateNav.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 20),
            dateNav.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            overlay.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -20),
            overlay.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            viewingStack.trailingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: -20),
            viewingStack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
        updateDateLabel()
        return bar
    }

    private func buildViewingBanner() -> NSView {
        viewingBanner.orientation = .horizontal
        viewingBanner.spacing = 12
        viewingBanner.alignment = .centerY
        viewingBanner.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        viewingBanner.wantsLayer = true
        viewingBanner.layer?.backgroundColor = Palette.accent.withAlphaComponent(0.16).cgColor
        viewingBanner.isHidden = true
        viewingBanner.translatesAutoresizingMaskIntoConstraints = false

        let back = NSButton(title: "Back to me", target: self, action: #selector(backToMe))
        back.bezelStyle = .rounded
        viewingBanner.setViews([viewingBannerLabel, back], in: .leading)
        return viewingBanner
    }

    private func iconButton(_ symbol: String, action: Selector) -> NSButton {
        let button = NSButton(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!,
            target: self, action: action)
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        return button
    }

    // MARK: - State

    @objc private func stateChanged() {
        applyAccount()
        refreshSelectedPage()
    }

    /// Reflect who I am, what I may see, and who I am currently inspecting.
    private func applyAccount() {
        let account = AccountStore.shared
        profileName.stringValue = account.current.name
        profileRole.stringValue = account.current.role.label

        teamButton?.isHidden = !account.isAdmin
        if !account.isAdmin, selected == .team { select(.dashboard) }

        userSelector.removeAllItems()
        for user in account.allUsers() {
            userSelector.addItem(withTitle: user.name)
            userSelector.lastItem?.representedObject = user.id
        }
        if let title = account.allUsers().first(where: { $0.id == account.viewing.id })?.name {
            userSelector.selectItem(withTitle: title)
        }

        viewingBannerLabel.stringValue =
            "You are viewing \(account.viewing.name)'s data — your own timer is not affected"

        updateChrome()
        updateWarningBadge()
    }

    /// The top bar only shows what the current page can actually use. Viewing someone
    /// else is only meaningful on Activity, so the selector and banner live there.
    private func updateChrome() {
        let account = AccountStore.shared
        let isActivity = selected == .activity
        let inspectingOther = account.viewing.id != account.current.id

        dateNav.isHidden = !isActivity
        viewingStack.isHidden = !(isActivity && account.isAdmin)
        viewingBanner.isHidden = !(isActivity && inspectingOther)
    }

    private func updateWarningBadge() {
        let count = WarningInbox.unreadCount()
        warningBadgeBubble.isHidden = count == 0
        warningBadge.stringValue = count > 99 ? "99+" : "\(count)"
    }

    private func refreshSelectedPage() {
        switch selected {
        case .dashboard: dashboard.refresh()
        case .activity: gallery.reload(for: selectedDate)
        case .analytics: analytics.reload()
        case .warnings: warnings.reload(); WarningInbox.markAllRead(); updateWarningBadge()
        case .team: team.reload()
        }
    }

    // MARK: - Navigation

    @objc private func navTapped(_ sender: NSButton) {
        select(Page(rawValue: sender.tag) ?? .dashboard)
    }

    private func select(_ page: Page) {
        selected = page
        dashboard.isHidden = page != .dashboard
        gallery.isHidden = page != .activity
        analytics.isHidden = page != .analytics
        warnings.isHidden = page != .warnings
        team.isHidden = page != .team

        for button in navButtons {
            let isOn = button.tag == page.rawValue
            button.layer?.backgroundColor =
                (isOn ? Palette.sidebarSelected : NSColor.clear).cgColor
        }
        updateChrome()
        refreshSelectedPage()
    }

    /// Inspect someone from the Team page: switch what is shown, never who is logged in.
    private func inspect(userId: String) {
        AccountStore.shared.setViewing(userId)
        select(.activity)
    }

    @objc private func backToMe() {
        AccountStore.shared.setViewing(AccountStore.shared.current.id)
    }

    @objc private func userSelected() {
        guard let id = userSelector.selectedItem?.representedObject as? String else { return }
        AccountStore.shared.setViewing(id)
    }

    @objc private func openOverlay() {
        (NSApp.delegate as? AppDelegate)?.showMini()
    }

    // MARK: - Day navigation

    @objc private func previousDay() { shiftDay(by: -1) }
    @objc private func nextDay() { shiftDay(by: 1) }

    @objc private func goToday() {
        selectedDate = Calendar.current.startOfDay(for: Date())
        updateDateLabel()
        if selected == .activity { gallery.reload(for: selectedDate) }
    }

    private func shiftDay(by days: Int) {
        guard let newDate = Calendar.current.date(
            byAdding: .day, value: days, to: selectedDate), newDate <= Date() else { return }
        selectedDate = newDate
        updateDateLabel()
        if selected == .activity { gallery.reload(for: selectedDate) }
    }

    private func updateDateLabel() {
        let isToday = Calendar.current.isDateInToday(selectedDate)
        dateLabel.stringValue = dayFormatter.string(from: selectedDate).capitalized
        todayButton.isEnabled = !isToday
    }

    // MARK: - Account switcher (stands in for login)

    @objc private func openProfileMenu(_ sender: NSGestureRecognizer) {
        let account = AccountStore.shared
        let menu = NSMenu()

        let header = NSMenuItem(title: "My role", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for role in [Role.admin, Role.user] {
            let item = NSMenuItem(
                title: role.label, action: #selector(pickRole(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = role.rawValue
            item.state = account.current.role == role ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let switchHeader = NSMenuItem(
            title: "Log in as (clocks you out)", action: nil, keyEquivalent: "")
        switchHeader.isEnabled = false
        menu.addItem(switchHeader)
        for user in account.allUsers() {
            let item = NSMenuItem(
                title: "\(user.name) (\(user.role.label))",
                action: #selector(pickUser(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = user.id
            item.state = account.current.id == user.id ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let add = NSMenuItem(
            title: "Add test user…", action: #selector(addTestUser), keyEquivalent: "")
        add.target = self
        menu.addItem(add)

        menu.addItem(.separator())
        let logout = NSMenuItem(title: "Log out", action: #selector(logoutTapped), keyEquivalent: "")
        logout.target = self
        menu.addItem(logout)

        if let view = sender.view {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height), in: view)
        }
    }

    @objc private func logoutTapped() {
        (NSApp.delegate as? AppDelegate)?.logoutFromUI()
    }

    @objc private func pickRole(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let role = Role(rawValue: raw)
        else { return }
        AccountStore.shared.setCurrentRole(role)
    }

    @objc private func pickUser(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        // Changing who the machine records for must never leave a shift running.
        if ShiftStore.shared.isClockedIn {
            ShiftStore.shared.clockOut()
            Tracker.shared.stop()
        }
        AccountStore.shared.switchCurrent(to: id)
    }

    @objc private func addTestUser() {
        let alert = NSAlert()
        alert.messageText = "New test user"
        alert.informativeText = "Name of the user:"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { AccountStore.shared.createUser(name: name, role: .user) }
        }
    }

    // MARK: - External

    func present() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshSelectedPage()
    }

    func showActivity() {
        select(.activity)
        present()
    }
}
