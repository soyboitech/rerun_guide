import Foundation

/// Turns a flat library into channel definitions and resolves definitions back into items.
public enum ChannelBuilder {
    /// The automatic channel lineup. Up front, when the library has enough for them: New Releases (films from this year and last),
    /// New This Season (TV from this year and last), Just Added (anything added in the last 60 days), Unwatched (films the
    /// signed-in user hasn't seen), then the classic shelves (TV and films from before 1970). After that every genre shelf,
    /// marathon, director, actor and year channel, scattered with a fixed seed so the lineup feels like cable rather than an
    /// alphabetical list, yet is identical on every device.
    /// Genre shelves get retro names ("Studio Audience", "Gumshoe", "Toon Block"); unknown genres keep their own name.
    /// No channel mixes films and TV: a genre gets a films shelf with ≥ `minItems` films and a TV shelf with ≥ `minItems`
    /// episodes, and director, actor and year channels are films. Only the biggest groups make the lineup (`maxSeries`
    /// marathons, `maxPeople` directors and actors, 3 years).
    public static func automaticChannels(from library: [MediaItem], minItems: Int = 4, maxSeries: Int = 24, maxPeople: Int = 12,
                                         now: Date = .now) -> [ChannelDefinition] {
        func def(_ id: String, _ name: String, _ tag: String, _ rule: [RuleChip], order: PlayOrder = .shuffle) -> ChannelDefinition {
            ChannelDefinition(id: id, number: 0, name: name, tag: tag, rule: rule, order: order)
        }
        func span(_ items: [MediaItem]) -> [RuleChip] {
            let years = items.compactMap(\.year)
            return years.isEmpty ? [] : [.years(years.min()! / 10 * 10, years.max()!)]
        }
        func count(_ rule: [RuleChip]) -> Int { library.lazy.filter { i in rule.allSatisfy { matches($0, i, now: now) } }.count }

        // Lead channels.
        let year = Calendar.current.component(.year, from: now)
        var lead: [ChannelDefinition] = []
        for (id, name, tag, rule, order) in [
            ("lead:new-movies", "New Releases", "Films from \(year - 1)–\(year)", [RuleChip.years(year - 1, year), .movies], PlayOrder.newestFirst),
            ("lead:new-tv", "New This Season", "TV from \(year - 1)–\(year)", [.years(year - 1, year), .tv], .newestFirst),
            ("lead:just-added", "Just Added", "Films new on the server", [.addedWithin(days: 60), .movies], .shuffle),
            ("lead:unwatched", "Unwatched", "Films you haven’t seen", [.unwatched, .movies], .shuffle),
            ("lead:just-added-tv", "Fresh Episodes", "TV new on the server", [.addedWithin(days: 60), .tv], .shuffle),
            ("lead:classic-tv", "Front Porch", "Classic TV, before 1970", [.years(1900, 1969), .tv], .shuffle),
            ("lead:classic-movies", "The Vault", "Classic films, before 1970", [.years(1900, 1969), .movies], .shuffle),
        ] where count(rule) >= minItems {
            lead.append(def(id, name, tag, rule, order: order))
        }

        var byGenre: [String: [MediaItem]] = [:], bySeries: [String: (title: String, eps: [MediaItem])] = [:]
        var byDirector: [String: Int] = [:], byActor: [String: Int] = [:], byYear: [Int: Int] = [:]
        for item in library {
            for g in item.genres { byGenre[g, default: []].append(item) }
            switch item.kind {
            case .episode:
                guard let key = item.seriesID ?? item.seriesTitle else { continue }
                bySeries[key, default: (item.seriesTitle ?? key, [])].eps.append(item)
            case .movie:
                for d in item.directors { byDirector[d, default: 0] += 1 }
                for a in item.actors { byActor[a, default: 0] += 1 }
                if let y = item.year { byYear[y, default: 0] += 1 }
            }
        }

        var genres: [ChannelDefinition] = []
        for (g, all) in byGenre where all.count >= minItems {
            let items = all.filter { matches(.genre(g), $0, now: now) }   // what the shelf will really air (kids' titles leave horror)
            let movies = items.filter { $0.kind == .movie }, eps = items.filter { $0.kind == .episode }
            if movies.count >= minItems {
                let (mn, md) = retroName(g, .movies)
                genres.append(def("genre:\(g):movies", mn, decadeTag(md, years: movies.compactMap(\.year)), [.genre(g)] + span(movies) + [.movies]))
            }
            if eps.count >= minItems {
                let (tn, td) = retroName(g, .tv)
                genres.append(def("genre:\(g):tv", tn, decadeTag(td, years: eps.compactMap(\.year)), [.genre(g)] + span(eps) + [.tv]))
            }
        }
        // Two shelves with the same retro name (two genres mapping to one, or a table gap) get told apart by what's on them.
        let dupes = Set(Dictionary(grouping: genres, by: \.name).filter { $0.value.count > 1 }.keys)
        for i in genres.indices where dupes.contains(genres[i].name) {
            let rule = genres[i].rule
            let kind = rule.contains(.tv) ? "TV" : rule.contains(.movies) ? "Films" : genres[i].id.split(separator: ":").dropFirst().first.map(String.init) ?? ""
            genres[i].name += " (\(kind))"
        }
        // Themed shelves: a keyword net inside a genre family, for what no genre tag covers.
        let themes = [
            def("theme:monsters", "Creature Feature", "Monster movies",
                [.movies, .anyGenre(monsterGenres), .keywords(monsterWords)]),
        ].filter { count($0.rule) >= minItems }
        let series = bySeries.filter { $0.value.eps.count >= minItems }
            .sorted { ($1.value.eps.count, $0.key) < ($0.value.eps.count, $1.key) }.prefix(maxSeries).map {
            def("series:\($0.key)", $0.value.title, "Marathon", [.series(id: $0.key, title: $0.value.title)], order: .inOrder)
        }
        func top(_ counts: [String: Int]) -> [String] {
            counts.filter { $0.value >= minItems }.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.prefix(maxPeople).map(\.key)
        }
        let directors = top(byDirector).map { def("director:\($0)", $0, "Director", [.director($0), .movies]) }
        let actors = top(byActor).map { def("actor:\($0)", $0, "Actor", [.actor($0), .movies]) }
        let years = byYear.filter { $0.value >= minItems }.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.prefix(3)
            .map { def("year:\($0.key)", "Class of ’" + String(format: "%02d", $0.key % 100), "Films from \($0.key)", [.year($0.key), .movies]) }

        // Scatter the rest with a fixed seed: same channels → same order on every device and launch.
        var rng = SeededGenerator(seed: "retro-binge-dial")
        let rest = (genres + themes + series + directors + actors + years).sorted { $0.id < $1.id }.shuffled(using: &rng)
        var all = lead + rest
        // Last, so it renumbers nothing: films for the nearest holiday, picked day by day (`Holiday`). The tag stays put:
        // a lineup built on February 1 can still be up on the 2nd.
        if Holiday.allCases.contains(where: { h in library.lazy.filter(h.has).count >= max(minItems, Holiday.minFilms) }) {
            all.append(def("holiday", "Holiday Special", "Films for the nearest holiday", [.holiday]))
        }
        var n = 0
        for i in all.indices {
            n = i == 0 ? 2 : n + 1 + Int(StableHash.fnv1a(all[i].id) % 3)
            if n == Channel.scrambledNumber { n += 1 }   // 99 belongs to the scrambled channel
            all[i].number = n
        }
        return all
    }

    enum ShelfKind { case movies, tv, mixed }

    /// Retro channel names for the common genres ("Studio Audience", "Gumshoe"). Returns (name, descriptor);
    /// the descriptor becomes the tag with the decade span appended. Unknown genres fall back to the genre itself.
    static func retroName(_ genre: String, _ kind: ShelfKind) -> (String, String) {
        let g = genre.lowercased()
        let table: [String: (movies: (String, String), tv: (String, String), mixed: (String, String))] = [
            "action":          (("Adrenaline", "Action films"), ("Stunt Hour", "Action TV"), ("Adrenaline", "Action")),
            "action & adventure": (("Thrill Ride", "Action & adventure films"), ("Thrill Ride", "Action & adventure TV"), ("Thrill Ride", "Action & adventure")),
            "adventure":       (("The Matinee", "Adventure films"), ("Wide World", "Adventure TV"), ("The Matinee", "Adventure")),
            "animation":       (("The Big Cartoon", "Animated films"), ("Toon Block", "Cartoons"), ("Toon Block", "Animation")),
            "anime":           (("Anime Features", "Anime films"), ("Anime Block", "Anime"), ("Anime Block", "Anime")),
            "biography":       (("Life Stories", "Biopics"), ("Portraits", "Biographies"), ("Life Stories", "Biographies")),
            "children":        (("Kids’ Matinee", "Kids’ films"), ("After School", "Kids’ TV"), ("After School", "Kids")),
            "kids":            (("Kids’ Matinee", "Kids’ films"), ("After School", "Kids’ TV"), ("After School", "Kids")),
            "comedy":          (("Funny Business", "Comedy films"), ("Studio Audience", "Sitcoms"), ("Studio Audience", "Comedy")),
            "crime":           (("Mean Streets", "Crime films"), ("Gumshoe", "Detectives"), ("Gumshoe", "Crime")),
            "documentary":     (("True Stories", "Documentaries"), ("Field Notes", "Documentary TV"), ("True Stories", "Documentaries")),
            "drama":           (("The Picture Show", "Drama films"), ("Prime Time", "Drama series"), ("Prime Time", "Drama")),
            "family":          (("Family Hour", "Family films"), ("Family Room", "Family TV"), ("Family Hour", "Family")),
            "fantasy":         (("Once Upon", "Fantasy films"), ("The Realm", "Fantasy TV"), ("Once Upon", "Fantasy")),
            "food":            (("Dinner Bell", "Food"), ("Dinner Bell", "Food TV"), ("Dinner Bell", "Food")),
            "game show":       (("Game Night", "Game shows"), ("Game Night", "Game shows"), ("Game Night", "Game shows")),
            "history":         (("Days Gone By", "History films"), ("The Archive", "History TV"), ("Days Gone By", "History")),
            "holiday":         (("Yule Log", "Holiday films"), ("Tinsel Time", "Holiday TV"), ("Yule Log", "Holiday")),
            "home and garden": (("Open House", "Home & garden"), ("Open House", "Home & garden"), ("Open House", "Home & garden")),
            "horror":          (("Fright Night", "Horror films"), ("Chiller", "Horror TV"), ("Fright Night", "Horror")),
            "martial arts":    (("Kung Fu Theater", "Martial arts"), ("Kung Fu Theater", "Martial arts"), ("Kung Fu Theater", "Martial arts")),
            "mini-series":     (("The Miniseries", "Mini-series"), ("The Miniseries", "Mini-series"), ("The Miniseries", "Mini-series")),
            "music":           (("The Jukebox", "Music films"), ("Video Hour", "Music TV"), ("The Jukebox", "Music")),
            "musical":         (("Showtunes", "Musicals"), ("Showtunes", "Musicals"), ("Showtunes", "Musicals")),
            "mystery":         (("Whodunit", "Mystery films"), ("Case Files", "Mystery TV"), ("Whodunit", "Mysteries")),
            "news":            (("Newsroom", "News"), ("Newsroom", "News"), ("Newsroom", "News")),
            "reality":         (("Real Life", "Reality TV"), ("Real Life", "Reality TV"), ("Real Life", "Reality TV")),
            "romance":         (("Date Night", "Romance films"), ("Love Lines", "Romance TV"), ("Date Night", "Romance")),
            "sci-fi":          (("Final Frontier", "Sci-fi films"), ("Space Age", "Sci-fi TV"), ("Space Age", "Sci-fi")),
            "science fiction": (("Final Frontier", "Sci-fi films"), ("Space Age", "Sci-fi TV"), ("Space Age", "Sci-fi")),
            "soap":            (("Daytime", "Soaps"), ("Daytime", "Soaps"), ("Daytime", "Soaps")),
            "sport":           (("Game Day", "Sports films"), ("Sports Desk", "Sports TV"), ("Game Day", "Sports")),
            "sports":          (("Game Day", "Sports films"), ("Sports Desk", "Sports TV"), ("Game Day", "Sports")),
            "superhero":       (("Capes & Cowls", "Superhero films"), ("Secret Identity", "Superhero TV"), ("Capes & Cowls", "Superheroes")),
            "suspense":        (("Nail Biter", "Suspense films"), ("Held Breath", "Suspense TV"), ("Nail Biter", "Suspense")),
            "talk show":       (("Late Night", "Talk shows"), ("Late Night", "Talk shows"), ("Late Night", "Talk shows")),
            "thriller":        (("Edge of Your Seat", "Thrillers"), ("Cliffhanger", "Thriller TV"), ("Edge of Your Seat", "Thrillers")),
            "travel":          (("Passport", "Travel films"), ("Road Trip", "Travel TV"), ("Passport", "Travel")),
            "war":             (("The Front", "War films"), ("War Room", "War TV"), ("The Front", "War")),
            "western":         (("Dusty Trails", "Westerns"), ("The Frontier", "Western TV"), ("Dusty Trails", "Westerns")),
        ]
        if let e = table[g] {
            switch kind { case .movies: return e.movies; case .tv: return e.tv; case .mixed: return e.mixed }
        }
        switch kind {
        case .movies: return ("\(genre) Movies", "\(genre) films")
        case .tv: return ("\(genre) TV", "\(genre) TV")
        case .mixed: return (genre, genre)
        }
    }

    /// Items matching every chip of the rule, in the sequence the channel's `order` wants
    /// (`inOrder`: season/episode then year; `newestFirst`: year descending; `shuffle`: library order, shuffled per day by the scheduler).
    public static func resolve(_ definition: ChannelDefinition, in library: [MediaItem], now: Date = .now) -> [MediaItem] {
        // A marathon whose show's copies were merged under another library's (`Duplicates`) follows it by title.
        // ponytail: a show gone from the library hands its chip to another of the same name, if any; say so if it bites.
        let rule = definition.rule.map { chip -> RuleChip in
            guard case let .series(id, title) = chip, !library.contains(where: { $0.seriesID == id }),
                  let moved = library.first(where: { $0.seriesTitle == title && $0.seriesID != nil })?.seriesID else { return chip }
            return .series(id: moved, title: title)
        }
        let items = library.filter { item in rule.allSatisfy { matches($0, item, now: now) } }
        switch definition.order {
        case .shuffle: return items
        case .inOrder: return items.sorted { ($0.season ?? 0, $0.episode ?? 0, $0.year ?? 0, $0.title) < ($1.season ?? 0, $1.episode ?? 0, $1.year ?? 0, $1.title) }
        case .newestFirst: return items.sorted { ($0.year ?? 0, $0.title) > ($1.year ?? 0, $1.title) }
        }
    }

    public static func matches(_ chip: RuleChip, _ item: MediaItem, now: Date = .now) -> Bool {
        switch chip {
        case .addedWithin(let days): return item.addedAt.map { $0 >= now.addingTimeInterval(-Double(days) * 86_400) } ?? false
        case .genre(let g): return item.genres.contains(g) && !(grownUpGenres.contains(g.lowercased()) && isForKids(item))
        case .years(let a, let b): return item.year.map { (a...b).contains($0) } ?? false
        case .director(let d): return item.directors.contains(d)
        case .actor(let a): return item.actors.contains(a)
        case .series(let id, let title): return item.seriesID == id || (item.seriesID == nil && item.seriesTitle == title)
        case .year(let y): return item.year == y
        case .movies: return item.kind == .movie
        case .tv: return item.kind == .episode
        case .anyGenre(let gs): return item.genres.contains { gs.contains($0) }
        case .keywords(let ws): return mentions(item, any: ws)
        case .unwatched: return !item.watched
        case .holiday: return Holiday.isGroundhogDay(item) || Holiday.allCases.contains { $0.has(item) }
        }
    }

    /// Genres whose shelves stay grown-up: a kids' title tagged with one (the animated Gremlins series is "Horror") is left off.
    static let grownUpGenres: Set<String> = ["horror", "thriller"]

    /// Made for children: tagged Children, Kids or Family, rated for kids, or animated without a rating for older viewers
    /// (an adult animated horror like Love, Death & Robots is TV-MA and stays).
    /// ponytail: US ratings only; another country's rating on an animated title counts as not older.
    static func isForKids(_ item: MediaItem) -> Bool {
        let genres = Set(item.genres.map { $0.lowercased() }), rating = item.contentRating?.uppercased()
        if !genres.isDisjoint(with: ["children", "kids", "family"]) { return true }
        if let r = rating, ["TV-Y", "TV-Y7", "TV-Y7-FV", "TV-G", "G"].contains(r) { return true }
        return genres.contains("animation") && !(rating.map { ["TV-14", "TV-MA", "PG-13", "R", "NC-17"].contains($0) } ?? false)
    }

    /// Word-start, case-insensitive search of the title and overview: "creature" takes "creatures", not "procreature".
    /// Compared as bytes (as `TitleSearch.contains` does): Foundation's `range(of:)` made the holiday channel's day take
    /// a tenth of a second on a big library.
    static func mentions(_ item: MediaItem, any words: [String]) -> Bool {
        var text = (item.title + " " + (item.overview ?? "")).lowercased()
        return text.withUTF8 { t in
            words.contains { w in
                var w = w
                return w.withUTF8 { p in
                    guard let f = p.first, p.count <= t.count else { return false }
                    var i = 0
                    while i <= t.count - p.count {
                        guard t[i] == f, memcmp(t.baseAddress! + i, p.baseAddress!, p.count) == 0 else { i += 1; continue }
                        // The character before it isn't a letter: back over UTF-8 continuation bytes to its first byte.
                        var s = i - 1
                        while s > 0 && t[s] & 0xC0 == 0x80 { s -= 1 }
                        if i == 0 || !(String(decoding: UnsafeBufferPointer(rebasing: t[s..<i]), as: UTF8.self).first?.isLetter ?? false) { return true }
                        i += p.count   // past this one, as the ports search
                    }
                    return false
                }
            }
        }
    }

    /// The net for "Creature Feature": lowercase, word-start prefixes ("werewol" takes werewolf and werewolves).
    /// "shark" alone nets loan sharks and shark-infested waters; "great white" is the one that eats people.
    static let monsterWords = ["monster", "kaiju", "godzilla", "king kong", "kong:", "creature", "werewol", "vampire", "zombie",
                               "frankenstein", "dracula", "mummy", "dinosaur", "great white", "megalodon", "gremlin", "xenomorph",
                               "kraken", "leviathan", "cryptid", "sasquatch", "bigfoot", "swamp thing"]
    /// Where the net is cast: Fantasy would add Terabithia and Spirited Away; Action/Adventure adds Jurassic Park and Kong.
    static let monsterGenres = ["Horror", "Science Fiction", "Sci-Fi", "Action", "Adventure"]

    /// The "what's new" channels: New Releases, New This Season, Just Added, and any channel with an "Added in the last N
    /// days" chip. They also see the new items found by the check that runs when the app opens, between full library loads.
    public static func isFresh(_ d: ChannelDefinition) -> Bool {
        ["lead:new-movies", "lead:new-tv", "lead:just-added", "lead:just-added-tv"].contains(d.id)
            || d.rule.contains { if case .addedWithin = $0 { true } else { false } }
    }

    /// `channels(_:in:now:)`, with `fresh` (newly added items not yet in `library`) given to the `isFresh` channels only:
    /// every other channel keeps resolving from `library`, so its lineup for the day holds still until the next full load.
    public static func channels(_ definitions: [ChannelDefinition], in library: [MediaItem], fresh: [MediaItem], now: Date = .now) -> [Channel] {
        guard !fresh.isEmpty else { return channels(definitions, in: library, now: now) }
        return channels(definitions.filter { !isFresh($0) }, in: library, now: now)
            + channels(definitions.filter(isFresh), in: library + fresh, now: now)
    }

    /// Resolve definitions against the library, dropping channels with nothing to air.
    public static func channels(_ definitions: [ChannelDefinition], in library: [MediaItem], now: Date = .now) -> [Channel] {
        definitions.compactMap { d in
            let items = resolve(d, in: library, now: now)
            return items.isEmpty ? nil : Channel(definition: d, items: items)
        }
    }

    /// Convenience: automatic channels resolved. Used by tests.
    public static func channels(from items: [MediaItem], minItems: Int = 4) -> [Channel] {
        channels(automaticChannels(from: items, minItems: minItems), in: items)
    }

    public enum CandidateKind: String, CaseIterable, Sendable { case director = "Director", actor = "Actor", series = "Show marathon" }
    public struct Candidate: Hashable, Sendable { public let name: String; public let id: String?; public let count: Int
        public init(name: String, id: String?, count: Int) { self.name = name; self.id = id; self.count = count } }

    /// Names with enough in the library to fill an evening, for the "New channel" picker. Sorted by count desc, then name.
    public static func candidates(_ kind: CandidateKind, in library: [MediaItem], minItems: Int = 3) -> [Candidate] {
        var counts: [String: (id: String?, n: Int)] = [:]
        for item in library {
            switch kind {
            case .director: for d in item.directors where item.kind == .movie { counts[d, default: (nil, 0)].n += 1 }
            case .actor: for a in item.actors where item.kind == .movie { counts[a, default: (nil, 0)].n += 1 }
            case .series: if item.kind == .episode, let t = item.seriesTitle { counts[t, default: (item.seriesID, 0)].n += 1 }
            }
        }
        return counts.filter { $0.value.n >= minItems }
            .map { Candidate(name: $0.key, id: $0.value.id, count: $0.value.n) }
            .sorted { ($1.count, $0.name) < ($0.count, $1.name) }
    }

    static func decadeTag(_ genre: String, years: [Int]) -> String {
        guard let lo = years.min(), let hi = years.max() else { return genre }
        // "80s" for the 1900s, "2010s" from 2000 on, so "50s–2020s" can't be read as the 1920s.
        let d = { (y: Int) in y < 2000 ? "\(y % 100 / 10 * 10)s" : "\(y / 10 * 10)s" }
        return "\(genre), " + (lo / 10 == hi / 10 ? d(lo) : "\(d(lo))–\(d(hi))")
    }
}

/// FNV-1a 64 of a string seeding SplitMix64. Stable across processes and devices, unlike `Hasher`.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: String) { state = StableHash.fnv1a(seed) }
    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}

/// Deterministic scheduler. Same (channel, day) → identical lineup on every device, every launch. No server state.
public enum GuideGenerator {
    /// Guide grid resolution. Slots are (runtime + `pad`) rounded UP to a multiple of this.
    public static let blockLength: TimeInterval = 30 * 60
    /// Breathing room so a 28-minute episode isn't jammed into one block: ceil((runtime + 3 min) / 30 min) blocks.
    public static let pad: TimeInterval = 3 * 60

    /// Lineup tiling `day` from local midnight to the next local midnight.
    /// Pool order follows `channel.order`: shuffle = seeded shuffle (seed = channel.id + yyyy-MM-dd); inOrder/newestFirst =
    /// the channel's item order rotated by a seeded offset so consecutive days don't all start at episode 1.
    /// Repeat the pool if it runs short. If the next item doesn't fit before midnight, take the next one that does.
    /// If none fits, no program starts that can't finish: the day's last slot runs on to midnight instead, re-picked to
    /// the longest item that fits that window, and the time left over becomes its break. Only an item longer than the
    /// whole day is still cut at midnight. A short program shares its half hour with the next ones that fit (`tile`).
    /// Nothing airs twice in a row (`repeatKey`) unless the channel has nothing else; across midnight, unless nothing else
    /// fits the last slot (or the channel plays in order).
    public static func schedule(for channel: Channel, day: Date, calendar: Calendar = .current) -> [Slot] {
        guard !channel.items.isEmpty else { return [] }
        let dayStart = calendar.startOfDay(for: day)
        // Tile by time: a DST day is 23 or 25 hours, never assume 48 blocks.
        // (Start of the next day, not 24h on: where a DST change skips midnight, a day starts at 1:00.)
        let dayEnd = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: dayStart)!)
        // A day always opens with its pool's first item, so tonight's last slot can steer clear of tomorrow's opener
        // without looking at any other day's lineup. Not on a show played in order: skipping an episode at 11:30 PM
        // would break the run, and tomorrow starts somewhere else in it anyway.
        let opens = channel.order == .inOrder ? nil : repeatKey(pool(channel, dayEnd, calendar)[0])
        return tile(pool(channel, dayStart, calendar), from: dayStart, to: dayEnd, opens: opens)
    }

    /// What mustn't air twice in a row: the item, or for a film any copy of it (same title and year; a library often
    /// holds a 4K copy as a second item). A cut is part of the title, so two cuts are two films. Episodes go by item, so a show's next episode, or the
    /// next segment sharing its episode number, still follows.
    static func repeatKey(_ item: MediaItem) -> String {
        item.kind == .movie ? "film:\(item.title)|\(item.year ?? 0)" : "item:\(item.id)"
    }

    /// The day's play order, seeded by channel and date. The holiday channel's is the day's holiday's films only.
    static func pool(_ channel: Channel, _ day: Date, _ device: Calendar) -> [MediaItem] {
        // The date as Gregorian, as Android and the web read it, whatever calendar the device uses (Buddhist, Hebrew...).
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = device.timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        var rng = SeededGenerator(seed: channel.id + String(format: "|%04d-%02d-%02d", c.year!, c.month!, c.day!))
        let items = channel.definition.rule.contains(.holiday) ? Holiday.pick(channel.items, on: day, calendar: calendar).films : channel.items
        switch channel.order {
        case .shuffle: return items.shuffled(using: &rng)
        case .inOrder, .newestFirst:
            let r = Int(rng.next() % UInt64(items.count))
            return Array(items[r...] + items[..<r])
        }
    }

    /// Tiles [start, end) from `pool` as `schedule` describes, opening with `pool[0]`. `opens`: the `repeatKey` of what
    /// airs right after `end`, which the last slot avoids when something else fits.
    static func tile(_ pool: [MediaItem], from start: Date, to end: Date, opens: String?) -> [Slot] {
        var slots: [Slot] = []
        var cursor = start
        var next = 0
        while cursor < end {
            let previous = slots.last.map { repeatKey($0.item) }
            var pick: Int?, again: Int?
            for k in 0..<pool.count {
                let i = (next + k) % pool.count
                let slotEnd = cursor.addingTimeInterval(slotLength(pool[i]))
                guard slotEnd <= end else { continue }
                let key = repeatKey(pool[i])
                if slots.isEmpty || key != previous && (slotEnd < end || key != opens) { pick = i; break }
                if again == nil { again = i }
            }
            // Only the same thing again fits: fine on a channel with nothing else that could air today (one film, or
            // copies of it). Otherwise it's the end of the day, below.
            let day = end.timeIntervalSince(start)
            if pick == nil, let again, !pool.contains(where: { repeatKey($0) != previous && slotLength($0) <= day }) { pick = again }
            guard let pick else {
                if var last = slots.popLast() {
                    // A half hour of short programs goes as a whole, so the re-picked slot starts on the half-hour grid.
                    while last.start.timeIntervalSince(start).truncatingRemainder(dividingBy: blockLength) != 0, let p = slots.popLast() { last = p }
                    let window = end.timeIntervalSince(last.start)
                    var best = last.item   // fits by construction; a longer one that also fits leaves a shorter break
                    if let before = slots.last.map({ repeatKey($0.item) }) {   // (the day's opener itself never changes)
                        // The longest that fits and repeats neither the slot before nor tomorrow's opener.
                        func ok(_ it: MediaItem) -> Bool { repeatKey(it) != before && repeatKey(it) != opens }
                        var found = ok(last.item) ? last.item : nil
                        for k in 0..<pool.count {
                            let it = pool[(next + k) % pool.count]
                            if slotLength(it) <= window, slotLength(it) > found.map(slotLength) ?? 0, ok(it) { found = it }
                        }
                        best = found ?? last.item
                    }
                    slots.append(Slot(item: best, start: last.start, end: end))
                } else {
                    slots.append(Slot(item: pool[next], start: cursor, end: end))   // longer than the whole day
                }
                break
            }
            let slotEnd = cursor.addingTimeInterval(slotLength(pool[pick]))
            // A short program (15 minutes or less: half its half hour, the pad not counted) doesn't leave the rest of it empty: the next ones in order that
            // fit play right after it, each in its own slot, the way cartoon blocks did. Nothing crosses the half hour.
            var parts = [pool[pick]], used = partLength(pool[pick])
            next = (pick + 1) % pool.count
            if pool[pick].runtime <= slotEnd.timeIntervalSince(cursor) / 2 {
                while pool.count > 1 {
                    let it = pool[next]
                    guard used + partLength(it) <= slotEnd.timeIntervalSince(cursor), !parts.contains(where: { $0.id == it.id }),
                          repeatKey(it) != repeatKey(parts[parts.count - 1]), slotEnd < end || repeatKey(it) != opens else { break }
                    parts.append(it); used += partLength(it); next = (next + 1) % pool.count
                }
            }
            for (n, it) in parts.enumerated() {   // the last one keeps whatever is left of the half hour as its break
                let partEnd = n == parts.count - 1 ? slotEnd : cursor.addingTimeInterval(partLength(it))
                slots.append(Slot(item: it, start: cursor, end: partEnd))
                cursor = partEnd
            }
        }
        return slots
    }

    /// A packed program's slot: its runtime in whole seconds, so the next one starts as it ends (no break in between).
    static func partLength(_ item: MediaItem) -> TimeInterval { max(1, item.runtime.rounded(.down)) }

    /// Slots on `channel` intersecting [from, to]. Spans days as needed.
    public static func schedule(for channel: Channel, from: Date, to: Date, calendar: Calendar = .current) -> [Slot] {
        var slots: [Slot] = []
        var day = calendar.startOfDay(for: from)
        while day < to {
            slots += schedule(for: channel, day: day, calendar: calendar)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return slots.filter { $0.end > from && $0.start < to }
    }

    /// The slot containing `time` on `channel`.
    public static func slot(on channel: Channel, at time: Date, calendar: Calendar = .current) -> Slot? {
        schedule(for: channel, day: time, calendar: calendar).first { $0.start <= time && time < $0.end }
    }

    /// The slot by its exact start (what `ProgramKey` stores), if the generator still produces it.
    /// Sub-second tolerance so a start that went through JSON (persisted key) still matches.
    public static func slot(on channel: Channel, startingAt start: Date, calendar: Calendar = .current) -> Slot? {
        schedule(for: channel, day: start, calendar: calendar).first { abs($0.start.timeIntervalSince(start)) < 1 }
    }

    /// later: before start · live: item playing · break: item over, slot not · past: slot over.
    public static func status(of slot: Slot, at time: Date) -> ProgramStatus {
        if time < slot.start { return .later }
        if time >= slot.end { return .past }
        return time >= slot.itemEnd ? .break : .live
    }

    public static func slotLength(_ item: MediaItem) -> TimeInterval {
        // Channel 99's programs fill their slots exactly: no pad, so the scramble never drops into a station break.
        let padded = item.id.hasPrefix(Channel.scrambledID) ? item.runtime : item.runtime + pad
        return max(1, (padded / blockLength).rounded(.up)) * blockLength
    }
}

/// The holiday channel's calendar (US holidays). Each day airs the films of the nearest holiday that has at least
/// `minFilms` of them: the one whose season the day falls in (all October is Halloween, Christmas runs from the day after
/// Thanksgiving), else the one whose season is closest. Groundhog Day is the one-day exception: the film, back to back.
public enum Holiday: String, CaseIterable, Sendable {
    case newYear = "New Year’s", valentines = "Valentine’s Day", stPatricks = "St. Patrick’s Day", easter = "Easter",
         july4 = "Fourth of July", halloween = "Halloween", thanksgiving = "Thanksgiving", christmas = "Christmas"

    /// Fewer and the holiday sits the year out: four films are about as few as a day can repeat.
    public static let minFilms = 4
    public static let groundhogDay = "Groundhog Day"

    /// Days before the holiday that its season starts. Where two seasons overlap, the nearer holiday has the day.
    var lead: Int {
        switch self {
        case .newYear: 6            // from the day after Christmas
        case .valentines: 13
        case .stPatricks, .easter, .july4: 7
        case .halloween: 30         // all October
        case .thanksgiving: 27      // all November up to it, even on the 28th
        case .christmas: 33         // from the day after Thanksgiving, the 22nd at the earliest
        }
    }

    /// Its month and day in `year`.
    func date(in year: Int) -> (month: Int, day: Int) {
        switch self {
        case .newYear: (1, 1)
        case .valentines: (2, 14)
        case .stPatricks: (3, 17)
        case .easter: Self.easter(year)
        case .july4: (7, 4)
        case .halloween: (10, 31)
        case .thanksgiving: (11, 22 + (11 - Self.weekday(year, 11, 1)) % 7)   // the fourth Thursday
        case .christmas: (12, 25)
        }
    }

    /// Word starts in a film's title or overview that make it this holiday's (as `ChannelBuilder.mentions` reads them).
    var words: [String] {
        switch self {
        case .newYear: ["new year", "auld lang syne"]
        case .valentines: ["valentine"]
        case .stPatricks: ["st. patrick", "st patrick", "saint patrick", "leprechaun", "ireland"]
        case .easter: ["easter bunny", "easter egg", "easter parade", "easter sunday", "jesus", "ten commandments", "ben-hur"]
        case .july4: ["fourth of july", "4th of july", "july 4", "july fourth", "independence day"]
        case .halloween: ["halloween", "trick or treat", "trick-or-treat"]
        case .thanksgiving: ["thanksgiving"]
        case .christmas: ["christmas", "xmas", "santa claus", "north pole", "yuletide", "scrooge", "grinch", "nutcracker", "kris kringle", "reindeer"]
        }
    }

    /// Genres that make a film this holiday's: a date for Valentine's, a scare for Halloween (not a kids' one: `.genre`).
    var genres: [String] {
        switch self {
        case .valentines: ["Romance"]
        case .halloween: ["Horror"]
        default: []
        }
    }

    /// A film for this holiday.
    func has(_ item: MediaItem) -> Bool {
        item.kind == .movie && (ChannelBuilder.mentions(item, any: words) || genres.contains { ChannelBuilder.matches(.genre($0), item) })
    }

    /// Groundhog Day's own film, by its title, any cut of it ("Groundhog Day (Remastered)": `MediaItem.title(_:edition:)`).
    static func isGroundhogDay(_ item: MediaItem) -> Bool {
        let t = item.title.lowercased()
        return item.kind == .movie && (t == "groundhog day" || t.hasPrefix("groundhog day ("))
    }

    /// What the holiday channel airs on `day`, and its holiday's name: on February 2 the film Groundhog Day if `films` has
    /// it, else the nearest holiday's films. All of `films` if no holiday has `minFilms` (then there is no channel).
    static func pick(_ films: [MediaItem], on day: Date, calendar: Calendar) -> (name: String, films: [MediaItem]) {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        if c.month == 2, c.day == 2 {
            let g = films.filter(isGroundhogDay)
            if !g.isEmpty { return (groundhogDay, g) }
        }
        let y = c.year!, today = dayNumber(y, c.month!, c.day!)
        // In its season (0), else how far from it; then the nearer holiday (halfway between two seasons, the one just gone:
        // its season ends on its day). No two holidays tie, so nearest first and the first with enough films has the day:
        // only the holidays tried get their films sorted out.
        func key(_ h: Holiday) -> (Int, Int) {
            (y - 1...y + 1).map { year in
                let (m, d) = h.date(in: year), at = dayNumber(year, m, d), start = at - h.lead
                return (today < start ? start - today : max(0, today - at), abs(at - today))
            }.min { $0 < $1 }!
        }
        for h in allCases.sorted(by: { key($0) < key($1) }) {
            let mine = films.filter(h.has)
            if mine.count >= minFilms { return (h.rawValue, mine) }
        }
        return ("Holiday", films)
    }

    /// Days from 1970-01-01 to a calendar date (Howard Hinnant's days_from_civil): plain arithmetic, the same on every platform.
    static func dayNumber(_ y: Int, _ m: Int, _ d: Int) -> Int {
        let yy = m <= 2 ? y - 1 : y, era = (yy >= 0 ? yy : yy - 399) / 400, yoe = yy - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        return era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468
    }

    /// 0 = Sunday (1970-01-01 was a Thursday).
    static func weekday(_ y: Int, _ m: Int, _ d: Int) -> Int { ((dayNumber(y, m, d) + 4) % 7 + 7) % 7 }

    /// Western Easter Sunday (the anonymous Gregorian algorithm).
    static func easter(_ y: Int) -> (month: Int, day: Int) {
        let a = y % 19, b = y / 100, c = y % 100, d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30, i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = (a + 11 * h + 22 * l) / 451
        let n = h + l - 7 * m + 114
        return (n / 31, n % 31 + 1)
    }
}
