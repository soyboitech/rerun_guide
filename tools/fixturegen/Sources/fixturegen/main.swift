// Cross-platform parity fixture: what the Swift Core produces for the demo library, so the Kotlin port can be checked
// value for value (the schedule must agree on every device, Apple TV or Google TV).
import Foundation
@testable import RerunGuideCore

var tz = TimeZone(identifier: "America/Los_Angeles")!
var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 20))!

var out: [String: Any] = [:]
out["timeZone"] = tz.identifier
out["now"] = now.timeIntervalSince1970

var g = SeededGenerator(seed: "parity|2026-10-24")
out["seeded"] = (0..<8).map { _ in String(g.next()) }
var g2 = SeededGenerator(seed: "shuffle-check")
out["shuffle20"] = Array(0..<20).shuffled(using: &g2)
var g3 = SeededGenerator(seed: "bounded")
out["bounded"] = (0..<12).map { i in Int.random(in: 0..<(i + 3) * 7, using: &g3) }
out["fnv1a"] = ["", "a", "genre:Comedy:tv", "retro-binge-dial", "Rerun Guide ✓"].map { ["s": $0, "h": String(StableHash.fnv1a($0))] }

// Films: addedAt pinned to `now` as the ports pin it (the demo's follows the wall clock), and every third one watched
// (m3, m6, ...) so Unwatched and its rule are checked too. The demo server itself has none watched.
let lib = DemoMediaServer.items.map { m in
    guard m.kind == .movie, let n = Int(m.id.dropFirst()) else { return m }
    return MediaItem(id: m.id, kind: m.kind, title: m.title, seriesTitle: m.seriesTitle, seriesID: m.seriesID, season: m.season,
                     episode: m.episode, year: m.year, genres: m.genres, runtime: m.runtime, artworkPath: m.artworkPath,
                     backdropPath: m.backdropPath, overview: m.overview, contentRating: m.contentRating, directors: m.directors,
                     actors: m.actors, libraryID: m.libraryID, addedAt: now.addingTimeInterval(-Double(n * 6) * 86_400), watched: n % 3 == 0)
}
out["demoItems"] = lib.map { ["id": $0.id, "kind": $0.kind == .movie ? "movie" : "episode", "title": $0.title, "runtime": $0.runtime,
                              "year": $0.year as Any, "genres": $0.genres, "seriesID": $0.seriesID as Any, "watched": $0.watched] }
let defs = ChannelBuilder.automaticChannels(from: lib, now: now)
out["automatic"] = defs.map { ["id": $0.id, "number": $0.number, "name": $0.name, "tag": $0.tag, "rule": $0.rule.map(\.label), "order": $0.order.rawValue] }
let chans = ChannelBuilder.channels(defs, in: lib, now: now) + [Channel.scrambled]
// The whole lineup through one pass a day, as the app schedules it (nothing on two channels at once).
let lineupDays = (0..<3).map { d -> (Date, [String: [Slot]]) in
    let day = cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: now))!
    return (day, GuideGenerator.schedule(lineup: chans, day: day, calendar: cal))
}
out["channels"] = chans.map { ch -> [String: Any] in
    let days = lineupDays.map { day, all -> [String: Any] in
        ["day": day.timeIntervalSince1970, "slots": (all[ch.id] ?? []).map { ["item": $0.item.id, "start": $0.start.timeIntervalSince1970, "end": $0.end.timeIntervalSince1970] }]
    }
    return ["id": ch.id, "items": ch.items.map(\.id), "days": days]
}
func rows(_ slots: [Slot]) -> [[Any]] { slots.map { [$0.item.id, $0.start.timeIntervalSince1970, $0.end.timeIntervalSince1970] as [Any] } }
func days(_ y: Int, _ m: Int, _ d: Int, _ n: Int) -> [Date] { (0..<n).map { cal.date(byAdding: .day, value: $0, to: cal.date(from: DateComponents(year: y, month: m, day: d))!)! } }
// The tape on its own: two marathons and the two-show Comedy TV shelf over both DST changes and two New Years.
let tapeDays = days(2026, 3, 7, 3) + days(2026, 10, 31, 3) + days(2026, 12, 31, 2) + days(2027, 12, 31, 2)
out["continuity"] = ["series:smh", "series:p9", "genre:Comedy:tv"].map { id -> [String: Any] in
    let ch = chans.first { $0.id == id }!
    return ["id": id, "days": tapeDays.map { ["day": $0.timeIntervalSince1970, "slots": rows(GuideGenerator.schedule(for: ch, day: $0, calendar: cal))] }]
}
// Shows taking turns: four shows of 22, 44 and 8 minute episodes, handed over interleaved.
func ep(_ show: String, _ n: Int, _ minutes: Double) -> MediaItem {
    MediaItem(id: "\(show)\(n)", kind: .episode, title: "\(show) \(n)", seriesTitle: show, seriesID: show, season: 1, episode: n, runtime: minutes * 60)
}
let turnItems = [ep("A", 4, 22), ep("D", 3, 8), ep("B", 2, 22), ep("A", 1, 22), ep("C", 1, 44), ep("D", 1, 8), ep("A", 5, 22), ep("B", 1, 22),
                 ep("A", 2, 22), ep("D", 2, 8), ep("A", 3, 22)]
let turns = Channel(id: "turns", number: 2, name: "Turns", items: turnItems)
out["turns"] = [
    "items": turnItems.map { ["id": $0.id, "title": $0.title, "seriesTitle": $0.seriesTitle!, "seriesID": $0.seriesID!, "season": $0.season!, "episode": $0.episode!, "runtime": $0.runtime] },
    "days": days(2026, 3, 1, 3).map { ["day": $0.timeIntervalSince1970, "slots": rows(GuideGenerator.schedule(for: turns, day: $0, calendar: cal))] },
]
// One program on one channel at a time: two shuffle channels of the same five films (with four a last slot, clear of the
// one before and tomorrow's two openers, can be left only the film the other airs), a marathon, and the shelf that
// holds its show; and the four-show turns channel behind a marathon of nine episodes of its show B (B1 and B2 shared).
let films = (1...5).map { MediaItem(id: "f\($0)", kind: .movie, title: "F\($0)", year: 1990, runtime: 95 * 60) }
let conflict = [Channel(id: "x1", number: 10, name: "X1", items: films), Channel(id: "x2", number: 11, name: "X2", items: films),
                chans.first { $0.id == "series:smh" }!, chans.first { $0.id == "genre:Comedy:tv" }!,
                turns, Channel(id: "series:B", number: 30, name: "B", items: (1...9).map { ep("B", $0, 22) }, order: .inOrder)]
out["exclusive"] = [
    "films": films.map { ["id": $0.id, "title": $0.title, "year": $0.year!, "runtime": $0.runtime] },
    "order": GuideGenerator.dependencyOrder(conflict).map(\.id),
    "days": days(2026, 1, 5, 3).map { day -> [String: Any] in
        let all = GuideGenerator.schedule(lineup: conflict, day: day, calendar: cal)
        return ["day": day.timeIntervalSince1970, "channels": conflict.map { ["id": $0.id, "slots": rows(all[$0.id]!)] }]
    },
]
// Short programs sharing a half hour, with fractional runtimes as servers report them: in order and shuffled.
let shorts = [130.7, 245.2, 480.4, 540.9, 701.0, 150.0, 453.3, 720.0, 780.0, 1320.0].enumerated().map { i, r in
    MediaItem(id: "s\(i)", kind: .episode, title: "S\(i)", seriesTitle: "Shorts", seriesID: "shorts", season: 1, episode: i + 1, runtime: r)
}
out["packed"] = [Channel(id: "shorts", number: 2, name: "Shorts", items: shorts, order: .inOrder),
                 Channel(id: "shorts-mix", number: 3, name: "Mix", items: shorts, order: .shuffle)].map { ch in
    (0..<3).map { d in
        GuideGenerator.schedule(for: ch, day: cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: now))!, calendar: cal)
            .map { [$0.item.id, $0.start.timeIntervalSince1970, $0.end.timeIntervalSince1970] as [Any] }
    }
}
var b = Bouncer(stage: (1920, 1080), logo: (400, 400), start: (300, 200))
var bounce: [[Double]] = []
for i in 1...(60 * 60 * 3) { b.step(1.0 / 60); if i % 600 == 0 { bounce.append([b.time, b.x, b.y, b.vx, b.vy, Double(b.corners)]) } }
out["bouncer"] = bounce
// The holiday channel's calendar: Easter and Thanksgiving, and what each day of two years airs, for a library with
// every holiday (and Groundhog Day) and for one with only Halloween and Christmas.
let lines = [("newYear", "A party on New Year’s Eve.", [String]()), ("valentines", "", ["Romance"]),
             ("stPatricks", "A leprechaun wants his gold back.", []), ("easter", "The Easter Bunny is missing.", []),
             ("july4", "Fireworks on the Fourth of July.", []), ("halloween", "", ["Horror"]),
             ("thanksgiving", "Home for Thanksgiving.", []), ("christmas", "Santa Claus is stuck in the chimney.", [])]
let festive = lines.flatMap { name, overview, genres in
    (0..<4).map { MediaItem(id: "\(name)\($0)", kind: .movie, title: "Film \($0)", genres: genres, runtime: 5400, overview: overview.isEmpty ? nil : overview) }
} + [MediaItem(id: "ghd", kind: .movie, title: "Groundhog Day", runtime: 6060)]
let thin = festive.filter { $0.id.hasPrefix("halloween") || $0.id.hasPrefix("christmas") }
// And what the channel itself airs on days the pick narrows (and on the Groundhog Day loop), slot by slot.
let festiveChannel = Channel(definition: ChannelDefinition(id: "holiday", number: 2, name: "Holiday Special", tag: "", rule: [.holiday]), items: festive)
let festiveDays = [(2026, 11, 26), (2026, 11, 27), (2026, 12, 25), (2026, 12, 26), (2027, 2, 1), (2027, 2, 2), (2027, 2, 3)].map { y, m, d -> [String: Any] in
    let day = cal.date(from: DateComponents(year: y, month: m, day: d))!
    return ["day": day.timeIntervalSince1970, "slots": GuideGenerator.schedule(for: festiveChannel, day: day, calendar: cal).map { [$0.item.id, $0.start.timeIntervalSince1970, $0.end.timeIntervalSince1970] as [Any] }]
}
func sweep(_ films: [MediaItem]) -> [[Any]] {
    (0..<730).map { i -> [Any] in
        let day = cal.date(byAdding: .day, value: i, to: cal.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!)!
        let p = Holiday.pick(films, on: day, calendar: cal)
        return [day.timeIntervalSince1970, p.name, p.films.map(\.id)]
    }
}
out["holidays"] = [
    "films": festive.map { ["id": $0.id, "title": $0.title, "overview": $0.overview ?? "", "genres": $0.genres, "runtime": $0.runtime] },
    "easter": (2000...2040).map { y -> [Int] in let e = Holiday.easter.date(in: y); return [y, e.month, e.day] },
    "thanksgiving": (2000...2040).map { [$0, Holiday.thanksgiving.date(in: $0).day] },
    "days": sweep(festive), "thin": sweep(thin), "slots": festiveDays,
]
// Duplicates: copies in a second library (punctuation and accents differ), a cut, films with no year, one item twice, a
// show in two libraries and two shows of one name. What the merge keeps, in order, with its show, watched and added.
func d(_ id: String, _ title: String, _ year: Int?, lib: String, added: Double? = nil, watched: Bool = false) -> MediaItem {
    MediaItem(id: id, kind: .movie, title: title, year: year, runtime: 6000, libraryID: lib, addedAt: added.map { Date(timeIntervalSince1970: $0) }, watched: watched)
}
func e(_ id: String, _ show: String, _ sid: String, _ ep: Int, _ title: String, lib: String, year: Int = 1982) -> MediaItem {
    MediaItem(id: id, kind: .episode, title: title, seriesTitle: show, seriesID: sid, season: 1, episode: ep, year: year, runtime: 1320, libraryID: lib)
}
let dupes = [d("m1", "The Thing", 1982, lib: "movies", added: 1_000), d("u1", "The thing!", 1982, lib: "4k", added: 2_000, watched: true),
             d("m2", "Blade Runner", 1982, lib: "movies"), d("m3", "Blade Runner (The Final Cut)", 1982, lib: "movies"),
             d("m4", "Home Video", nil, lib: "movies"), d("m5", "Home Video", nil, lib: "4k"),
             d("u6", "Amélie", 2001, lib: "4k", added: 3_000), d("m6", "Amelie", 2001, lib: "movies"),
             e("a1", "Cheers", "s1", 1, "Give Me a Ring Sometime", lib: "tv"), e("a2", "Cheers", "s1", 2, "Sams Women", lib: "tv"),
             e("b1", "Cheers", "s9", 1, "Give Me a Ring Sometime", lib: "tv2"), e("b2", "Cheers", "s9", 2, "Sam's Women", lib: "tv2"),
             e("b3", "Cheers", "s9", 3, "The Tortelli Tort", lib: "tv2"), e("a1", "Cheers", "s1", 1, "Give Me a Ring Sometime", lib: "tv2"),
             e("uk1", "The Office", "uk", 1, "Downsize", lib: "tv"), e("us1", "The Office", "us", 1, "Pilot", lib: "tv"),
             e("t9", "Taxi", "x9", 1, "Like Father, Like Daughter", lib: "tv2"), e("t1", "Taxi", "x1", 1, "Like Father, Like Daughter", lib: "tv"),
             e("t2", "Taxi", "x1", 2, "One-Punch Banta", lib: "tv"), e("t8", "Taxi", "x9", 2, "One Punch Banta", lib: "tv2"),
             e("t7", "Taxi", "x9", 3, "Blind Date", lib: "tv2"),
             e("sk1", "Skins", "skuk", 1, "Tony", lib: "tv", year: 2007), e("sk2", "Skins", "skus", 1, "Tony", lib: "tv", year: 2011),
             d("q1", "?", 1990, lib: "movies"), d("q2", "!", 1990, lib: "movies"),
             d("k1", "Alien", 1979, lib: "4k", watched: true), d("k2", "Aliens", 1986, lib: "4k"), d("a3", "Alien", 1979, lib: "movies", added: 500)]
out["dedup"] = [
    "input": dupes.map { ["id": $0.id, "kind": $0.kind == .movie ? "movie" : "episode", "title": $0.title, "seriesTitle": $0.seriesTitle as Any,
                          "seriesID": $0.seriesID as Any, "season": $0.season as Any, "episode": $0.episode as Any, "year": $0.year as Any,
                          "libraryID": $0.libraryID as Any, "addedAt": $0.addedAt?.timeIntervalSince1970 as Any, "watched": $0.watched] },
    "lastResort": ["4k"],
    "merged": Duplicates.merge(dupes, lastResort: ["4k"]).map { ["id": $0.id, "seriesID": $0.seriesID as Any, "watched": $0.watched, "addedAt": $0.addedAt?.timeIntervalSince1970 as Any] },
]
var rot = SpotRotation(); out["spotRotation"] = (["a", "b", "a", "c", "d", "d"] + (1...30).map { "n\($0)" }).map { rot.next($0) }

let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote", data.count, "bytes;", chans.count, "channels")
