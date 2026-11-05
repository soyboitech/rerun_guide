import XCTest
@testable import RerunGuideCore

/// The same film or episode in two libraries is one item: once on every channel, counted once, one show.
final class DuplicatesTests: XCTestCase {
    func film(_ id: String, _ title: String, _ year: Int?, lib: String = "movies", watched: Bool = false, added: Double? = nil) -> MediaItem {
        MediaItem(id: id, kind: .movie, title: title, year: year, genres: ["Drama"], runtime: 6000, directors: ["Dee Rector"],
                  libraryID: lib, addedAt: added.map { Date(timeIntervalSince1970: $0) }, watched: watched)
    }
    func ep(_ id: String, _ show: String, _ sid: String, _ s: Int, _ e: Int, _ title: String, lib: String = "tv", year: Int = 1990) -> MediaItem {
        MediaItem(id: id, kind: .episode, title: title, seriesTitle: show, seriesID: sid, season: s, episode: e, year: year,
                  genres: ["Comedy"], runtime: 1320, libraryID: lib)
    }

    /// The first copy stays (it plays); watched if either copy is, added when the first copy was.
    func testFilmCopies() {
        let merged = Duplicates.merge([film("m1", "The Thing", 1982, added: 1_000), film("u1", "The thing!", 1982, lib: "4k", watched: true, added: 2_000)])
        XCTAssertEqual(merged.map(\.id), ["m1"])
        XCTAssertEqual(merged[0].libraryID, "movies")
        XCTAssertTrue(merged[0].watched)
        XCTAssertEqual(merged[0].addedAt, Date(timeIntervalSince1970: 1_000))
        // The 4K copy came first: it stays, and still dates from the older copy.
        let other = Duplicates.merge([film("u1", "The Thing", 1982, lib: "4k", added: 2_000), film("m1", "The Thing", 1982, added: 1_000)])
        XCTAssertEqual(other.map(\.id), ["u1"])
        XCTAssertEqual(other[0].addedAt, Date(timeIntervalSince1970: 1_000))
        // A copy with no date counts as old: a new copy of an undated film doesn't make it new.
        XCTAssertNil(Duplicates.merge([film("m1", "The Thing", 1982), film("u1", "The Thing", 1982, lib: "4k", added: 2_000)])[0].addedAt)
    }

    /// A copy in a 4K library plays only when no other library has the film; a film only there still airs.
    func testFourKLibraryIsLastResort() {
        let sections = [LibrarySection(id: "4k", title: "4K Movies", kind: .movies), LibrarySection(id: "movies", title: "Movies", kind: .movies),
                        LibrarySection(id: "uhd", title: "Films (UHD)", kind: .movies)]
        XCTAssertEqual(Duplicates.lastResort(sections), ["4k", "uhd"])
        let items = [film("u1", "The Thing", 1982, lib: "4k", watched: true), film("u2", "Alien", 1979, lib: "4k"), film("m1", "The Thing", 1982)]
        let merged = Duplicates.merge(items, lastResort: Duplicates.lastResort(sections))
        XCTAssertEqual(merged.map(\.id), ["m1", "u2"])
        XCTAssertTrue(merged[0].watched)
    }

    /// Two cuts are two films; a remake (another year) is another film; with no year there's no telling, so both stay.
    func testWhatStaysApart() {
        let items = [film("a", "Blade Runner", 1982), film("b", "Blade Runner (The Final Cut)", 1982),
                     film("c", "The Thing", 1982), film("d", "The Thing", 2011), film("e", "Home Video", nil), film("f", "Home Video", nil)]
        XCTAssertEqual(Duplicates.merge(items).map(\.id), ["a", "b", "c", "d", "e", "f"])
    }

    /// One item listed twice (two chosen libraries sharing it on Emby or Jellyfin) is once.
    func testSameItemTwice() {
        let e = ep("e1", "Cheers", "s1", 1, 1, "Give Me a Ring Sometime")
        XCTAssertEqual(Duplicates.merge([e, film("m", "Diner", 1982), e]).map(\.id), ["e1", "m"])
    }

    /// A show in two libraries is one show: its copies go, and what only the second library has joins the first's show.
    func testShowInTwoLibraries() {
        let items = [ep("a1", "Cheers", "s1", 1, 1, "Give Me a Ring Sometime"), ep("a2", "Cheers", "s1", 1, 2, "Sams Women"),
                     ep("b1", "Cheers", "s9", 1, 1, "Give Me a Ring Sometime", lib: "tv2"), ep("b2", "Cheers", "s9", 1, 2, "Sam's Women", lib: "tv2"),
                     ep("b3", "Cheers", "s9", 1, 3, "The Tortelli Tort", lib: "tv2")]
        let merged = Duplicates.merge(items)
        XCTAssertEqual(merged.map(\.id), ["a1", "a2", "b3"])
        XCTAssertEqual(Set(merged.compactMap(\.seriesID)), ["s1"])
        let marathons = ChannelBuilder.automaticChannels(from: merged, minItems: 3).filter { $0.tag == "Marathon" }
        XCTAssertEqual(marathons.map(\.name), ["Cheers"])
    }

    /// Two shows of one name (the UK and US Office) aren't copies of each other: other episode titles, or the same pilot
    /// title years apart.
    func testShowsOfOneName() {
        let items = [ep("uk1", "The Office", "uk", 1, 1, "Downsize"), ep("us1", "The Office", "us", 1, 1, "Pilot"),
                     ep("sk1", "Skins", "skuk", 1, 1, "Tony", year: 2007), ep("sk2", "Skins", "skus", 1, 1, "Tony", year: 2011)]
        let merged = Duplicates.merge(items)
        XCTAssertEqual(merged.map(\.id), ["uk1", "us1", "sk1", "sk2"])
        XCTAssertEqual(merged.compactMap(\.seriesID), ["uk", "us", "skuk", "skus"])
    }

    /// A custom marathon made from the second library's copy of a show still airs once that show is merged into the first.
    func testCustomMarathonFollowsMergedShow() {
        let items = [ep("a1", "Cheers", "s1", 1, 1, "Give Me a Ring Sometime"), ep("b1", "Cheers", "s9", 1, 1, "Give Me a Ring Sometime", lib: "tv2"),
                     ep("b2", "Cheers", "s9", 1, 2, "Sams Women", lib: "tv2")]
        let custom = ChannelDefinition(id: "custom:c", number: 50, name: "Cheers", tag: "Marathon", rule: [.series(id: "s9", title: "Cheers")],
                                       order: .inOrder, isCustom: true)
        XCTAssertEqual(ChannelBuilder.resolve(custom, in: Duplicates.merge(items)).map(\.id), ["a1", "b2"])
    }

    /// Libraries that come interleaved (one recursive query) still make one show, under the id that turned up first.
    func testInterleavedShow() {
        let items = [ep("b1", "Cheers", "s9", 1, 1, "Give Me a Ring Sometime", lib: "tv2"), ep("a1", "Cheers", "s1", 1, 1, "Give Me a Ring Sometime"),
                     ep("a2", "Cheers", "s1", 1, 2, "Sams Women"), ep("b2", "Cheers", "s9", 1, 2, "Sam's Women", lib: "tv2"),
                     ep("b3", "Cheers", "s9", 1, 3, "The Tortelli Tort", lib: "tv2")]
        let merged = Duplicates.merge(items)
        XCTAssertEqual(merged.map(\.id), ["b1", "a2", "b3"])
        XCTAssertEqual(Set(merged.compactMap(\.seriesID)), ["s9"])
    }

    /// A title with no letters or digits says nothing about the film: never merged.
    func testEmptyTitle() {
        XCTAssertEqual(Duplicates.merge([film("x", "?", 1990), film("y", "!", 1990)]).map(\.id), ["x", "y"])
    }

    /// A library with a 4K copy of every film builds the same lineup as one without, once merged.
    func testLineupCountsFilmsOnce() {
        let films = (0..<6).map { film("f\($0)", "Film \($0)", 1980 + $0) }
        let copies = (0..<6).map { film("k\($0)", "Film \($0)", 1980 + $0, lib: "4k", added: Date.now.timeIntervalSince1970) }
        let now = Date.now
        XCTAssertNotEqual(ChannelBuilder.automaticChannels(from: films + copies, now: now), ChannelBuilder.automaticChannels(from: films, now: now))
        XCTAssertEqual(ChannelBuilder.automaticChannels(from: Duplicates.merge(films + copies), now: now),
                       ChannelBuilder.automaticChannels(from: films, now: now))
    }
}
