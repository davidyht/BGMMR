import Foundation

/// Accumulates opponents seen this game and drives the panel. Thread-safe.
final class MmrModel {
    static let shared = MmrModel()
    private let lock = NSLock()
    private var seen = Set<String>()
    private var ordered = [String]()
    private var duos = false
    private var emptyStreak = 0
    // Consecutive empty reads (~2s each) before we treat the game as over and clear.
    private static let emptyResetThreshold = 2
    private init() {}

    private func key(_ n: String) -> String {
        (n.split(separator: "#", maxSplits: 1).first.map(String.init) ?? n).lowercased()
    }

    func setState(names: [String], mode: String) {
        guard Settings.enabled else { return }
        let ownKey = Settings.ownName.isEmpty ? nil : key(Settings.ownName)

        // No opponents visible (menu / between games). After a brief debounce, treat the
        // game as over and clear the list so the next game starts with a fresh panel.
        let cleaned = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if cleaned.isEmpty {
            lock.lock(); emptyStreak += 1; let streak = emptyStreak; let hadNames = !ordered.isEmpty; lock.unlock()
            if hadNames && streak >= MmrModel.emptyResetThreshold { reset() }
            return
        }

        lock.lock()
        emptyStreak = 0
        if mode == "duos" { duos = true } else if mode == "solo" { duos = false }
        let wasDuos = duos
        // A lobby whose visible players don't overlap the ones we're tracking is a new
        // game (e.g. teams repopulated without an empty gap) — drop the stale list first.
        let incoming = Set(cleaned.map { key($0) }).subtracting(ownKey.map { [$0] } ?? [])
        if !seen.isEmpty && seen.isDisjoint(with: incoming) {
            seen.removeAll(); ordered.removeAll()
        }
        for n in cleaned {
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
        lock.lock(); seen.removeAll(); ordered.removeAll(); duos = false; emptyStreak = 0; lock.unlock()
        DispatchQueue.main.async { MmrPanel.shared.resetState() }
    }
}
