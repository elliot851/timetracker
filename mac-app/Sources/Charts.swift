import AppKit

/// A small trend line with a soft fill underneath — the mini-graph on stat cards
/// and per-person rows.
final class SparklineView: NSView {
    var values: [Int] = [] { didSet { needsDisplay = true } }
    var color: NSColor = Palette.accent { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard values.count > 1 else { return }
        let maxV = CGFloat(max(values.max() ?? 1, 1))
        let stepX = bounds.width / CGFloat(values.count - 1)
        let pad: CGFloat = 3

        func point(_ i: Int) -> NSPoint {
            let x = CGFloat(i) * stepX
            let y = pad + (bounds.height - pad * 2) * CGFloat(values[i]) / maxV
            return NSPoint(x: x, y: y)
        }

        let line = NSBezierPath()
        line.move(to: point(0))
        for i in 1..<values.count { line.line(to: point(i)) }

        // Soft fill down to the baseline.
        let fill = line.copy() as! NSBezierPath
        fill.line(to: NSPoint(x: bounds.width, y: 0))
        fill.line(to: NSPoint(x: 0, y: 0))
        fill.close()
        color.withAlphaComponent(0.16).setFill()
        fill.fill()

        color.setStroke()
        line.lineWidth = 2
        line.lineJoinStyle = .round
        line.stroke()
    }
}

/// A donut split into coloured segments — the work-time classification ring.
final class RingView: NSView {
    struct Segment { let value: Int; let color: NSColor }

    var segments: [Segment] = [] { didSet { needsDisplay = true } }
    var centerText: String = "" { didSet { needsDisplay = true } }
    var centerCaption: String = "" { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let total = CGFloat(segments.reduce(0) { $0 + $1.value })
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 6
        let lineWidth: CGFloat = 16

        // Track behind the segments so an empty ring still reads as a ring.
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        NSColor.white.withAlphaComponent(0.06).setStroke()
        track.stroke()

        var start: CGFloat = 90   // 12 o'clock
        if total > 0 {
            for segment in segments where segment.value > 0 {
                let sweep = 360 * CGFloat(segment.value) / total
                let arc = NSBezierPath()
                arc.appendArc(
                    withCenter: center, radius: radius,
                    startAngle: start, endAngle: start - sweep, clockwise: true)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .butt
                segment.color.setStroke()
                arc.stroke()
                start -= sweep
            }
        }

        drawCentered(centerText, size: 26, weight: .bold, dy: 4, color: Palette.textPrimary, center: center)
        drawCentered(centerCaption, size: 10, weight: .regular, dy: -16,
                     color: Palette.textSecondary, center: center)
    }

    private func drawCentered(
        _ text: String, size: CGFloat, weight: NSFont.Weight, dy: CGFloat,
        color: NSColor, center: NSPoint
    ) {
        guard !text.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
        ]
        let string = NSAttributedString(string: text, attributes: attrs)
        let s = string.size()
        string.draw(at: NSPoint(x: center.x - s.width / 2, y: center.y + dy - s.height / 2))
    }
}
