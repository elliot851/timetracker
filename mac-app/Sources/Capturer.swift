import AppKit
import CoreGraphics
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case permissionDenied
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording is not allowed for TimeTracker."
        case .encodingFailed:
            return "Could not encode the image as JPEG."
        }
    }
}

struct Capturer {
    /// 0.0–1.0. Lower means smaller files, which matters when storing thousands of shots.
    var quality: Double = 0.4

    /// Screens are downscaled to this width before encoding. Still readable for
    /// reviewing what someone worked on, but a fraction of the bytes.
    var maxWidth = 1280

    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system Screen Recording dialog. Only prompts the first time;
    /// after a denial macOS stays silent and the toggle must be flipped by hand.
    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Captures only the display the user is on (the one with the mouse pointer),
    /// not every screen — less storage, less of the person's other monitors exposed.
    func captureActiveDisplay() async throws -> [URL] {
        guard Self.hasPermission() else {
            Self.requestPermission()
            throw CaptureError.permissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        let displays = content.displays
        guard !displays.isEmpty else { return [] }

        let activeID = Self.activeDisplayID()
        let display = displays.first { $0.displayID == activeID } ?? displays[0]

        let scale = min(1.0, Double(maxWidth) / Double(display.width))
        let configuration = SCStreamConfiguration()
        configuration.width = Int(Double(display.width) * scale)
        configuration.height = Int(Double(display.height) * scale)
        configuration.showsCursor = false

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: configuration)

        let url = try Storage.destination(for: Date(), display: 1, of: 1)
        try write(image, to: url)
        return [url]
    }

    /// The display under the mouse pointer, falling back to the main display.
    private static func activeDisplayID() -> CGDirectDisplayID {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
           let number = screen.deviceDescription[
               NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return CGDirectDisplayID(number.uint32Value)
        }
        return CGMainDisplayID()
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(
            using: .jpeg, properties: [.compressionFactor: quality])
        else {
            throw CaptureError.encodingFailed
        }
        try data.write(to: url)
    }
}
