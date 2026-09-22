import AppKit

/// Auth window: log in, create account, verify the emailed code, and reset password.
final class LoginWindowController: NSWindowController, NSTextFieldDelegate {
    var onLoggedIn: (() -> Void)?

    private enum Mode { case login, register, verify, reset, resetConfirm }
    private var mode: Mode = .login
    private var pendingEmail = ""

    private let titleLabel = NSTextField.label("Log in", size: 24, weight: .bold)
    private let infoLabel = NSTextField.label("", size: 12, color: Palette.textSecondary)
    private let emailField = NSTextField()
    private let passwordBox = NSView()
    private let passwordField = NSSecureTextField()
    private let passwordPlain = NSTextField()
    private let eyeButton = NSButton()
    private var passwordVisible = false
    private let codeInput = CodeInputView()
    private let strengthLabel = NSTextField.label("", size: 11, color: Palette.textSecondary)
    private let submitButton = NSButton()
    private let switchButton = NSButton()
    private let forgotButton = NSButton()
    private let resendButton = NSButton()
    private let errorLabel = NSTextField.label("", size: 12, color: Palette.danger)
    private let spinner = NSProgressIndicator()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 540),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "TimeTracker"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Palette.background
        window.appearance = NSAppearance(named: .darkAqua)
        window.isMovableByWindowBackground = true
        window.center()
        self.init(window: window)
        buildInterface()
    }

    private func buildInterface() {
        guard let content = window?.contentView else { return }

        let logo = NSImageView()
        logo.image = NSApp.applicationIconImage
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.widthAnchor.constraint(equalToConstant: 56).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 56).isActive = true

        configureField(emailField, placeholder: "Email")
        emailField.contentType = .username
        buildPasswordBox()
        codeInput.translatesAutoresizingMaskIntoConstraints = false
        codeInput.onComplete = { [weak self] in self?.submit() }

        submitButton.isBordered = false
        submitButton.wantsLayer = true
        submitButton.layer?.cornerRadius = 11
        submitButton.layer?.backgroundColor = Palette.accent.cgColor
        submitButton.target = self
        submitButton.action = #selector(submit)
        submitButton.translatesAutoresizingMaskIntoConstraints = false
        submitButton.heightAnchor.constraint(equalToConstant: 46).isActive = true

        for b in [switchButton, forgotButton, resendButton] {
            b.isBordered = false
            b.bezelStyle = .inline
            b.contentTintColor = Palette.textSecondary
            b.target = self
        }
        switchButton.action = #selector(toggleMode)
        forgotButton.action = #selector(startReset)
        forgotButton.title = "Forgot your password?"
        resendButton.action = #selector(resend)
        resendButton.title = "Send a new code"

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isHidden = true
        errorLabel.isHidden = true
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 3
        infoLabel.isHidden = true
        infoLabel.alignment = .center
        infoLabel.lineBreakMode = .byWordWrapping
        infoLabel.maximumNumberOfLines = 2

        let stack = NSStackView(views: [
            logo, titleLabel, infoLabel, emailField, passwordBox, codeInput, strengthLabel,
            errorLabel, submitButton, spinner, resendButton, forgotButton, switchButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(18, after: logo)
        stack.setCustomSpacing(20, after: titleLabel)
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 300),
            infoLabel.widthAnchor.constraint(equalToConstant: 300),
            emailField.widthAnchor.constraint(equalToConstant: 300),
            passwordBox.widthAnchor.constraint(equalToConstant: 300),
            codeInput.widthAnchor.constraint(equalToConstant: 300),
            submitButton.widthAnchor.constraint(equalToConstant: 300),
        ])
        applyMode()
    }

    private func configureField(_ field: NSTextField, placeholder: String) {
        field.placeholderString = placeholder
        field.font = NSFont.systemFont(ofSize: 14)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 40).isActive = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.delegate = self
    }

    private func buildPasswordBox() {
        passwordBox.translatesAutoresizingMaskIntoConstraints = false
        passwordBox.heightAnchor.constraint(equalToConstant: 40).isActive = true
        for field in [passwordField, passwordPlain] {
            field.placeholderString = "Password"
            field.font = NSFont.systemFont(ofSize: 14)
            field.bezelStyle = .roundedBezel
            field.focusRingType = .none
            field.delegate = self
            field.target = self
            field.action = #selector(submit)
            field.translatesAutoresizingMaskIntoConstraints = false
            passwordBox.addSubview(field)
            NSLayoutConstraint.activate([
                field.topAnchor.constraint(equalTo: passwordBox.topAnchor),
                field.bottomAnchor.constraint(equalTo: passwordBox.bottomAnchor),
                field.leadingAnchor.constraint(equalTo: passwordBox.leadingAnchor),
                field.trailingAnchor.constraint(equalTo: passwordBox.trailingAnchor),
            ])
        }
        passwordPlain.isHidden = true
        eyeButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Show")
        eyeButton.isBordered = false
        eyeButton.contentTintColor = Palette.textSecondary
        eyeButton.target = self
        eyeButton.action = #selector(toggleReveal)
        eyeButton.translatesAutoresizingMaskIntoConstraints = false
        passwordBox.addSubview(eyeButton)
        NSLayoutConstraint.activate([
            eyeButton.trailingAnchor.constraint(equalTo: passwordBox.trailingAnchor, constant: -10),
            eyeButton.centerYAnchor.constraint(equalTo: passwordBox.centerYAnchor),
            eyeButton.widthAnchor.constraint(equalToConstant: 24),
        ])
    }

    private var passwordValue: String {
        passwordVisible ? passwordPlain.stringValue : passwordField.stringValue
    }

    @objc private func toggleReveal() {
        passwordVisible.toggle()
        if passwordVisible { passwordPlain.stringValue = passwordField.stringValue }
        else { passwordField.stringValue = passwordPlain.stringValue }
        passwordField.isHidden = passwordVisible
        passwordPlain.isHidden = !passwordVisible
        eyeButton.image = NSImage(
            systemSymbolName: passwordVisible ? "eye.slash" : "eye", accessibilityDescription: "Show")
    }

    func controlTextDidChange(_ obj: Notification) {
        if mode == .register || mode == .resetConfirm { updateStrength() }
    }

    private func updateStrength() {
        let (_, text, color) = Self.strength(of: passwordValue)
        strengthLabel.stringValue = text
        strengthLabel.textColor = color
        strengthLabel.isHidden = passwordValue.isEmpty
    }

    static func strength(of password: String) -> (ok: Bool, text: String, color: NSColor) {
        let hasLetter = password.contains { $0.isLetter }
        let hasDigit = password.contains { $0.isNumber }
        let hasSymbol = password.contains { !$0.isLetter && !$0.isNumber }
        if password.count < 8 { return (false, "Weak · at least 8 characters", Palette.danger) }
        if !hasLetter || !hasDigit { return (false, "Weak · mix letters and numbers", Palette.danger) }
        if password.count >= 12 && hasSymbol { return (true, "Strong password", Palette.success) }
        return (true, "OK password", NSColor(srgbRed: 0.953, green: 0.663, blue: 0.216, alpha: 1))
    }

    // MARK: - Mode

    private func applyMode() {
        errorLabel.isHidden = true
        let titles: [Mode: String] = [
            .login: "Log in", .register: "Create account", .verify: "Verify your email",
            .reset: "Reset password", .resetConfirm: "New password",
        ]
        titleLabel.stringValue = titles[mode] ?? ""

        let showEmail = mode == .login || mode == .register || mode == .reset
        let showPassword = mode == .login || mode == .register || mode == .resetConfirm
        let showCode = mode == .verify || mode == .resetConfirm
        let showStrength = mode == .register || mode == .resetConfirm

        emailField.isHidden = !showEmail
        passwordBox.isHidden = !showPassword
        codeInput.isHidden = !showCode
        strengthLabel.isHidden = !showStrength || passwordValue.isEmpty
        forgotButton.isHidden = mode != .login
        resendButton.isHidden = mode != .verify

        switch mode {
        case .login: setButton("Log in"); switchButton.title = "No account? Create one"
        case .register: setButton("Create account"); switchButton.title = "Already have an account? Log in"
        case .verify: setButton("Verify"); switchButton.title = "Back to login"
        case .reset: setButton("Send code"); switchButton.title = "Back to login"
        case .resetConfirm: setButton("Reset password"); switchButton.title = "Back to login"
        }

        if mode == .verify {
            infoLabel.stringValue = "We sent a code to \(pendingEmail). Check your spam folder too."
            infoLabel.isHidden = false
        } else if mode == .resetConfirm {
            infoLabel.stringValue = "Enter the code we emailed to \(pendingEmail) and a new password."
            infoLabel.isHidden = false
        } else {
            infoLabel.isHidden = true
        }
        passwordField.placeholderString = mode == .resetConfirm ? "New password" : "Password"
        passwordPlain.placeholderString = passwordField.placeholderString
    }

    private func setButton(_ text: String) {
        submitButton.attributedTitle = NSAttributedString(
            string: text, attributes: [.foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold)])
    }

    @objc private func toggleMode() {
        mode = (mode == .login) ? .register : .login
        applyMode()
    }

    @objc private func startReset() {
        mode = .reset
        applyMode()
    }

    @objc private func resend() {
        Task { @MainActor in
            try? await APIClient.resendCode(email: pendingEmail)
            showInfo("New code sent.")
        }
    }

    // MARK: - Submit

    @objc private func submit() {
        let email = emailField.stringValue.trimmingCharacters(in: .whitespaces)
        let password = passwordValue
        let code = codeInput.code.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .login, .register, .reset:
            guard email.contains("@") else { return showError("Enter a valid email address.") }
        default: break
        }
        if mode == .register || mode == .resetConfirm {
            let (ok, text, _) = Self.strength(of: password)
            if !ok { return showError(text) }
        }
        if mode == .verify || mode == .resetConfirm, code.count < 6 {
            return showError("Enter the 6-digit code.")
        }

        setLoading(true)
        Task { @MainActor in
            do {
                switch mode {
                case .login:
                    _ = try await APIClient.login(email: email, password: password)
                    finish()
                case .register:
                    let r = try await APIClient.register(email: email, password: password)
                    setLoading(false)
                    if r.pending { pendingEmail = email; mode = .verify; codeInput.clear(); applyMode(); codeInput.focusFirst() }
                    else { finish() }
                case .verify:
                    _ = try await APIClient.verifyCode(email: pendingEmail, code: code)
                    finish()
                case .reset:
                    try await APIClient.requestReset(email: email)
                    pendingEmail = email; setLoading(false)
                    mode = .resetConfirm; codeInput.clear(); applyMode(); codeInput.focusFirst()
                case .resetConfirm:
                    _ = try await APIClient.resetPassword(email: pendingEmail, code: code, password: password)
                    finish()
                }
            } catch {
                setLoading(false)
                showError(error.localizedDescription)
            }
        }
    }

    private func finish() { setLoading(false); onLoggedIn?() }

    private func setLoading(_ loading: Bool) {
        spinner.isHidden = !loading
        loading ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
        submitButton.isEnabled = !loading
        [emailField, passwordField, passwordPlain].forEach { $0.isEnabled = !loading }
    }

    private func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.textColor = Palette.danger
        errorLabel.isHidden = false
    }

    private func showInfo(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.textColor = Palette.success
        errorLabel.isHidden = false
    }

    func present() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
