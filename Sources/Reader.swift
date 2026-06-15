import Cocoa

let kHearthstoneBundleID = "unity.Blizzard Entertainment.Hearthstone"

/// Spawns the bundled bgmmr-reader against a Hearthstone pid and parses its JSON stream.
final class LeaderboardReader {
    static let shared = LeaderboardReader()
    private let lock = NSLock()
    private var process: Process?
    private var buffer = Data()
    private var pid: pid_t = 0
    private init() {}

    private var helperURL: URL? {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/bgmmr-reader")
    }

    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return process != nil }
    var attachedPid: pid_t { lock.lock(); defer { lock.unlock() }; return pid }

    func start(pid newPid: pid_t) {
        stop()
        guard let helper = helperURL, FileManager.default.isExecutableFile(atPath: helper.path) else {
            NSLog("BGMMR: helper not found at \(helperURL?.path ?? "nil")"); return
        }
        let proc = Process()
        proc.executableURL = helper
        proc.arguments = ["\(newPid)"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in self?.consume(h.availableData) }
        // If the helper exits (HS quit, attach failed, crash), clean up so the watcher retries.
        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.lock.lock()
                if self.process === p { self.process = nil; self.pid = 0; self.buffer.removeAll() }
                self.lock.unlock()
                MmrModel.shared.reset()
            }
        }
        do {
            try proc.run()
            lock.lock(); process = proc; pid = newPid; lock.unlock()
            NSLog("BGMMR: reader attached to pid \(newPid)")
        } catch { NSLog("BGMMR: reader failed: \(error)") }
    }

    func stop() {
        lock.lock(); let p = process; process = nil; pid = 0; buffer.removeAll(); lock.unlock()
        if let p = p {
            (p.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            p.terminationHandler = nil
            p.terminate()
        }
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        let nl = UInt8(ascii: "\n")
        while let i = buffer.firstIndex(of: nl) {
            let line = buffer.subdata(in: buffer.startIndex..<i)
            buffer.removeSubrange(buffer.startIndex...i)
            handle(line)
        }
    }

    private func handle(_ line: Data) {
        guard !line.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = obj["payload"] as? [String: Any] else { return }
        if let names = payload["names"] as? [String] {
            let mode = payload["mode"] as? String ?? "unknown"
            if !names.isEmpty { MmrModel.shared.setState(names: names, mode: mode) }
        }
    }
}

/// Polls for Hearthstone and keeps the reader attached. Exposes a status for the menu.
final class HearthstoneWatcher {
    static let shared = HearthstoneWatcher()
    enum State { case disabled, noGame, rosetta, connecting, connected }
    private(set) var state: State = .noGame
    private var timer: Timer?
    private init() {}

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    /// Re-evaluate immediately (e.g. after toggling Enabled).
    func refresh() { tick() }

    private var sawHearthstone = false
    private var noGameTicks = 0

    private func hearthstone() -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        if !Settings.hearthstonePath.isEmpty {
            let target = URL(fileURLWithPath: Settings.hearthstonePath).standardizedFileURL
            if let a = apps.first(where: { $0.bundleURL?.standardizedFileURL == target }) { return a }
        }
        return apps.first { $0.bundleIdentifier == kHearthstoneBundleID }
    }

    private func tick() {
        if !Settings.enabled {
            if LeaderboardReader.shared.isRunning { LeaderboardReader.shared.stop(); MmrModel.shared.reset() }
            state = .disabled; return
        }
        guard let app = hearthstone(), !app.isTerminated else {
            if LeaderboardReader.shared.isRunning { LeaderboardReader.shared.stop(); MmrModel.shared.reset() }
            state = .noGame
            // Auto-quit once Hearthstone has been seen and then closed (auto-start mode only).
            // Require a *sustained* absence plus an independent confirmation that HS is
            // really gone, so a transient runningApplications blip (common under the heavy
            // load at end-of-game) can't close the app while you're still playing.
            if Settings.autoStart && sawHearthstone {
                noGameTicks += 1
                let confirmedGone = NSRunningApplication
                    .runningApplications(withBundleIdentifier: kHearthstoneBundleID)
                    .allSatisfy { $0.isTerminated }
                if noGameTicks >= 6 && confirmedGone { NSApp.terminate(nil) }
            }
            return
        }
        sawHearthstone = true
        noGameTicks = 0
        // Frida can't inject into a Rosetta/translated process — needs native arm64.
        if app.executableArchitecture != NSBundleExecutableArchitectureARM64 {
            if LeaderboardReader.shared.isRunning { LeaderboardReader.shared.stop(); MmrModel.shared.reset() }
            state = .rosetta; return
        }
        let pid = app.processIdentifier
        if LeaderboardReader.shared.isRunning && LeaderboardReader.shared.attachedPid == pid {
            state = .connected
        } else {
            MmrModel.shared.reset()
            LeaderboardReader.shared.start(pid: pid)
            state = .connecting
        }
    }
}
