import XCTest
@testable import RerunGuideCore

/// The holiday channel: each day the nearest holiday's films, Groundhog Day back to back on February 2, and a lineup
/// that keeps every other channel's number.
final class HolidayTests: XCTestCase {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()
    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))! }
    func film(_ id: String, _ title: String, overview: String? = nil, genres: [String] = []) -> MediaItem {
        MediaItem(id: id, kind: .movie, title: title, genres: genres, runtime: 5400, overview: overview)
    }
    /// Four films for every holiday, by its words alone (no genre or year: they would add shelves of their own), and
    /// Groundhog Day.
    var films: [MediaItem] {
        let lines = [("newYear", "A party on New Year’s Eve."), ("valentines", "A Valentine’s card goes astray."),
                     ("stPatricks", "A leprechaun wants his gold back."), ("easter", "The Easter Bunny is missing."),
                     ("july4", "Fireworks on the Fourth of July."), ("halloween", "Trick or treat on the wrong street."),
                     ("thanksgiving", "Home for Thanksgiving."), ("christmas", "Santa Claus is stuck in the chimney.")]
        return lines.flatMap { name, overview in (0..<4).map { film("\(name)\($0)", "Film \($0)", overview: overview) } }
            + [film("ghd", "Groundhog Day")]
    }
    func pick(_ y: Int, _ m: Int, _ d: Int, in films: [MediaItem]? = nil) -> String {
        Holiday.pick(films ?? self.films, on: date(y, m, d), calendar: cal).name
    }

    func testDates() {
        XCTAssertEqual([2025, 2026, 2027].map { Holiday.easter.date(in: $0).month * 100 + Holiday.easter.date(in: $0).day }, [420, 405, 328])
        XCTAssertEqual([2025, 2026, 2027].map { Holiday.thanksgiving.date(in: $0).day }, [27, 26, 25])
        XCTAssertEqual(Holiday.dayNumber(1970, 1, 1), 0)
        XCTAssertEqual(Holiday.dayNumber(2026, 11, 3), 20_760)
        XCTAssertEqual(Holiday.weekday(2026, 11, 3), 2)   // a Tuesday
    }

    func testSeasons() {
        XCTAssertEqual(pick(2026, 10, 1), "Halloween")
        XCTAssertEqual(pick(2026, 10, 31), "Halloween")
        XCTAssertEqual(pick(2026, 11, 1), "Thanksgiving")
        XCTAssertEqual(pick(2025, 11, 1), "Thanksgiving")   // with Thanksgiving on the 27th
        XCTAssertEqual(pick(2025, 10, 31), "Halloween")
        XCTAssertEqual(pick(2026, 11, 26), "Thanksgiving")
        XCTAssertEqual(pick(2026, 11, 27), "Christmas")   // the day after Thanksgiving
        XCTAssertEqual(pick(2025, 11, 23), "Thanksgiving")   // Thanksgiving 2025 is the 27th; Christmas's season overlaps
        XCTAssertEqual(pick(2026, 12, 25), "Christmas")
        XCTAssertEqual(pick(2026, 12, 26), "New Year’s")
        XCTAssertEqual(pick(2027, 1, 1), "New Year’s")
        XCTAssertEqual(pick(2027, 2, 1), "Valentine’s Day")
        XCTAssertEqual(pick(2027, 2, 14), "Valentine’s Day")
        XCTAssertEqual(pick(2027, 3, 17), "St. Patrick’s Day")
        XCTAssertEqual(pick(2027, 3, 28), "Easter")
        XCTAssertEqual(pick(2027, 7, 4), "Fourth of July")
        XCTAssertEqual(pick(2027, 7, 5), "Fourth of July")   // between seasons: the nearest one
        XCTAssertEqual(pick(2027, 9, 10), "Halloween")
    }

    func testGroundhogDay() {
        XCTAssertEqual(pick(2027, 2, 2), "Groundhog Day")
        XCTAssertEqual(Holiday.pick(films, on: date(2027, 2, 2), calendar: cal).films.map(\.id), ["ghd"])
        XCTAssertEqual(pick(2027, 2, 2, in: films.filter { $0.id != "ghd" }), "Valentine’s Day")   // without the film, the season
        XCTAssertEqual(pick(2027, 2, 3), "Valentine’s Day")
        // The day is the film again and again, with its break between.
        let ch = Channel(definition: ChannelDefinition(id: "holiday", number: 2, name: "Holiday Special", tag: "", rule: [.holiday]),
                         items: films)
        let slots = GuideGenerator.schedule(for: ch, day: date(2027, 2, 2), calendar: cal)
        XCTAssertEqual(Set(slots.map(\.item.id)), ["ghd"])
        XCTAssertEqual(slots.first?.start, cal.startOfDay(for: date(2027, 2, 2)))
        XCTAssertEqual(slots.count, 12)
        // The same day on a device set to another calendar (the date is read as Gregorian everywhere).
        var hebrew = Calendar(identifier: .hebrew); hebrew.timeZone = cal.timeZone
        XCTAssertEqual(GuideGenerator.schedule(for: ch, day: date(2027, 2, 2), calendar: hebrew), slots)
        // A cut of the film counts too.
        XCTAssertEqual(pick(2027, 2, 2, in: films.filter { $0.id != "ghd" } + [film("ghd4k", "Groundhog Day (Remastered)")]), "Groundhog Day")
        // The day after is Valentine's again.
        XCTAssertTrue(GuideGenerator.schedule(for: ch, day: date(2027, 2, 3), calendar: cal).allSatisfy { $0.item.id.hasPrefix("valentines") })
    }

    /// A holiday with too few films sits out: its days go to the nearest one that has enough.
    func testThinHolidaysSitOut() {
        let some = films.filter { !$0.id.hasPrefix("thanksgiving") } + [film("tg", "Pieces of April", overview: "Thanksgiving dinner.")]
        XCTAssertEqual(pick(2026, 11, 10, in: some), "Halloween")
        XCTAssertEqual(pick(2026, 11, 20, in: some), "Christmas")
        let two = films.filter { $0.id.hasPrefix("halloween") || $0.id.hasPrefix("christmas") }
        XCTAssertEqual(pick(2027, 6, 1, in: two), "Halloween")
        XCTAssertEqual(pick(2027, 2, 2, in: two), "Christmas")
    }

    /// Romance is Valentine's and horror Halloween's, but not a kids' horror (the `.genre` rule's own exception).
    func testGenres() {
        XCTAssertTrue(Holiday.valentines.has(film("r", "R", genres: ["Romance"])))
        XCTAssertTrue(Holiday.halloween.has(film("h", "H", genres: ["Horror"])))
        XCTAssertFalse(Holiday.halloween.has(film("k", "K", genres: ["Horror", "Family"])))
        XCTAssertTrue(Holiday.halloween.has(film("k2", "K2", overview: "A Halloween night out.", genres: ["Horror", "Family"])))
        XCTAssertFalse(Holiday.christmas.has(MediaItem(id: "e", kind: .episode, title: "A Christmas Special", runtime: 1500)))   // films only
        XCTAssertFalse(Holiday.easter.has(film("w", "W", overview: "Eastern Europe, 1946.")))   // Easter's words are phrases
        XCTAssertFalse(Holiday.halloween.has(film("j", "J", overview: "A jack-of-all-trades.")))
        XCTAssertTrue(Holiday.christmas.has(film("é", "É", overview: "Noël: «Christmas»")))   // after a two-byte non-letter
        XCTAssertFalse(Holiday.christmas.has(film("ü", "Ü", overview: "Noëlëchristmas")))   // after a two-byte letter
    }

    /// The channel goes last, so no other channel's number moves, and only when some holiday has enough films.
    func testLineup() {
        let now = date(2026, 12, 1)
        let base = DemoMediaServer.items.filter { !$0.genres.contains("Horror") }   // the demo's horror is Halloween's
        let plain = ChannelBuilder.automaticChannels(from: base, now: now)
        XCTAssertFalse(plain.contains { $0.id == "holiday" })
        let festive = ChannelBuilder.automaticChannels(from: base + films, now: now)
        let h = festive.last!
        XCTAssertEqual([h.id, h.name, h.tag], ["holiday", "Holiday Special", "Films for the nearest holiday"])
        XCTAssertEqual(h.rule, [.holiday])
        XCTAssertEqual(h.rule.map(\.label), ["Nearest holiday"])
        let before = Dictionary(uniqueKeysWithValues: plain.map { ($0.id, $0.number) })
        for d in festive where before[d.id] != nil { XCTAssertEqual(d.number, before[d.id], d.id) }
        XCTAssertTrue((1...3).contains(h.number - festive[festive.count - 2].number))
        let ch = ChannelBuilder.channels([h], in: base + films, now: now)[0]
        XCTAssertEqual(ch.items.count, films.count)   // every holiday's films, Groundhog Day too; the day picks
        XCTAssertFalse(ch.items.contains { $0.kind == .episode })
    }
}
