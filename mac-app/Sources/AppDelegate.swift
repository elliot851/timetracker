import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var windowController: MainWindowController?
    private var miniController: MiniTimerWindowController?
    private var loginController: LoginWindowController?
    private var lastCurrentUserId = ""

    private let store = ShiftStore.shared
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let shiftItem = NSMenuItem(
        title: "Clock in", action: #selector(toggleShift), keyEquivalent: "s")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMainMenu()
        buildMenu()

        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh), name: ShiftStore.didChange, object: nil)
        lastCurrentUserId = AccountStore.shared.current.id
        NotificationCenter.default.addObserver(
            self, selector: #selector(accountChanged), name: AccountStore.didChange, object: nil)

        Log.write("Starting from \(Bundle.main.bundlePath). Screen Recording allowed: \(Capturer.hasPermission())")
        if !Capturer.hasPermission() {
            let granted = Capturer.requestPermission()
            Log.write("Requested permission, response: \(granted)")
        }

        _ = InactivityWarning.shared
        Notifier.requestAuthorization()

        if Session.isLoggedIn {
            enterApp()
        } else {
            showLogin()
        }
    }

    /// Adopt the logged-in identity, resume any shift, and show the main window.
    private func enterApp() {
        if let user = Session.user {
            AccountStore.shared.adoptRemoteUser(
                id: user.id, name: user.name, role: Role(rawValue: user.role) ?? .user)
            lastCurrentUserId = user.id
        }
        // Surviving a crash or force-quit mid-shift means capture should pick back up.
        if store.isClockedIn { Tracker.shared.start() }
        refresh()
        loginController?.close()
        loginController = nil
        showWindow()
    }

    private func showLogin() {
        windowController?.close()
        windowController = nil
        if loginController == nil {
            loginController = LoginWindowController()
            loginController?.onLoggedIn = { [weak self] in self?.enterApp() }
        }
        loginController?.present()
    }

    /// A Dock app needs a real menu bar, otherwise Cmd+Q and Cmd+W do nothing.
    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "TimeTracker")
        appMenu.addItem(
            withTitle: "About TimeTracker",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide TimeTracker",
            action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit TimeTracker",
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(
            withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    /// Permission is usually granted while the app sits in the background, so re-read
    /// it on the way back in rather than leaving a stale banner on screen.
    func applicationDidBecomeActive(_ notification: Notification) {
        refresh()
        NotificationCenter.default.post(name: ShiftStore.didChange, object: nil)
    }

    /// Closing the window must not end the shift — tracking lives in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        Session.isLoggedIn ? showWindow() : showLogin()
        return true
    }

    private func buildMenu() {
        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        shiftItem.target = self
        menu.addItem(shiftItem)

        let open = NSMenuItem(
            title: "Open TimeTracker", action: #selector(showWindow), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        let gallery = NSMenuItem(
            title: "Show activity & screenshots", action: #selector(showGallery), keyEquivalent: "a")
        gallery.target = self
        menu.addItem(gallery)

        let mini = NSMenuItem(
            title: "Open overlay timer", action: #selector(showMini), keyEquivalent: "m")
        mini.target = self
        menu.addItem(mini)

        menu.addItem(.separator())

        let shotNow = NSMenuItem(
            title: "Take screenshot now", action: #selector(captureNow), keyEquivalent: "t")
        shotNow.target = self
        menu.addItem(shotNow)

        let folder = NSMenuItem(
            title: "Open screenshots folder", action: #selector(openFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)

        menu.addItem(.separator())

        let logoutItem = NSMenuItem(
            title: "Log out", action: #selector(logout), keyEquivalent: "")
        logoutItem.target = self
        menu.addItem(logoutItem)

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    @objc private func refresh() {
        let clockedIn = store.isClockedIn

        statusItem.button?.image = NSImage(
            systemSymbolName: clockedIn ? "record.circle" : "clock",
            accessibilityDescription: "TimeTracker")

        if !Capturer.hasPermission() {
            statusLine.title = "Permission missing"
        } else if clockedIn {
            statusLine.title = "Clocked in · \(Format.compact(store.total(on: Date()))) today"
        } else {
            statusLine.title = "Clocked out · \(Format.compact(store.total(on: Date()))) today"
        }

        shiftItem.title = clockedIn ? "Clock out" : "Clock in"
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

    @objc private func showWindow() {
        if windowController == nil {
            windowController = MainWindowController()
        }
        windowController?.present()
    }

    @objc func showGallery() {
        if windowController == nil {
            windowController = MainWindowController()
        }
        windowController?.showActivity()
    }

    /// When the logged-in user changes (dev switcher), stop recording for the old
    /// user and load the new user's shifts.
    @objc private func accountChanged() {
        let newId = AccountStore.shared.current.id
        guard newId != lastCurrentUserId else { return }
        lastCurrentUserId = newId
        Tracker.shared.stop()
        ShiftStore.shared.reloadForCurrentUser()
        refresh()
    }

    func logoutFromUI() { logout() }

    @objc private func logout() {
        if store.isClockedIn {
            store.clockOut()
            Tracker.shared.stop()
        }
        Task { await APIClient.logout() }
        Session.clear()
        showLogin()
    }

    @objc func showMini() {
        if miniController == nil {
            miniController = MiniTimerWindowController()
        }
        miniController?.present()
    }

    @objc private func captureNow() {
        Tracker.shared.captureNow()
    }

    @objc private func openFolder() {
        let folder = Storage.screenshotsDir(user: Storage.recordingUserId)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
