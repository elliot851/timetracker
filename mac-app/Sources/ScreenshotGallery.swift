import AppKit

/// One browsable frame: a single screenshot plus the minute it belongs to.
struct ViewerFrame {
    let url: URL
    let minute: GalleryMinute
    let displayIndex: Int
    let displayCount: Int
}

/// The card's root view. Handling mouseDown here fires before the collection view's
/// selection machinery, so a click always registers.
final class CardView: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// A card: the screenshot, its time, how many images that minute holds, and an
/// activity bar coloured by how busy the minute was.
final class ShotItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ShotItem")
    var onClick: (() -> Void)?

    private let thumb = NSImageView()
    private let timeLabel = NSTextField.label("", size: 12, weight: .medium)
    private let countLabel = NSTextField.label("", size: 11, color: Palette.textSecondary)
    private let percentLabel = NSTextField.label("", size: 11, color: Palette.textSecondary)
    private let barFill = NSView()
    private var fillWidth: NSLayoutConstraint!

    private let barWidth: CGFloat = 188
    private let dim = NSView()
    private let magnifier = NSImageView()
    private var trackingArea: NSTrackingArea?

    override func loadView() {
        let card = CardView()
        card.onClick = { [weak self] in self?.onClick?() }
        view = card
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.backgroundColor = Palette.card.cgColor
        view.layer?.masksToBounds = true

        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        thumb.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(thumb)

        let footer = NSStackView(views: [timeLabel, countLabel])
        footer.orientation = .horizontal
        footer.distribution = .equalSpacing
        footer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footer)

        let track = NSView()
        track.wantsLayer = true
        track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        track.layer?.cornerRadius = 3
        track.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(track)

        barFill.wantsLayer = true
        barFill.layer?.cornerRadius = 3
        barFill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(barFill)

        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(percentLabel)

        fillWidth = barFill.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            thumb.topAnchor.constraint(equalTo: view.topAnchor),
            thumb.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            thumb.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            thumb.heightAnchor.constraint(equalToConstant: 118),

            footer.topAnchor.constraint(equalTo: thumb.bottomAnchor, constant: 8),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),

            track.topAnchor.constraint(equalTo: footer.bottomAnchor, constant: 8),
            track.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            track.widthAnchor.constraint(equalToConstant: barWidth),
            track.heightAnchor.constraint(equalToConstant: 6),

            barFill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            barFill.topAnchor.constraint(equalTo: track.topAnchor),
            barFill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fillWidth,

            percentLabel.topAnchor.constraint(equalTo: track.bottomAnchor, constant: 6),
            percentLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
        ])

        buildHoverLayer()
    }

    /// A dim wash + magnifier that appears on hover, hinting the card opens.
    private func buildHoverLayer() {
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        dim.isHidden = true
        dim.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dim)

        magnifier.image = NSImage(
            systemSymbolName: "magnifyingglass.circle.fill", accessibilityDescription: "Enlarge")
        magnifier.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .regular)
        magnifier.contentTintColor = .white
        magnifier.isHidden = true
        magnifier.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(magnifier)

        NSLayoutConstraint.activate([
            dim.topAnchor.constraint(equalTo: thumb.topAnchor),
            dim.leadingAnchor.constraint(equalTo: thumb.leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: thumb.trailingAnchor),
            dim.bottomAnchor.constraint(equalTo: thumb.bottomAnchor),
            magnifier.centerXAnchor.constraint(equalTo: thumb.centerXAnchor),
            magnifier.centerYAnchor.constraint(equalTo: thumb.centerYAnchor),
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if let existing = trackingArea { view.removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        view.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        dim.isHidden = false
        magnifier.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        dim.isHidden = true
        magnifier.isHidden = true
    }

    func configure(with minute: GalleryMinute) {
        thumb.image = minute.thumbURL.flatMap { GalleryView.thumbnail(for: $0) }
        timeLabel.stringValue = Format.time.string(from: minute.date)
        countLabel.stringValue = minute.shotCount > 1 ? "x\(minute.shotCount)" : ""

        let color = ActivityColor.of(minute.activity)
        barFill.layer?.backgroundColor = color.cgColor
        fillWidth.constant = barWidth * CGFloat(minute.activity) / 100
        percentLabel.stringValue = "\(minute.activity)% activity"
        view.toolTip = minute.app
    }
}

/// Section header: the clock hour and how many minutes were worked in it.
final class HourHeader: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("HourHeader")

    private let title = NSTextField.label("", size: 13, weight: .semibold)
    private let worked = NSTextField.label("", size: 12, color: Palette.textSecondary)

    override init(frame: NSRect) {
        super.init(frame: frame)
        let stack = NSStackView(views: [title, worked])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ group: HourGroup) {
        let end = group.start.addingTimeInterval(3600)
        title.stringValue = "\(Format.time.string(from: group.start)) – \(Format.time.string(from: end))"
        worked.stringValue = "time worked: \(Format.compact(TimeInterval(group.workedMinutes * 60)))"
    }
}

/// The activity page: an hour-grouped grid of screenshots with a Google Drive-style
/// lightbox that swaps in place. An embeddable view inside the main window.
final class GalleryView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {

    private var groups: [HourGroup] = []
    private var frames: [ViewerFrame] = []
    private var frameStart: [[Int]] = []
    private var index = 0
    private var currentDate = Date()

    private let collectionView = NSCollectionView()
    private let headerLabel = NSTextField.label("", size: 17, weight: .bold)
    private let gridScroll = NSScrollView()

    // Detail mode (a Google Drive-style lightbox overlaid on the dimmed grid)
    private let detailContainer = NSView()
    private let detailImage = NSImageView()
    private let detailTime = NSTextField.label("", size: 15, weight: .semibold, color: .white)
    private let detailActivity = NSTextField.label("", size: 14, weight: .semibold)
    private let detailBreakdown = NSTextField.label("", size: 12, color: NSColor.white.withAlphaComponent(0.7))
    private let detailCounter = NSTextField.label("", size: 13, color: NSColor.white.withAlphaComponent(0.7))
    private var detailImageW: NSLayoutConstraint!
    private var detailImageH: NSLayoutConstraint!

    private var keyMonitor: Any?

    init() {
        super.init(frame: .zero)
        buildGrid()
        buildDetail()
        for name in [Tracker.didCapture, ShiftStore.didChange] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(reloadCurrent), name: name, object: nil)
        }
        installKeyMonitor()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        if inDetail { layoutDetailImage() }
    }

    private func buildGrid() {
        let content = self

        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(headerLabel)

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 208, height: 194)
        layout.minimumInteritemSpacing = 14
        layout.minimumLineSpacing = 14
        layout.sectionInset = NSEdgeInsets(top: 4, left: 16, bottom: 20, right: 16)
        layout.headerReferenceSize = NSSize(width: 0, height: 34)

        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColors = [.clear]
        collectionView.register(ShotItem.self, forItemWithIdentifier: ShotItem.identifier)
        collectionView.register(
            HourHeader.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: HourHeader.identifier)

        gridScroll.documentView = collectionView
        gridScroll.hasVerticalScroller = true
        gridScroll.drawsBackground = false
        gridScroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(gridScroll)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            headerLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            headerLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            gridScroll.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 10),
            gridScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            gridScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            gridScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    private func buildDetail() {
        let content = self

        // Full-bleed translucent overlay; the grid stays faintly visible behind it.
        detailContainer.isHidden = true
        detailContainer.wantsLayer = true
        detailContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(detailContainer)

        // Clicking the dark backdrop (outside the image) closes, like Drive.
        let backdrop = CardView()
        backdrop.onClick = { [weak self] in self?.showGrid() }
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(backdrop)

        detailImage.imageScaling = .scaleProportionallyUpOrDown
        detailImage.wantsLayer = true
        detailImage.layer?.cornerRadius = 14
        detailImage.layer?.masksToBounds = true
        detailImage.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(detailImage)

        let close = circleButton("xmark", action: #selector(showGrid))
        let prev = circleButton("chevron.left", action: #selector(showPrevious))
        let next = circleButton("chevron.right", action: #selector(showNext))

        let info = NSStackView(views: [detailTime, detailActivity, detailBreakdown])
        info.orientation = .vertical
        info.alignment = .leading
        info.spacing = 2
        info.translatesAutoresizingMaskIntoConstraints = false

        detailCounter.translatesAutoresizingMaskIntoConstraints = false

        [close, prev, next, info, detailCounter].forEach { detailContainer.addSubview($0) }

        detailImageW = detailImage.widthAnchor.constraint(equalToConstant: 100)
        detailImageH = detailImage.heightAnchor.constraint(equalToConstant: 100)

        NSLayoutConstraint.activate([
            detailContainer.topAnchor.constraint(equalTo: content.topAnchor),
            detailContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            backdrop.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),

            detailImage.centerXAnchor.constraint(equalTo: detailContainer.centerXAnchor),
            detailImage.centerYAnchor.constraint(equalTo: detailContainer.centerYAnchor),
            detailImageW, detailImageH,

            close.topAnchor.constraint(equalTo: detailContainer.topAnchor, constant: 18),
            close.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor, constant: 18),

            prev.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor, constant: 20),
            prev.centerYAnchor.constraint(equalTo: detailContainer.centerYAnchor),
            next.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor, constant: -20),
            next.centerYAnchor.constraint(equalTo: detailContainer.centerYAnchor),

            info.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor, constant: 24),
            info.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor, constant: -22),

            detailCounter.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor, constant: -24),
            detailCounter.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor, constant: -24),
        ])
    }

    /// Translucent circular button, like Drive's edge arrows and close control.
    private func circleButton(_ symbol: String, action: Selector) -> NSButton {
        let button = NSButton(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!,
            target: self, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        button.layer?.cornerRadius = 24
        button.contentTintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 48).isActive = true
        button.heightAnchor.constraint(equalToConstant: 48).isActive = true
        return button
    }

    /// Sizes the image as large as fits while keeping its aspect ratio, so the
    /// rounded corners hug the picture instead of an empty box.
    private func layoutDetailImage() {
        guard let image = detailImage.image, image.size.width > 0 else { return }
        let maxW = bounds.width - 150
        let maxH = bounds.height - 150
        guard maxW > 0, maxH > 0 else { return }

        let aspect = image.size.width / image.size.height
        var w = maxW
        var h = w / aspect
        if h > maxH { h = maxH; w = h * aspect }
        detailImageW.constant = w
        detailImageH.constant = h
    }

    /// Called by the main window with the day the user has navigated to.
    func reload(for date: Date) {
        currentDate = date
        showGrid()
        loadData()
    }

    @objc private func reloadCurrent() {
        loadData()
    }

    // MARK: - Mode switching

    @objc private func showGrid() {
        detailContainer.isHidden = true
    }

    private func showDetail(at frameIndex: Int) {
        guard frames.indices.contains(frameIndex) else { return }
        index = frameIndex
        // Grid stays mounted behind the translucent overlay, dimmed but visible.
        detailContainer.isHidden = false
        renderDetail()
    }

    private func renderDetail() {
        guard frames.indices.contains(index) else { return }
        let frame = frames[index]
        detailImage.image = NSImage(contentsOf: frame.url)
        layoutDetailImage()

        let minute = frame.minute
        var time = Format.time.string(from: minute.date)
        if frame.displayCount > 1 { time += "  ·  screen \(frame.displayIndex + 1)/\(frame.displayCount)" }
        detailTime.stringValue = time

        detailActivity.stringValue = "\(minute.activity)% activity"
        detailActivity.textColor = ActivityColor.of(minute.activity)

        var line = "keyboard \(minute.keyboard)%  ·  mouse \(minute.mouse)%"
        if let app = minute.app { line += "  ·  \(app)" }
        detailBreakdown.stringValue = line

        detailCounter.stringValue = "\(index + 1) / \(frames.count)"
    }

    @objc private func showPrevious() {
        guard index > 0 else { return }
        index -= 1
        renderDetail()
    }

    @objc private func showNext() {
        guard index < frames.count - 1 else { return }
        index += 1
        renderDetail()
    }

    private var inDetail: Bool { !detailContainer.isHidden }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true,
                  self.superview != nil, self.inDetail else { return event }
            switch event.keyCode {
            case 123: self.showPrevious(); return nil
            case 124: self.showNext(); return nil
            case 53: self.showGrid(); return nil
            default: return event
            }
        }
    }

    // MARK: - Data

    private func loadData() {
        let viewingId = AccountStore.shared.viewing.id
        groups = DayData.hours(on: currentDate, user: viewingId)
        rebuildFrames()

        let total = Format.compact(DayData.totalWorked(on: currentDate, user: viewingId))
        let isToday = Calendar.current.isDateInToday(currentDate)
        var header = isToday ? "Total today: \(total)" : "Total: \(total)"
        if let avg = DayData.averageActivity(on: currentDate, user: viewingId) {
            header += "   ·   avg. activity \(avg)%"
        }
        if groups.isEmpty { header += "   ·   no screenshots" }
        headerLabel.stringValue = header

        collectionView.reloadData()
        if inDetail { renderDetail() }
    }

    private func rebuildFrames() {
        frames.removeAll()
        frameStart.removeAll()
        for group in groups {
            var starts: [Int] = []
            for minute in group.minutes {
                starts.append(frames.count)
                for (i, url) in minute.screenshots.enumerated() {
                    frames.append(ViewerFrame(
                        url: url, minute: minute,
                        displayIndex: i, displayCount: minute.screenshots.count))
                }
            }
            frameStart.append(starts)
        }
    }

    // MARK: - Collection view

    func numberOfSections(in collectionView: NSCollectionView) -> Int { groups.count }

    func collectionView(_ collectionView: NSCollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        groups[section].minutes.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: ShotItem.identifier, for: indexPath) as! ShotItem
        item.configure(with: groups[indexPath.section].minutes[indexPath.item])
        let start = frameStart[indexPath.section][indexPath.item]
        item.onClick = { [weak self] in self?.showDetail(at: start) }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView,
                        viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                        at indexPath: IndexPath) -> NSView {
        let header = collectionView.makeSupplementaryView(
            ofKind: kind, withIdentifier: HourHeader.identifier, for: indexPath) as! HourHeader
        header.configure(groups[indexPath.section])
        return header
    }

    // MARK: - Thumbnails

    static func thumbnail(for url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 460,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
}
