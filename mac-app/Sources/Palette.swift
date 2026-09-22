import AppKit

/// Colours picked from the app icon so the window and the logo read as one thing.
enum Palette {
    static let background = NSColor(srgbRed: 0.043, green: 0.059, blue: 0.106, alpha: 1)
    static let card = NSColor(srgbRed: 0.078, green: 0.102, blue: 0.169, alpha: 1)
    static let border = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.07)
    static let accent = NSColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 1)
    static let danger = NSColor(srgbRed: 0.937, green: 0.325, blue: 0.314, alpha: 1)
    static let success = NSColor(srgbRed: 0.298, green: 0.733, blue: 0.365, alpha: 1)
    static let textPrimary = NSColor(srgbRed: 0.945, green: 0.960, blue: 0.988, alpha: 1)
    static let textSecondary = NSColor(srgbRed: 0.541, green: 0.580, blue: 0.678, alpha: 1)

    static let sidebar = NSColor(srgbRed: 0.031, green: 0.043, blue: 0.078, alpha: 1)
    static let sidebarSelected = NSColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 0.20)
}

extension NSTextField {
    static func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = Palette.textPrimary,
        monospacedDigits: Bool = false
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = monospacedDigits
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }

    /// Uppercase section label with subtle letter spacing, for headings.
    static func sectionLabel(_ text: String) -> NSTextField {
        let field = label(
            text.uppercased(), size: 10, weight: .semibold, color: Palette.textSecondary)
        field.attributedStringValue = NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: Palette.textSecondary,
                .kern: 0.8,
            ])
        return field
    }
}

/// AppKit anchors an unflipped document view to the bottom of its scroll view, so
/// short lists float down the page. Flipping puts the origin at the top like a page.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A vertically scrolling column whose rows start at the top and each stretch to the
/// full content width — the layout every list page in the app wants. Row width is
/// pinned explicitly because NSStackView's `.width` alignment proved unreliable here.
final class ScrollingColumn: NSScrollView {
    private let column = NSStackView()
    private let insets: NSEdgeInsets
    private var rowWidthConstraints: [NSLayoutConstraint] = []

    init(spacing: CGFloat = 12,
         insets: NSEdgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 24, right: 20)) {
        self.insets = insets
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = true
        translatesAutoresizingMaskIntoConstraints = false

        let page = FlippedView()
        page.translatesAutoresizingMaskIntoConstraints = false
        documentView = page

        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = spacing
        column.edgeInsets = insets
        column.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(column)

        NSLayoutConstraint.activate([
            page.widthAnchor.constraint(equalTo: contentView.widthAnchor),
            column.topAnchor.constraint(equalTo: page.topAnchor),
            column.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: page.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func replaceRows(with views: [NSView]) {
        rowWidthConstraints.forEach { $0.isActive = false }
        rowWidthConstraints.removeAll()
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for view in views {
            column.addArrangedSubview(view)
            let width = view.widthAnchor.constraint(
                equalTo: contentView.widthAnchor, constant: -(insets.left + insets.right))
            width.isActive = true
            rowWidthConstraints.append(width)
        }
    }
}

extension NSView {
    /// A rounded card with a subtle 1px border, for definition without heavy fills.
    @discardableResult
    func asCard(radius: CGFloat = 12) -> NSView {
        wantsLayer = true
        layer?.backgroundColor = Palette.card.cgColor
        layer?.cornerRadius = radius
        layer?.borderWidth = 1
        layer?.borderColor = Palette.border.cgColor
        return self
    }
}
