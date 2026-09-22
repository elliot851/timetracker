import AppKit

/// A 6-box one-time-code input: one digit per box, auto-advancing, with backspace
/// moving back and paste distributing a full code across the boxes.
final class CodeInputView: NSView, NSTextFieldDelegate {
    private let count = 6
    private var boxes: [NSTextField] = []
    var onComplete: (() -> Void)?

    var code: String { boxes.map { $0.stringValue }.joined() }

    init() {
        super.init(frame: .zero)
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for _ in 0..<count {
            let box = NSTextField()
            box.alignment = .center
            box.font = NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .bold)
            box.bezelStyle = .roundedBezel
            box.focusRingType = .none
            box.delegate = self
            box.translatesAutoresizingMaskIntoConstraints = false
            box.heightAnchor.constraint(equalToConstant: 52).isActive = true
            box.widthAnchor.constraint(equalToConstant: 42).isActive = true
            boxes.append(box)
            stack.addArrangedSubview(box)
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func clear() {
        boxes.forEach { $0.stringValue = "" }
    }

    func focusFirst() {
        window?.makeFirstResponder(boxes.first)
    }

    // MARK: - Behavior

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              let index = boxes.firstIndex(of: field) else { return }

        let digits = field.stringValue.filter { $0.isNumber }

        // Paste of a whole code: spread it across the boxes from here.
        if digits.count > 1 {
            let chars = Array(digits)
            for (offset, box) in boxes[index...].enumerated() {
                box.stringValue = offset < chars.count ? String(chars[offset]) : ""
            }
            let filled = min(index + chars.count, count)
            window?.makeFirstResponder(filled < count ? boxes[filled] : boxes[count - 1])
            if code.count == count { onComplete?() }
            return
        }

        // Single digit: keep one char, advance.
        field.stringValue = String(digits.prefix(1))
        if !field.stringValue.isEmpty, index + 1 < count {
            window?.makeFirstResponder(boxes[index + 1])
        }
        if code.count == count { onComplete?() }
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy selector: Selector) -> Bool {
        guard let field = control as? NSTextField,
              let index = boxes.firstIndex(of: field) else { return false }
        if selector == #selector(NSResponder.deleteBackward(_:)),
           field.stringValue.isEmpty, index > 0 {
            boxes[index - 1].stringValue = ""
            window?.makeFirstResponder(boxes[index - 1])
            return true
        }
        return false
    }
}
