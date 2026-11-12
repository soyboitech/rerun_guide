' Port of web/src/core/Models.ts. Objects are plain AAs with the TS field names and null as invalid, built by the *_new
' functions. Two names differ: a Slot's `end` is `finish`, and a years chip's from/to are `yearFrom`/`yearTo` (END and TO
' are BrightScript keywords). A Channel copies its definition's fields (id, number, name, ...) next to `definition`:
' definitions are never changed in place, only replaced (ChannelDefinition_copy), and a new Channel built from them.

' MediaItem(p): p is an AA with the TS MediaItemInit fields (id, kind, title, runtime required).
function MediaItem_new(p as Object) as Object
    it = {
        id: p.id, kind: p.kind, title: p.title, seriesTitle: p.seriesTitle, seriesID: p.seriesID,
        season: p.season, episode: p.episode, year: p.year, genres: p.genres, runtime: p.runtime * 1#,
        artworkPath: p.artworkPath, backdropPath: p.backdropPath, overview: p.overview, contentRating: p.contentRating,
        directors: p.directors, actors: p.actors, libraryID: p.libraryID, addedAt: p.addedAt, watched: isTrue(p.watched)
    }
    if it.genres = invalid then it.genres = []
    if it.directors = invalid then it.directors = []
    if it.actors = invalid then it.actors = []
    if it.addedAt <> invalid then it.addedAt = it.addedAt * 1#
    return it
end function

' A copy with `changes` (an AA of fields) applied.
function MediaItem_copy(it as Object, changes as Object) as Object
    c = {}
    c.Append(it)
    c.Append(changes)
    return c
end function

' Guide-cell headline: series name for episodes, title for movies.
function MediaItem_displayTitle(it as Object) as String
    if it.kind = "episode" and it.seriesTitle <> invalid then return it.seriesTitle
    return it.title
end function

' "S5 E9" or "".
function MediaItem_seasonEpisode(it as Object) as String
    parts = []
    if it.season <> invalid then parts.Push("S" + iStr(it.season))
    if it.episode <> invalid then parts.Push("E" + iStr(it.episode))
    return parts.Join(" ")
end function

' Guide-cell second line: episode title for episodes, year for movies.
function MediaItem_subtitle(it as Object) as String
    if it.kind = "episode" then return it.title
    if it.year <> invalid then return iStr(it.year)
    return ""
end function

' Info-panel sub line. Episodes: "Episode" · S5 E9 · 1986. Movies: 1981 · PG · 115 min.
function MediaItem_infoLine(it as Object) as String
    parts = []
    if it.kind = "episode" then
        parts.Push("“" + it.title + "”")
        se = MediaItem_seasonEpisode(it)
        if se <> "" then parts.Push(se)
        if it.year <> invalid then parts.Push(iStr(it.year))
    else
        if it.year <> invalid then parts.Push(iStr(it.year))
        if it.contentRating <> invalid then parts.Push(it.contentRating)
        parts.Push(iStr(Fix(it.runtime / 60)) + " min")
    end if
    return parts.Join(" · ")
end function

' A film's title with its cut, "Watchmen (Directors Cut)".
function MediaItem_title(title as String, edition as Dynamic) as String
    if edition = invalid then return title
    e = edition.Trim()
    if e = "" then return title
    return title + " (" + e + ")"
end function

' Keys as Swift's synthesized Codable; dates as epoch seconds; nulls omitted.
function MediaItem_toJson(it as Object) as Object
    o = {id: it.id, kind: it.kind, title: it.title}
    for each k in ["seriesTitle", "seriesID", "season", "episode", "year"]
        if it[k] <> invalid then o[k] = it[k]
    end for
    o.genres = it.genres
    o.runtime = it.runtime
    for each k in ["artworkPath", "backdropPath", "overview", "contentRating"]
        if it[k] <> invalid then o[k] = it[k]
    end for
    o.directors = it.directors
    o.actors = it.actors
    if it.libraryID <> invalid then o["libraryID"] = it.libraryID
    if it.addedAt <> invalid then o["addedAt"] = it.addedAt
    o.watched = it.watched
    return o
end function

' Invalid for a shape that isn't an item (an older cache: the caller refetches).
function MediaItem_fromJson(o as Dynamic) as Dynamic
    if type(o) <> "roAssociativeArray" then return invalid
    if o.id = invalid or o.title = invalid or o.runtime = invalid or o.watched = invalid then return invalid
    if o.kind <> "movie" and o.kind <> "episode" then return invalid
    return MediaItem_new(o)
end function

' ---- PlayOrder: "shuffle" | "inOrder" | "newestFirst" ----

function PlayOrder_rawValue(o as String) as String
    if o = "inOrder" then return "In order"
    if o = "newestFirst" then return "Newest first"
    return "Shuffle"
end function

function PlayOrder_next(o as String) as String
    if o = "shuffle" then return "inOrder"
    if o = "inOrder" then return "newestFirst"
    return "shuffle"
end function

function PlayOrder_from(raw as Dynamic) as Dynamic
    for each o in ["shuffle", "inOrder", "newestFirst"]
        if PlayOrder_rawValue(o) = raw then return o
    end for
    return invalid
end function

' ---- RuleChip: one criterion of a channel's rule; a channel airs the items matching EVERY chip ----

function RuleChip_genre(value as String) as Object
    return {kind: "genre", value: value}
end function

function RuleChip_years(yearFrom as Integer, yearTo as Integer) as Object
    return {kind: "years", yearFrom: yearFrom, yearTo: yearTo}
end function

function RuleChip_director(name as String) as Object
    return {kind: "director", name: name}
end function

function RuleChip_actor(name as String) as Object
    return {kind: "actor", name: name}
end function

function RuleChip_series(id as String, title as String) as Object
    return {kind: "series", id: id, title: title}
end function

function RuleChip_year(value as Integer) as Object
    return {kind: "year", value: value}
end function

function RuleChip_movies() as Object
    return {kind: "movies"}
end function

function RuleChip_tv() as Object
    return {kind: "tv"}
end function

function RuleChip_addedWithin(days as Integer) as Object
    return {kind: "addedWithin", days: days}
end function

function RuleChip_anyGenre(genres as Object) as Object
    return {kind: "anyGenre", genres: genres}
end function

function RuleChip_keywords(words as Object) as Object
    return {kind: "keywords", words: words}
end function

function RuleChip_unwatched() as Object
    return {kind: "unwatched"}
end function

function RuleChip_holiday() as Object
    return {kind: "holiday"}
end function

' Chip text as shown in the channel editor: "Genre: Sitcom", "1975–1999", "Director: Steven Spielberg", "TV".
function RuleChip_label(c as Object) as String
    k = c.kind
    if k = "genre" then return "Genre: " + c.value
    if k = "years" then
        if c.yearFrom <= 1900 then return "Before " + iStr(c.yearTo + 1)
        return iStr(c.yearFrom) + "–" + iStr(c.yearTo)
    end if
    if k = "director" then return "Director: " + c.name
    if k = "actor" then return "Actor: " + c.name
    if k = "series" then return "Show: " + c.title
    if k = "year" then return "Year: " + iStr(c.value)
    if k = "movies" then return "Movies"
    if k = "tv" then return "TV"
    if k = "addedWithin" then return "Added in the last " + iStr(c.days) + " days"
    if k = "anyGenre" then return "Genre: " + c.genres.Join(" / ")
    if k = "keywords" then
        s = "Mentions: " + prefix(c.words, 4).Join(", ")
        if c.words.Count() > 4 then s = s + "…"
        return s
    end if
    if k = "unwatched" then return "Unwatched"
    return "Nearest holiday"
end function

' Swift's synthesized enum Codable shape: {"genre":{"_0":"Comedy"}}, {"series":{"id":…,"title":…}}, {"movies":{}}.
function RuleChip_toJson(c as Object) as Object
    k = c.kind
    v = {}
    if k = "genre" then
        v._0 = c.value
    else if k = "years" then
        v._0 = c.yearFrom
        v._1 = c.yearTo
    else if k = "director" or k = "actor" then
        v._0 = c.name
    else if k = "series" then
        v.id = c.id
        v.title = c.title
    else if k = "year" then
        v._0 = c.value
    else if k = "addedWithin" then
        v.days = c.days
    else if k = "anyGenre" then
        v._0 = c.genres
    else if k = "keywords" then
        v._0 = c.words
    end if
    o = {}
    o[k] = v
    return o
end function

' Invalid for an unknown case.
function RuleChip_fromJson(o as Object) as Dynamic
    for each k in o
        v = o[k]
        if type(v) <> "roAssociativeArray" then return invalid
        if k = "genre" then return RuleChip_genre(v._0)
        if k = "years" then return RuleChip_years(v._0, v._1)
        if k = "director" then return RuleChip_director(v._0)
        if k = "actor" then return RuleChip_actor(v._0)
        if k = "series" then return RuleChip_series(v.id, v.title)
        if k = "year" then return RuleChip_year(v._0)
        if k = "movies" then return RuleChip_movies()
        if k = "tv" then return RuleChip_tv()
        if k = "addedWithin" then return RuleChip_addedWithin(v.days)
        if k = "anyGenre" then return RuleChip_anyGenre(v._0)
        if k = "keywords" then return RuleChip_keywords(v._0)
        if k = "unwatched" then return RuleChip_unwatched()
        if k = "holiday" then return RuleChip_holiday()
        return invalid
    end for
    return invalid
end function

' ---- ChannelDefinition: what a channel IS, independent of the library contents ----

' p: {id, number, name, tag, rule} and optionally order ("shuffle"), trailerBreaks (true), isCustom (false), tuneMode.
function ChannelDefinition_new(p as Object) as Object
    d = {id: p.id, number: p.number, name: p.name, tag: p.tag, rule: p.rule, order: p.order, trailerBreaks: p.trailerBreaks,
         isCustom: isTrue(p.isCustom), tuneMode: p.tuneMode}
    if d.order = invalid then d.order = "shuffle"
    if d.trailerBreaks = invalid then d.trailerBreaks = true
    return d
end function

function ChannelDefinition_copy(d as Object, changes as Object) as Object
    c = {}
    c.Append(d)
    c.Append(changes)
    return c
end function

' Stable 0..<360 hue for gradients, from the id.
function ChannelDefinition_hue(d as Object) as Integer
    return U64_mod(StableHash_fnv1a(d.id), 360)
end function

function ChannelDefinition_hasChip(d as Object, kind as String) as Boolean
    for each c in d.rule
        if c.kind = kind then return true
    end for
    return false
end function

function ChannelDefinition_toJson(d as Object) as Object
    rule = []
    for each c in d.rule
        rule.Push(RuleChip_toJson(c))
    end for
    o = {id: d.id, number: d.number, name: d.name, tag: d.tag, rule: rule, order: PlayOrder_rawValue(d.order),
         trailerBreaks: d.trailerBreaks, isCustom: d.isCustom}
    if d.tuneMode <> invalid then o["tuneMode"] = d.tuneMode
    return o
end function

function ChannelDefinition_fromJson(o as Object) as Dynamic
    if o.id = invalid then return invalid
    rule = []
    if type(o.rule) = "roArray" then
        for each c in o.rule
            if type(c) = "roAssociativeArray" then
                chip = RuleChip_fromJson(c)
                if chip = invalid then return invalid
                rule.Push(chip)
            end if
        end for
    end if
    number = o.number
    if number = invalid then number = 0
    name = o.name
    if name = invalid then name = ""
    tag = o.tag
    if tag = invalid then tag = ""
    tm = o.tuneMode
    if tm <> "live" and tm <> "start" then tm = invalid
    return ChannelDefinition_new({id: o.id, number: number, name: name, tag: tag, rule: rule, order: PlayOrder_from(o.order),
        trailerBreaks: not isFalse(o.trailerBreaks), isCustom: isTrue(o.isCustom), tuneMode: tm})
end function

' ---- Channel: a guide row, a definition plus the library items it resolved to ----

function Channel_new(d as Object, items as Object) as Object
    movies = 0
    for each it in items
        if it.kind = "movie" then movies = movies + 1
    end for
    return {definition: d, items: items, isMovies: movies * 2 >= items.Count(), id: d.id, number: d.number, name: d.name,
            tag: d.tag, order: d.order, trailerBreaks: d.trailerBreaks, isCustom: d.isCustom, isScrambled: d.id = "scrambled"}
end function

' Kotlin's convenience constructor, for tests and channel 99: a plain genre-style channel.
function Channel_make(id as String, number as Integer, name as String, items as Object, tag = "" as String, order = "shuffle" as String) as Object
    return Channel_new(ChannelDefinition_new({id: id, number: number, name: name, tag: tag, rule: [], order: order}), items)
end function

' Channel 99: the one every cable box had that nobody could quite make out. Its programs are stand-ins the app never
' asks the server for; the picture is the scramble itself.
function Channel_scrambled() as Object
    g = GetGlobalAA()
    if g.scrambledChannel = invalid then
        titles = ["Late Night Feature", "Mystery Matinee", "After Hours Special", "Double Feature", "Feature Presentation", "Encore Showing"]
        items = []
        for i = 0 to titles.Count() - 1
            ' Exactly an hour: the scheduler skips its pad for these, so the picture never drops into a station break.
            items.Push(MediaItem_new({id: "scrambled-" + iStr(i), kind: "movie", title: titles[i], year: 1986 + i, runtime: 3600,
                overview: "Nothing comes in clearly on 99.", contentRating: "NR"}))
        end for
        d = ChannelDefinition_new({id: "scrambled", number: 99, name: "Channel 99", tag: "Scrambled", rule: [], order: "shuffle",
            trailerBreaks: false})
        g.scrambledChannel = Channel_new(d, items)
    end if
    return g.scrambledChannel
end function

' ---- Slot: one guide cell, an item airing between `start` and `finish` ----

function Slot_new(item as Object, start as Double, finish as Double) as Object
    return {item: item, start: start, finish: finish}
end function

function Slot_id(s as Object) as String
    return s.item.id + "@" + iStr(Fix(s.start))
end function

' When the item itself stops playing and the break begins.
function Slot_itemEnd(s as Object) as Double
    return minD(s.finish, s.start + s.item.runtime)
end function

' ---- StableHash and SeededGenerator: FNV-1a 64 of a string seeding SplitMix64, the same on every device ----

' 64-bit FNV-1a over the UTF-8 bytes.
function StableHash_fnv1a(s as String) as LongInteger
    ba = CreateObject("roByteArray")
    ba.FromAsciiString(s)
    h = &hCBF29CE484222325&
    n = ba.Count()
    for i = 0 to n - 1
        b = ba[i] + 0&
        h = ((h or b) and not (h and b)) * &h100000001B3&
    end for
    return h
end function

function SeededGenerator(seed as String) as Object
    ' Kotlin `next()` is `nextRaw` here: NEXT is a keyword.
    return {state: StableHash_fnv1a(seed), nextRaw: SeededGenerator_next, nextBelow: SeededGenerator_nextBelow, nextInt: SeededGenerator_nextInt}
end function

' SplitMix64.
function SeededGenerator_next() as LongInteger
    s = m.state + &h9E3779B97F4A7C15&
    m.state = s
    z = s
    if z >= 0 then t = z \ 1073741824& else t = ((z and &h7FFFFFFFFFFFFFFF&) \ 1073741824&) + 8589934592&   ' z >>> 30
    z = ((z or t) and not (z and t)) * &hBF58476D1CE4E5B9&
    if z >= 0 then t = z \ 134217728& else t = ((z and &h7FFFFFFFFFFFFFFF&) \ 134217728&) + 68719476736&     ' z >>> 27
    z = ((z or t) and not (z and t)) * &h94D049BB133111EB&
    if z >= 0 then t = z \ 2147483648& else t = ((z and &h7FFFFFFFFFFFFFFF&) \ 2147483648&) + 4294967296&   ' z >>> 31
    return (z or t) and not (z and t)
end function

' Swift's RandomNumberGenerator.next(upperBound:), Lemire's nearly divisionless method: the same draws, the same result.
' 0 < bound < 2^31.
function SeededGenerator_nextBelow(bound as LongInteger) as LongInteger
    r = U64_mulBound(m.nextRaw(), bound)
    if U64_less(r[1], bound) then
        ' (0 - bound) mod bound, which is 2^64 mod bound: (2^32 mod bound)^2 mod bound.
        q = 4294967296& mod bound
        t = q * q mod bound
        while U64_less(r[1], t)
            r = U64_mulBound(m.nextRaw(), bound)
        end while
    end if
    return r[0]
end function

' Swift's Int.random(in: 0..<until, using:).
function SeededGenerator_nextInt(until as Integer) as Integer
    return m.nextBelow(until)
end function

' Swift's shuffled(using:): Fisher-Yates front to back, each swap partner from Int.random(in: 0..<remaining).
function shuffled(list as Object, using as Object) as Object
    result = []
    result.Append(list)
    amount = result.Count()
    i = 0
    while amount > 1
        r = using.nextInt(amount)
        amount = amount - 1
        t = result[i]
        result[i] = result[i + r]
        result[i + r] = t
        i = i + 1
    end while
    return result
end function
