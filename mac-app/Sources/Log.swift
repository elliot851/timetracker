import Foundation

/// Appends to ~/Documents/TimeTracker/tracker.log. A background agent has nowhere
/// to show errors, so failures need somewhere durable to land.
enum Log {
    private static var fileURL: URL { Storage.logFile(user: Storage.recordingUserId) }

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func write(_ message: String) {
        let line = "[\(timestamp.string(from: Date()))] \(message)\n"
        NSLog("%@", message)

        guard let data = line.data(using: .utf8) else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }
}
