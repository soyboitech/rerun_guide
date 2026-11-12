import Foundation

/// The "On now" listings the app leaves for the Apple TV Top Shelf and the iPhone and iPad widget: ready-made programs
/// for the guide's channels from the write day's midnight to `until`. The extensions read it and pick the program that
/// contains now; they never schedule anything, open the library cache or evaluate a rule.
public struct Shelf: Codable, Equatable, Sendable {
    public struct Program: Codable, Equatable, Sendable {
        public let title: String
        public let start: Date, end: Date, itemEnd: Date
        /// The server-relative poster path (no token).
        public let art: String?
        public init(title: String, start: Date, end: Date, itemEnd: Date, art: String?) {
            self.title = title; self.start = start; self.end = end; self.itemEnd = itemEnd; self.art = art
        }
    }
    public struct Row: Codable, Equatable, Sendable {
        public let id: String, number: Int, name: String, hue: Double
        /// From local midnight of the write day past `until`, in order, gap-free.
        public let programs: [Program]
        public init(id: String, number: Int, name: String, hue: Double, programs: [Program]) {
            self.id = id; self.number = number; self.name = name; self.hue = hue; self.programs = programs
        }
        public func program(at time: Date) -> Program? { programs.first { $0.start <= time && time < $0.end } }
        public func next(after time: Date) -> Program? { programs.first { $0.start > time } }
    }
    public let kind: ServerKind
    public let baseURL: URL
    /// The profile's theme (`ThemeID` raw value).
    public let theme: String
    /// The zone the times were tiled in: another zone means another schedule, so the extensions show nothing.
    public let zone: String
    public let until: Date
    public let rows: [Row]

    public static let maxRows = 20
    static let group = "group.com.rerunguide.RerunGuide", scheme = "rerunguide", days = 7
    /// ponytail: the extensions decode the whole file, so it is bounded by programs, not days: 4,000 is about 0.7 MB. A
    /// week of films fits; 22-minute episodes get about four days, cartoons a day, two-minute clips a few hours, then the
    /// static shelf until the app runs again. Upgrade: export the item lists and run GuideGenerator in the extension.
    static let maxPrograms = 4000

    /// `lineup`: every channel, hidden ones included, as the app holds them (the lineup pass needs them all). `shown`:
    /// the rows to export, in order.
    public static func make(lineup: [Channel], shown: [Channel], kind: ServerKind, baseURL: URL, theme: String, now: Date,
                            calendar: Calendar = .current) -> Shelf {
        let from = calendar.startOfDay(for: now)
        var until = calendar.date(byAdding: .day, value: days, to: from)!
        var byID: [String: [Slot]] = Dictionary(shown.map { ($0.id, []) }, uniquingKeysWith: { a, _ in a })
        var day = from
        while day < until {
            let lineupDay = GuideGenerator.schedule(lineup: lineup, day: day, calendar: calendar)
            for ch in shown { byID[ch.id]! += lineupDay[ch.id] ?? [] }
            day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: day)!)
        }
        var listings = shown.map { byID[$0.id]! }
        let starts = listings.flatMap { $0.map(\.start) }.sorted()
        if starts.count > maxPrograms {   // every row still covers [from, until]: until is a program start, rows are gap-free
            until = starts[maxPrograms]
            listings = listings.map { $0.filter { $0.start < until } }
        }
        let rows = zip(shown, listings).map { ch, slots in
            Row(id: ch.id, number: ch.number, name: ch.name, hue: ch.hue, programs: slots.map {
                Program(title: $0.item.displayTitle, start: $0.start, end: $0.end, itemEnd: $0.itemEnd, art: $0.item.artworkPath)
            })
        }
        return Shelf(kind: kind, baseURL: baseURL, theme: theme, zone: calendar.timeZone.identifier, until: until, rows: rows)
    }

    /// `rerunguide://tune?channel=<id>`: tune that channel live.
    public static func tuneURL(_ channelID: String) -> URL {
        var c = URLComponents()
        c.scheme = scheme; c.host = "tune"; c.queryItems = [URLQueryItem(name: "channel", value: channelID)]
        return c.url!
    }
    /// The channel a tune link names; nil for anything else (only a channel id ever comes in this way).
    public static func channelID(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == "tune",
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "channel" })?.value,
              (1...200).contains(id.count) else { return nil }
        return id
    }

    /// `<group container>/Library/Caches/shelf.json`; nil without the App Group (and on the Mac, which has neither surface).
    public static var url: URL? {
        #if targetEnvironment(macCatalyst) || os(macOS)
        return nil
        #else
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("Library/Caches/shelf.json")
        #endif
    }
    public static func load() -> Shelf? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Shelf.self, from: data)
    }
    /// Writes only when the bytes differ (sorted keys, no write time), so an unchanged lineup costs no widget reload.
    public static func save(_ shelf: Shelf) -> Bool {
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        guard let url, let data = try? e.encode(shelf), (try? Data(contentsOf: url)) != data else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }
    public static func clear() { if let url { try? FileManager.default.removeItem(at: url) } }
}

public extension ServerKind {
    /// The client for a linked server: the app's, and the Top Shelf's for its poster URLs.
    func makeServer(baseURL: URL, token: String, userID: String?, deviceID: String, name: String, maxBitrateKbps: Int = 0) -> any MediaServer {
        switch self {
        case .plex: PlexClient(baseURL: baseURL, token: token, clientID: deviceID, serverName: name, maxBitrateKbps: maxBitrateKbps)
        case .emby, .jellyfin: JellyfinClient(baseURL: baseURL, token: token, userID: userID ?? "", deviceID: deviceID, kind: self, serverName: name, maxBitrateKbps: maxBitrateKbps)
        case .demo: DemoMediaServer()
        }
    }
}
