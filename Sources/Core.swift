import Foundation

// MARK: - Region

enum Region: String, CaseIterable {
    case us = "US"
    case eu = "EU"
    case ap = "AP"
    // China (NetEase) uses a different API and is not supported.

    var label: String {
        switch self {
        case .us: return "Americas (NA)"
        case .eu: return "Europe (EU)"
        case .ap: return "Asia-Pacific (AP)"
        }
    }
    /// Short tag for display (the API still uses rawValue, i.e. "US" for Americas).
    var short: String {
        switch self {
        case .us: return "NA"
        case .eu: return "EU"
        case .ap: return "AP"
        }
    }
}

// MARK: - Settings (UserDefaults)

enum Settings {
    private static let d = UserDefaults.standard

    static var enabled: Bool {
        get { d.object(forKey: "enabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "enabled") }
    }
    static var region: Region {
        get { Region(rawValue: d.string(forKey: "region") ?? "") ?? .us }
        set { d.set(newValue.rawValue, forKey: "region") }
    }
    /// Your BattleTag name (no #1234) so the panel can hide yourself. Optional.
    static var ownName: String {
        get { d.string(forKey: "ownName") ?? "" }
        set { d.set(newValue, forKey: "ownName") }
    }
    /// Optional manual path to Hearthstone.app (used if auto-detection by bundle id fails).
    static var hearthstonePath: String {
        get { d.string(forKey: "hearthstonePath") ?? "" }
        set { d.set(newValue, forKey: "hearthstonePath") }
    }
    static var autoStart: Bool {
        get { d.object(forKey: "autoStart") as? Bool ?? false }
        set { d.set(newValue, forKey: "autoStart") }
    }
    static var panelScale: Double {
        get { let v = d.double(forKey: "panelScale"); return v > 0 ? v : 1.0 }
        set { d.set(newValue, forKey: "panelScale") }
    }
    static var panelFrame: NSRect? {
        get {
            guard let s = d.string(forKey: "panelFrame") else { return nil }
            let p = s.split(separator: ",").compactMap { Double($0) }
            guard p.count == 4 else { return nil }
            return NSRect(x: p[0], y: p[1], width: p[2], height: p[3])
        }
        set {
            if let r = newValue {
                d.set("\(r.origin.x),\(r.origin.y),\(r.size.width),\(r.size.height)", forKey: "panelFrame")
            } else {
                d.removeObject(forKey: "panelFrame")
            }
        }
    }
}

// MARK: - Leaderboard service (Blizzard public API)

final class RankService {
    static let shared = RankService()
    private let queue = DispatchQueue(label: "bgmmr.rank")
    private var cache = [String: Int]()                 // lowercased name -> rating
    private var top = [(name: String, rating: Int)]()   // original casing, sorted desc
    private var loadedKey: String?
    private var loading = false
    private init() {}

    /// Rating for a name if it's on the leaderboard (i.e. above the cutoff), else nil.
    func rating(for name: String) -> Int? {
        let key = name.split(separator: "#", maxSplits: 1).first.map(String.init)?.lowercased() ?? name.lowercased()
        return queue.sync { cache[key] }
    }

    /// Highest-rated players currently loaded (for the preview panel).
    func topPlayers(_ n: Int) -> [(name: String, rating: Int)] {
        queue.sync { Array(top.prefix(n)) }
    }

    /// Loads the leaderboard for the region/mode once; calls onLoaded when the cache is ready.
    func prefetch(region: Region, duos: Bool, onLoaded: @escaping () -> Void) {
        let mode = duos ? "battlegroundsduo" : "battlegrounds"
        let key = "\(region.rawValue)|\(mode)"
        queue.async {
            if self.loadedKey == key && !self.cache.isEmpty { return }
            if self.loading { return }
            self.loading = true
            self.loadAllPages(region: region.rawValue, mode: mode) { rows in
                self.queue.async {
                    if !rows.isEmpty {
                        self.cache = Dictionary(rows.map { ($0.0.lowercased(), $0.1) }, uniquingKeysWith: max)
                        self.top = rows.sorted { $0.1 > $1.1 }.map { (name: $0.0, rating: $0.1) }
                        self.loadedKey = key
                    }
                    self.loading = false
                    if !rows.isEmpty { onLoaded() }
                }
            }
        }
    }

    private func url(_ region: String, _ mode: String, _ page: Int) -> URL? {
        URL(string: "https://hearthstone.blizzard.com/en-us/api/community/leaderboardsData?region=\(region)&leaderboardId=\(mode)&page=\(page)")
    }

    // Returns original-cased (name, rating) rows, de-duplicated by lowercased name (max rating).
    private func loadAllPages(region: String, mode: String, completion: @escaping ([(String, Int)]) -> Void) {
        guard let firstURL = url(region, mode, 1) else { completion([]); return }
        var req = URLRequest(url: firstURL); req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data, let first = RankService.parse(data) else { completion([]); return }
            var merged = [String: (String, Int)]()   // lowercased -> (origName, rating)
            func add(_ rows: [(String, Int)]) {
                for (n, r) in rows {
                    let k = n.lowercased()
                    if let e = merged[k], e.1 >= r { continue }
                    merged[k] = (n, r)
                }
            }
            add(first.rows)
            let total = min(first.totalPages, 100)
            if total <= 1 { completion(Array(merged.values)); return }
            let group = DispatchGroup()
            let lock = NSLock()
            for page in 2...total {
                guard let u = self.url(region, mode, page) else { continue }
                group.enter()
                var r = URLRequest(url: u); r.timeoutInterval = 20
                URLSession.shared.dataTask(with: r) { d, _, _ in
                    defer { group.leave() }
                    guard let d, let parsed = RankService.parse(d) else { return }
                    lock.lock(); add(parsed.rows); lock.unlock()
                }.resume()
            }
            group.notify(queue: .global()) { completion(Array(merged.values)) }
        }.resume()
    }

    private static func parse(_ data: Data) -> (rows: [(String, Int)], totalPages: Int)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lb = json["leaderboard"] as? [String: Any],
              let rows = lb["rows"] as? [[String: Any]] else { return nil }
        let total = (lb["pagination"] as? [String: Any])?["totalPages"] as? Int ?? 1
        var out = [(String, Int)]()
        for row in rows {
            if let acc = row["accountid"] as? String, let rating = row["rating"] as? Int {
                out.append((acc, rating))
            }
        }
        return (out, total)
    }
}
