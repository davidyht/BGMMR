import Foundation

/// Installs a launchd agent that starts BGMMR when Hearthstone becomes active (it watches
/// Hearthstone's log folder, which the game writes to on launch). The app quits itself when
/// Hearthstone closes, so nothing of ours runs while you're not playing.
enum AutoStart {
    static let label = "net.bgmmr.opponentmmr.autostart"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    /// Hearthstone's log directory (sibling of Hearthstone.app), derived from the manual path
    /// if set, else the default install location.
    static func logsDir() -> String {
        if !Settings.hearthstonePath.isEmpty {
            return URL(fileURLWithPath: Settings.hearthstonePath)
                .deletingLastPathComponent().appendingPathComponent("Logs").path
        }
        return "/Applications/Hearthstone/Logs"
    }

    @discardableResult
    static func install() -> String? {
        let appPath = Bundle.main.bundlePath
        let logs = logsDir()
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-g", appPath],
            "WatchPaths": [logs],
            "RunAtLoad": false,
        ]
        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            try data.write(to: plistURL)
            _ = launchctl(["unload", plistURL.path])      // reload if it was loaded
            _ = launchctl(["load", "-w", plistURL.path])
            Settings.autoStart = true
            if !FileManager.default.fileExists(atPath: logs) {
                return "Enabled, but \(logs) doesn't exist yet — it will start working after Hearthstone has run once (or set the Hearthstone path)."
            }
            return nil
        } catch {
            return "Failed to enable auto-start: \(error.localizedDescription)"
        }
    }

    static func remove() {
        _ = launchctl(["unload", "-w", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
        Settings.autoStart = false
    }

    /// Re-install if the watched path changed (e.g. user set a new Hearthstone path).
    static func refreshIfInstalled() {
        if isInstalled { _ = install() }
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardError = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { return -1 }
    }
}
