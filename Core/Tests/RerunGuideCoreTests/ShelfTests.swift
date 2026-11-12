import XCTest
@testable import RerunGuideCore

/// The Top Shelf and widget listings: what the guide airs, within the program budget, and the tune link.
final class ShelfTests: XCTestCase {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()

    func testListingsMatchTheGuide() throws {
        let lineup = ChannelBuilder.channels(from: DemoMediaServer.items) + [Channel.scrambled]
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 20))!   // the week holds the 25-hour Nov 1
        let shown = lineup.filter { !$0.isScrambled }
        let shelf = Shelf.make(lineup: lineup, shown: shown, kind: .jellyfin, baseURL: URL(string: "http://h:8096")!, theme: "late", now: now, calendar: cal)
        let from = cal.startOfDay(for: now)
        XCTAssertEqual(shelf.until, cal.date(byAdding: .day, value: 7, to: from))
        XCTAssertEqual(shelf.rows.map(\.id), shown.map(\.id))
        for row in shelf.rows {
            XCTAssertEqual(row.programs.first?.start, from, row.id)
            XCTAssertEqual(row.programs.last?.end, shelf.until, row.id)
            for (a, b) in zip(row.programs, row.programs.dropFirst()) { XCTAssertEqual(a.end, b.start, row.id) }
        }
        var t = from.addingTimeInterval(1), days: [Date: [String: [Slot]]] = [:]
        while t < shelf.until {
            let d = cal.startOfDay(for: t)
            if days[d] == nil { days[d] = GuideGenerator.schedule(lineup: lineup, day: d, calendar: cal) }
            for row in shelf.rows {
                XCTAssertEqual(row.program(at: t)?.start, days[d]![row.id]!.first { $0.start <= t && t < $0.end }?.start, "\(row.id) at \(t)")
            }
            t = t.addingTimeInterval(1800)
        }
        let e = JSONEncoder(); e.outputFormatting = .sortedKeys
        XCTAssertEqual(try JSONDecoder().decode(Shelf.self, from: e.encode(shelf)), shelf)
    }

    func testProgramBudget() {
        let lineup = (0..<20).map { c in
            Channel(id: "c\(c)", number: c + 2, name: "C\(c)", items: (0..<40).map { MediaItem(id: "c\(c)-\($0)", kind: .movie, title: "F\(c)-\($0)", runtime: 5 * 60) })
        }
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 9))!
        let shelf = Shelf.make(lineup: lineup, shown: lineup, kind: .plex, baseURL: URL(string: "https://p")!, theme: "late", now: now, calendar: cal)
        XCTAssertLessThanOrEqual(shelf.rows.reduce(0) { $0 + $1.programs.count }, Shelf.maxPrograms)
        XCTAssertLessThan(shelf.until, cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: now))!)
        for row in shelf.rows {
            XCTAssertEqual(row.programs.first?.start, cal.startOfDay(for: now))
            XCTAssertGreaterThanOrEqual(row.programs.last!.end, shelf.until)
        }
    }

    func testTuneLinkRoundTrip() {
        for id in ["lead:new-movies", "genre:Sci-Fi:movies", "director:Marguerite Vole", "custom:" + UUID().uuidString] {
            XCTAssertEqual(Shelf.channelID(from: Shelf.tuneURL(id)), id)
        }
        XCTAssertNil(Shelf.channelID(from: URL(string: "https://tune?channel=x")!))
        XCTAssertNil(Shelf.channelID(from: URL(string: "rerunguide://info?channel=x")!))
        XCTAssertNil(Shelf.channelID(from: URL(string: "rerunguide://tune")!))
        XCTAssertNil(Shelf.channelID(from: Shelf.tuneURL(String(repeating: "x", count: 201))))
    }
}
