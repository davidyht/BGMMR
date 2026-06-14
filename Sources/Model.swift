import Foundation

/// Accumulates opponents seen this game and drives the panel. Thread-safe.
final class MmrModel {
    static let shared = MmrModel()
    private let lock = NSLock()
    private var seen = Set<String>()
    private var ordered = [String]()
    private var duos = false
    private init() {}

    private func key(_ n: String) -> String {
        (n.split(separator: "#", maxSplits: 1).first.map(String.init) ?? n).lowercased()
    }

    func setState(names: [String], mode: String) {
        guard Settings.enabled else { return }
        let ownKey = Settings.ownName.isEmpty ? nil : key(Settings.ownName)
        lock.lock()
        if mode == "duos" { duos = true } else if mode == "solo" { duos = false }
        let wasDuos = duos
        for raw in names {
            let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if n.isEmpty { continue }
            let k = key(n)
            if k == ownKey { continue }
            if !seen.contains(k) { seen.insert(k); ordered.append(n) }
        }
        lock.unlock()

        // Make sure the right leaderboard is loaded; refresh the panel when it arrives.
        RankService.shared.prefetch(region: Settings.region, duos: wasDuos) { [weak self] in
            self?.publish()
        }
        publish()
    }

    func publish() {
        lock.lock(); let names = ordered; lock.unlock()
        guard !names.isEmpty else { return }
        let entries = names.map { (name: $0, rating: RankService.shared.rating(for: $0)) }
            .sorted { ($0.rating ?? -1) > ($1.rating ?? -1) }
        DispatchQueue.main.async { MmrPanel.shared.update(entries: entries) }
    }

    func reset() {
        lock.lock(); seen.removeAll(); ordered.removeAll(); duos = false; lock.unlock()
        DispatchQueue.main.async { MmrPanel.shared.resetState() }
    }
}
