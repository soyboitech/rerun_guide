' Port of web/src/core/GuideGenerator.ts: ChannelBuilder, the deterministic scheduler and Holiday. Same names with the
' module as a prefix (ChannelBuilder_automaticChannels, GuideGenerator_scheduleLineup, Holiday_pick). The calendar is the
' device's time zone (Time.brs). Every Map keyed by library data is a case-sensitive AA (newMap).

' ---- ChannelBuilder: turns a flat library into channel definitions and resolves definitions back into items ----

' Genre (lowercased) -> [films name, films descriptor, TV name, TV descriptor, mixed name, mixed descriptor].
function ChannelBuilder_retroTable() as Object
    g = GetGlobalAA()
    if g.cbRetroTable <> invalid then return g.cbRetroTable
    rows = [
        ["action", "Adrenaline", "Action films", "Stunt Hour", "Action TV", "Adrenaline", "Action"],
        ["action & adventure", "Thrill Ride", "Action & adventure films", "Thrill Ride", "Action & adventure TV", "Thrill Ride", "Action & adventure"],
        ["adventure", "The Matinee", "Adventure films", "Wide World", "Adventure TV", "The Matinee", "Adventure"],
        ["animation", "The Big Cartoon", "Animated films", "Toon Block", "Cartoons", "Toon Block", "Animation"],
        ["anime", "Anime Features", "Anime films", "Anime Block", "Anime", "Anime Block", "Anime"],
        ["biography", "Life Stories", "Biopics", "Portraits", "Biographies", "Life Stories", "Biographies"],
        ["children", "Kids’ Matinee", "Kids’ films", "After School", "Kids’ TV", "After School", "Kids"],
        ["kids", "Kids’ Matinee", "Kids’ films", "After School", "Kids’ TV", "After School", "Kids"],
        ["comedy", "Funny Business", "Comedy films", "Studio Audience", "Sitcoms", "Studio Audience", "Comedy"],
        ["crime", "Mean Streets", "Crime films", "Gumshoe", "Detectives", "Gumshoe", "Crime"],
        ["documentary", "True Stories", "Documentaries", "Field Notes", "Documentary TV", "True Stories", "Documentaries"],
        ["drama", "The Picture Show", "Drama films", "Prime Time", "Drama series", "Prime Time", "Drama"],
        ["family", "Family Hour", "Family films", "Family Room", "Family TV", "Family Hour", "Family"],
        ["fantasy", "Once Upon", "Fantasy films", "The Realm", "Fantasy TV", "Once Upon", "Fantasy"],
        ["food", "Dinner Bell", "Food", "Dinner Bell", "Food TV", "Dinner Bell", "Food"],
        ["game show", "Game Night", "Game shows", "Game Night", "Game shows", "Game Night", "Game shows"],
        ["history", "Days Gone By", "History films", "The Archive", "History TV", "Days Gone By", "History"],
        ["holiday", "Yule Log", "Holiday films", "Tinsel Time", "Holiday TV", "Yule Log", "Holiday"],
        ["home and garden", "Open House", "Home & garden", "Open House", "Home & garden", "Open House", "Home & garden"],
        ["horror", "Fright Night", "Horror films", "Chiller", "Horror TV", "Fright Night", "Horror"],
        ["martial arts", "Kung Fu Theater", "Martial arts", "Kung Fu Theater", "Martial arts", "Kung Fu Theater", "Martial arts"],
        ["mini-series", "The Miniseries", "Mini-series", "The Miniseries", "Mini-series", "The Miniseries", "Mini-series"],
        ["music", "The Jukebox", "Music films", "Video Hour", "Music TV", "The Jukebox", "Music"],
        ["musical", "Showtunes", "Musicals", "Showtunes", "Musicals", "Showtunes", "Musicals"],
        ["mystery", "Whodunit", "Mystery films", "Case Files", "Mystery TV", "Whodunit", "Mysteries"],
        ["news", "Newsroom", "News", "Newsroom", "News", "Newsroom", "News"],
        ["reality", "Real Life", "Reality TV", "Real Life", "Reality TV", "Real Life", "Reality TV"],
        ["romance", "Date Night", "Romance films", "Love Lines", "Romance TV", "Date Night", "Romance"],
        ["sci-fi", "Final Frontier", "Sci-fi films", "Space Age", "Sci-fi TV", "Space Age", "Sci-fi"],
        ["science fiction", "Final Frontier", "Sci-fi films", "Space Age", "Sci-fi TV", "Space Age", "Sci-fi"],
        ["soap", "Daytime", "Soaps", "Daytime", "Soaps", "Daytime", "Soaps"],
        ["sport", "Game Day", "Sports films", "Sports Desk", "Sports TV", "Game Day", "Sports"],
        ["sports", "Game Day", "Sports films", "Sports Desk", "Sports TV", "Game Day", "Sports"],
        ["superhero", "Capes & Cowls", "Superhero films", "Secret Identity", "Superhero TV", "Capes & Cowls", "Superheroes"],
        ["suspense", "Nail Biter", "Suspense films", "Held Breath", "Suspense TV", "Nail Biter", "Suspense"],
        ["talk show", "Late Night", "Talk shows", "Late Night", "Talk shows", "Late Night", "Talk shows"],
        ["thriller", "Edge of Your Seat", "Thrillers", "Cliffhanger", "Thriller TV", "Edge of Your Seat", "Thrillers"],
        ["travel", "Passport", "Travel films", "Road Trip", "Travel TV", "Passport", "Travel"],
        ["war", "The Front", "War films", "War Room", "War TV", "The Front", "War"],
        ["western", "Dusty Trails", "Westerns", "The Frontier", "Western TV", "Dusty Trails", "Westerns"]
    ]
    t = newMap()
    for each r in rows
        t[r[0]] = r
    end for
    g.cbRetroTable = t
    return t
end function

function CB_yearsOf(items as Object) as Object
    out = []
    for each i in items
        if i.year <> invalid then out.Push(i.year)
    end for
    return out
end function

function CB_min(a as Object) as Integer
    v = a[0]
    for each x in a
        if x < v then v = x
    end for
    return v
end function

function CB_max(a as Object) as Integer
    v = a[0]
    for each x in a
        if x > v then v = x
    end for
    return v
end function

function CB_def(id as String, name as String, tag as String, rule as Object, order = "shuffle" as String) as Object
    return ChannelDefinition_new({id: id, number: 0, name: name, tag: tag, rule: rule, order: order})
end function

' Items of `library` matching every chip of `rule`.
function CB_filter(library as Object, rule as Object, now as Double) as Object
    out = []
    for each i in library
        ok = true
        for each c in rule
            if not ChannelBuilder_matches(c, i, now) then
                ok = false
                exit for
            end if
        end for
        if ok then out.Push(i)
    end for
    return out
end function

function CB_ofKind(items as Object, kind as String) as Object
    out = []
    for each it in items
        if it.kind = kind then out.Push(it)
    end for
    return out
end function

function CB_bump(counts as Object, keys as Object, k as String)
    c = counts[k]
    if c = invalid then
        counts[k] = 1
        keys.Push(k)
    else
        counts[k] = c + 1
    end if
end function

function CB_byCountThenName(a as Object, b as Object, ctx as Dynamic) as Integer
    if a.count <> b.count then return b.count - a.count
    return swiftCompare(a.name, b.name)
end function

function CB_byCountThenYear(a as Object, b as Object, ctx as Dynamic) as Integer
    if a.count <> b.count then return b.count - a.count
    return compareValues(a.year, b.year)
end function

function CB_byID(a as Object, b as Object, ctx as Dynamic) as Integer
    return swiftCompare(a.id, b.id)
end function

' The names with at least minItems films, most first (ties by name), at most maxPeople.
function CB_top(counts as Object, keys as Object, minItems as Integer, maxPeople as Integer) as Object
    entries = []
    for each k in keys
        if counts[k] >= minItems then entries.Push({name: k, count: counts[k]})
    end for
    out = []
    for each e in prefix(stableSort(entries, CB_byCountThenName), maxPeople)
        out.Push(e.name)
    end for
    return out
end function

' The automatic channel lineup. Up front, when the library has enough for them: New Releases, New This Season, Just
' Added, Unwatched, Fresh Episodes, then the classic channels. After that every genre, theme, marathon, director, actor and
' year channel, scattered with a fixed seed so the lineup feels like cable yet is identical on every device. No channel
' mixes films and TV. Only the biggest groups make the lineup (maxSeries marathons, maxPeople directors and actors, 3 years).
function ChannelBuilder_automaticChannels(library as Object, minItems = 4 as Integer, maxSeries = 24 as Integer, maxPeople = 12 as Integer, now = invalid as Dynamic) as Object
    if now = invalid then now = Time_now()
    year = Time_localYear(now)
    lastYear = iStr(year - 1) + "–" + iStr(year)
    leads = [
        ["lead:new-movies", "New Releases", "Films from " + lastYear, [RuleChip_years(year - 1, year), RuleChip_movies()], "newestFirst"],
        ["lead:new-tv", "New This Season", "TV from " + lastYear, [RuleChip_years(year - 1, year), RuleChip_tv()], "shuffle"],
        ["lead:just-added", "Just Added", "Films new on the server", [RuleChip_addedWithin(60), RuleChip_movies()], "shuffle"],
        ["lead:unwatched", "Unwatched", "Films you haven’t seen", [RuleChip_unwatched(), RuleChip_movies()], "shuffle"],
        ["lead:just-added-tv", "Fresh Episodes", "TV new on the server", [RuleChip_addedWithin(60), RuleChip_tv()], "shuffle"],
        ["lead:classic-tv", "Front Porch", "Classic TV, before 1970", [RuleChip_years(1900, 1969), RuleChip_tv()], "shuffle"],
        ["lead:classic-movies", "The Vault", "Classic films, before 1970", [RuleChip_years(1900, 1969), RuleChip_movies()], "shuffle"]
    ]
    lead = []
    for each l in leads
        if CB_filter(library, l[3], now).Count() >= minItems then lead.Push(CB_def(l[0], l[1], l[2], l[3], l[4]))
    end for

    byGenre = newMap()
    genreKeys = []
    bySeries = newMap()
    seriesKeys = []
    byDirector = newMap()
    directorKeys = []
    byActor = newMap()
    actorKeys = []
    byYear = newMap()
    yearKeys = []
    for each item in library
        for each gn in item.genres
            lst = byGenre[gn]
            if lst = invalid then
                lst = []
                byGenre[gn] = lst
                genreKeys.Push(gn)
            end if
            lst.Push(item)
        end for
        if item.kind = "episode" then
            key = item.seriesID
            if key = invalid then key = item.seriesTitle
            if key <> invalid then
                e = bySeries[key]
                if e = invalid then
                    title = item.seriesTitle
                    if title = invalid then title = key
                    e = {title: title, items: []}
                    bySeries[key] = e
                    seriesKeys.Push(key)
                end if
                e.items.Push(item)
            end if
        else
            for each d in item.directors
                CB_bump(byDirector, directorKeys, d)
            end for
            for each a in item.actors
                CB_bump(byActor, actorKeys, a)
            end for
            if item.year <> invalid then
                yk = iStr(item.year)
                if byYear[yk] = invalid then
                    byYear[yk] = {year: item.year, count: 1}
                    yearKeys.Push(yk)
                else
                    byYear[yk].count = byYear[yk].count + 1
                end if
            end if
        end if
    end for

    genres = []
    for each gn in genreKeys
        all = byGenre[gn]
        if all.Count() >= minItems then
            chip = RuleChip_genre(gn)
            items = CB_filter(all, [chip], now)   ' what the channel will really air (kids' titles leave horror)
            movies = CB_ofKind(items, "movie")
            eps = CB_ofKind(items, "episode")
            if movies.Count() >= minItems then
                rn = ChannelBuilder_retroName(gn, "movies")
                rule = [chip]
                rule.Append(CB_span(movies))
                rule.Push(RuleChip_movies())
                genres.Push(CB_def("genre:" + gn + ":movies", rn[0], ChannelBuilder_decadeTag(rn[1], CB_yearsOf(movies)), rule))
            end if
            if eps.Count() >= minItems then
                rn = ChannelBuilder_retroName(gn, "tv")
                rule = [chip]
                rule.Append(CB_span(eps))
                rule.Push(RuleChip_tv())
                genres.Push(CB_def("genre:" + gn + ":tv", rn[0], ChannelBuilder_decadeTag(rn[1], CB_yearsOf(eps)), rule))
            end if
        end if
    end for
    ' Two channels with the same retro name get told apart by what's on them.
    names = newMap()
    for each gd in genres
        if names[gd.name] = invalid then names[gd.name] = 1 else names[gd.name] = names[gd.name] + 1
    end for
    for i = 0 to genres.Count() - 1
        gd = genres[i]
        if names[gd.name] >= 2 then
            if ChannelDefinition_hasChip(gd, "tv") then
                kind = "TV"
            else if ChannelDefinition_hasChip(gd, "movies") then
                kind = "Films"
            else
                parts = []
                for each s in gd.id.Split(":")
                    if s <> "" then parts.Push(s)
                end for
                kind = ""
                if parts.Count() > 1 then kind = parts[1]
            end if
            genres[i] = ChannelDefinition_copy(gd, {name: gd.name + " (" + kind + ")"})
        end if
    end for
    ' Themed channels: a keyword search within a few related genres, for what no genre tag covers.
    themes = []
    monster = CB_def("theme:monsters", "Creature Feature", "Monster movies", [RuleChip_movies(), RuleChip_anyGenre(ChannelBuilder_monsterGenres()), RuleChip_keywords(ChannelBuilder_monsterWords())])
    if CB_filter(library, monster.rule, now).Count() >= minItems then themes.Push(monster)

    seriesEntries = []
    for each k in seriesKeys
        e = bySeries[k]
        if e.items.Count() >= minItems then seriesEntries.Push({name: k, count: e.items.Count(), title: e.title})
    end for
    series = []
    for each e in prefix(stableSort(seriesEntries, CB_byCountThenName), maxSeries)
        series.Push(CB_def("series:" + e.name, e.title, "Marathon", [RuleChip_series(e.name, e.title)], "inOrder"))
    end for
    directors = []
    for each p in CB_top(byDirector, directorKeys, minItems, maxPeople)
        directors.Push(CB_def("director:" + p, p, "Director", [RuleChip_director(p), RuleChip_movies()]))
    end for
    actors = []
    for each p in CB_top(byActor, actorKeys, minItems, maxPeople)
        actors.Push(CB_def("actor:" + p, p, "Actor", [RuleChip_actor(p), RuleChip_movies()]))
    end for
    yearEntries = []
    for each k in yearKeys
        if byYear[k].count >= minItems then yearEntries.Push(byYear[k])
    end for
    years = []
    for each e in prefix(stableSort(yearEntries, CB_byCountThenYear), 3)
        years.Push(CB_def("year:" + iStr(e.year), "Class of ’" + zeroPad(e.year mod 100, 2), "Films from " + iStr(e.year), [RuleChip_year(e.year), RuleChip_movies()]))
    end for

    ' Scatter the rest with a fixed seed: same channels, same order on every device and launch.
    rest = []
    for each part in [genres, themes, series, directors, actors, years]
        rest.Append(part)
    end for
    rest = shuffled(stableSort(rest, CB_byID), SeededGenerator("retro-binge-dial"))
    all = concat(lead, rest)
    ' Last, so it renumbers nothing: films for the nearest holiday, picked day by day.
    need = minItems
    if Holiday_minFilms() > need then need = Holiday_minFilms()
    for each h in Holiday_entries()
        n = 0
        for each i in library
            if Holiday_has(h, i) then n = n + 1
        end for
        if n >= need then
            all.Push(CB_def("holiday", "Holiday Special", "Films for the nearest holiday", [RuleChip_holiday()]))
            exit for
        end if
    end for
    num = 0
    for i = 0 to all.Count() - 1
        if i = 0 then num = 2 else num = num + 1 + U64_mod(StableHash_fnv1a(all[i].id), 3)
        if num = 99 then num = num + 1   ' 99 belongs to the scrambled channel
        all[i] = ChannelDefinition_copy(all[i], {number: num})
    end for
    return all
end function

' The decade span of `items` as a years chip, or nothing.
function CB_span(items as Object) as Object
    years = CB_yearsOf(items)
    if years.Count() = 0 then return []
    return [RuleChip_years((CB_min(years) \ 10) * 10, CB_max(years))]
end function

' Retro channel names for the common genres: [name, descriptor]. Unknown genres fall back to the genre itself.
' kind: "movies" | "tv" | "mixed".
function ChannelBuilder_retroName(genre as String, kind as String) as Object
    e = ChannelBuilder_retroTable()[LCase(genre)]
    if e <> invalid then
        if kind = "movies" then return [e[1], e[2]]
        if kind = "tv" then return [e[3], e[4]]
        return [e[5], e[6]]
    end if
    if kind = "movies" then return [genre + " Movies", genre + " films"]
    if kind = "tv" then return [genre + " TV", genre + " TV"]
    return [genre, genre]
end function

' Items matching every chip of the rule, in the sequence the channel's order wants.
function ChannelBuilder_resolve(definition as Object, library as Object, now = invalid as Dynamic) as Object
    if now = invalid then now = Time_now()
    ' A marathon whose show's copies were merged under another library's follows it by title.
    rule = []
    for each chip in definition.rule
        if chip.kind = "series" then
            found = false
            for each it in library
                if it.seriesID = chip.id then
                    found = true
                    exit for
                end if
            end for
            if not found then
                for each it in library
                    if it.seriesTitle = chip.title and it.seriesID <> invalid then
                        chip = RuleChip_series(it.seriesID, chip.title)
                        exit for
                    end if
                end for
            end if
        end if
        rule.Push(chip)
    end for
    items = CB_filter(library, rule, now)
    if definition.order = "inOrder" then return stableSort(items, ChannelBuilder_episodeOrder)
    if definition.order = "newestFirst" then return stableSort(items, CB_newestFirst)
    return items
end function

function CB_newestFirst(a as Object, b as Object, ctx as Dynamic) as Integer
    ya = a.year
    if ya = invalid then ya = 0
    yb = b.year
    if yb = invalid then yb = 0
    c = compareValues(yb, ya)
    if c <> 0 then return c
    return swiftCompare(b.title, a.title)
end function

function CB_orZero(v as Dynamic) as Dynamic
    if v = invalid then return 0
    return v
end function

' In order: season, episode, then year and title.
function ChannelBuilder_episodeOrder(a as Object, b as Object, ctx = invalid as Dynamic) as Integer
    c = compareValues(CB_orZero(a.season), CB_orZero(b.season))
    if c <> 0 then return c
    c = compareValues(CB_orZero(a.episode), CB_orZero(b.episode))
    if c <> 0 then return c
    c = compareValues(CB_orZero(a.year), CB_orZero(b.year))
    if c <> 0 then return c
    return swiftCompare(a.title, b.title)
end function

function ChannelBuilder_matches(chip as Object, item as Object, now = invalid as Dynamic) as Boolean
    k = chip.kind
    if k = "addedWithin" then
        if now = invalid then now = Time_now()
        return item.addedAt <> invalid and item.addedAt >= now - chip.days * 86400#
    end if
    if k = "genre" then
        if not contains(item.genres, chip.value) then return false
        return not (contains(["horror", "thriller"], LCase(chip.value)) and ChannelBuilder_isForKids(item))
    end if
    if k = "years" then return item.year <> invalid and item.year >= chip.yearFrom and item.year <= chip.yearTo
    if k = "director" then return contains(item.directors, chip.name)
    if k = "actor" then return contains(item.actors, chip.name)
    if k = "series" then
        if item.seriesID <> invalid then return item.seriesID = chip.id
        return item.seriesTitle <> invalid and item.seriesTitle = chip.title
    end if
    if k = "year" then return item.year <> invalid and item.year = chip.value
    if k = "movies" then return item.kind = "movie"
    if k = "tv" then return item.kind = "episode"
    if k = "anyGenre" then
        for each gn in item.genres
            if contains(chip.genres, gn) then return true
        end for
        return false
    end if
    if k = "keywords" then return ChannelBuilder_mentions(item, chip.words)
    if k = "unwatched" then return not item.watched
    if k = "holiday" then
        if Holiday_isGroundhogDay(item) then return true
        for each h in Holiday_entries()
            if Holiday_has(h, item) then return true
        end for
        return false
    end if
    return false
end function

' Made for children: tagged Children, Kids or Family, rated for kids, or animated without a rating for older viewers.
' ponytail: US ratings only; another country's rating on an animated title counts as not older.
function ChannelBuilder_isForKids(item as Object) as Boolean
    genres = []
    for each gn in item.genres
        genres.Push(LCase(gn))
    end for
    if contains(genres, "children") or contains(genres, "kids") or contains(genres, "family") then return true
    rating = invalid
    if item.contentRating <> invalid then rating = UCase(item.contentRating)
    if rating <> invalid and contains(["TV-Y", "TV-Y7", "TV-Y7-FV", "TV-G", "G"], rating) then return true
    if not contains(genres, "animation") then return false
    return not (rating <> invalid and contains(["TV-14", "TV-MA", "PG-13", "R", "NC-17"], rating))
end function

' Word-start, case-insensitive search of the title and overview: "creature" takes "creatures", not "procreature".
function ChannelBuilder_mentions(item as Object, words as Object) as Boolean
    text = item.title + " "
    if item.overview <> invalid then text = text + item.overview
    text = LCase(text)
    for each w in words
        if w <> "" then
            from = 1
            while true
                r = Instr(from, text, w)
                if r = 0 then exit while
                if r = 1 then return true
                if not isLetterCode(Asc(Mid(text, r - 1, 1))) then return true
                from = r + Len(w)
            end while
        end if
    end for
    return false
end function

' The keywords for "Creature Feature": lowercase, word-start prefixes ("werewol" takes werewolf and werewolves).
function ChannelBuilder_monsterWords() as Object
    return ["monster", "kaiju", "godzilla", "king kong", "kong:", "creature", "werewol", "vampire", "zombie", "frankenstein",
            "dracula", "mummy", "dinosaur", "great white", "megalodon", "gremlin", "xenomorph", "kraken", "leviathan", "cryptid",
            "sasquatch", "bigfoot", "swamp thing"]
end function

' The genres searched for those keywords.
function ChannelBuilder_monsterGenres() as Object
    return ["Horror", "Science Fiction", "Sci-Fi", "Action", "Adventure"]
end function

' The "what's new" channels: New Releases, New This Season, Just Added, Fresh Episodes and any channel with an "Added
' in the last N days" chip.
function ChannelBuilder_isFresh(d as Object) as Boolean
    if contains(["lead:new-movies", "lead:new-tv", "lead:just-added", "lead:just-added-tv"], d.id) then return true
    return ChannelDefinition_hasChip(d, "addedWithin")
end function

' channelsFrom(definitions, library, now), with `fresh` (newly added items not yet in library) given to the fresh channels.
function ChannelBuilder_channels(definitions as Object, library as Object, fresh as Object, now = invalid as Dynamic) as Object
    if fresh.Count() = 0 then return ChannelBuilder_channelsFrom(definitions, library, now)
    stale = []
    news = []
    for each d in definitions
        if ChannelBuilder_isFresh(d) then news.Push(d) else stale.Push(d)
    end for
    return concat(ChannelBuilder_channelsFrom(stale, library, now), ChannelBuilder_channelsFrom(news, concat(library, fresh), now))
end function

' Resolve definitions against the library, dropping channels with nothing to air.
function ChannelBuilder_channelsFrom(definitions as Object, library as Object, now = invalid as Dynamic) as Object
    if now = invalid then now = Time_now()
    out = []
    for each d in definitions
        items = ChannelBuilder_resolve(d, library, now)
        if items.Count() > 0 then out.Push(Channel_new(d, items))
    end for
    return out
end function

' Names with enough in the library to fill an evening, for the "New channel" picker: [{name, id, count}], most first.
' kind: "director" | "actor" | "series".
function ChannelBuilder_candidates(kind as String, library as Object, minItems = 3 as Integer) as Object
    counts = newMap()
    keys = []
    for each item in library
        if kind = "director" and item.kind = "movie" then
            for each d in item.directors
                CB_bumpCandidate(counts, keys, d, invalid)
            end for
        else if kind = "actor" and item.kind = "movie" then
            for each a in item.actors
                CB_bumpCandidate(counts, keys, a, invalid)
            end for
        else if kind = "series" and item.kind = "episode" and item.seriesTitle <> invalid then
            CB_bumpCandidate(counts, keys, item.seriesTitle, item.seriesID)
        end if
    end for
    out = []
    for each k in keys
        if counts[k].count >= minItems then out.Push(counts[k])
    end for
    return stableSort(out, CB_byCountThenName)
end function

function CB_bumpCandidate(counts as Object, keys as Object, name as String, id as Dynamic)
    c = counts[name]
    if c = invalid then
        counts[name] = {name: name, id: id, count: 1}
        keys.Push(name)
    else
        if c.id = invalid then c.id = id
        c.count = c.count + 1
    end if
end function

function ChannelBuilder_candidateKindName(kind as String) as String
    if kind = "director" then return "Director"
    if kind = "actor" then return "Actor"
    return "Show marathon"
end function

' "Comedy films, 80s–90s": "80s" for the 1900s, "2010s" from 2000 on.
function ChannelBuilder_decadeTag(genre as String, years as Object) as String
    if years.Count() = 0 then return genre
    lo = CB_min(years)
    hi = CB_max(years)
    if lo \ 10 = hi \ 10 then return genre + ", " + CB_decade(lo)
    return genre + ", " + CB_decade(lo) + "–" + CB_decade(hi)
end function

function CB_decade(y as Integer) as String
    if y < 2000 then return iStr((y mod 100) \ 10 * 10) + "s"
    return iStr(y \ 10 * 10) + "s"
end function

' ---- GuideGenerator: deterministic scheduler. Same (lineup, day), identical schedule on every device ----

' Guide grid resolution: slots are (runtime + pad) rounded up to a multiple of this.
function GuideGenerator_blockLength() as Integer
    return 1800
end function

' Every channel of `lineup` tiling `day` from local midnight to the next: an AA by channel id (case-sensitive) of slot
' arrays. See GuideGenerator.ts scheduleLineup for the rules (the tape, one program on one channel at a time, no repeats).
function GuideGenerator_scheduleLineup(lineup as Object, day as Double) as Object
    start = Time_startOfDay(day)
    ' Tile by time: a DST day is 23 or 25 hours. (Start of the next day, not 24 h on.)
    nxt = Time_addDays(start, 1)
    year = 0
    lengths = []
    for each ch in lineup
        if GuideGenerator_isContinuous(ch) then
            dl = GuideGenerator_dayLengths(start)
            year = dl.year
            lengths = dl.lengths
            exit for
        end if
    end for
    ' On December 31, January 1's length: the tapes look ahead to what they open the new year with.
    jan1 = invalid
    if year <> 0 and Time_localYear(nxt) <> year then jan1 = jsRound(Time_addDays(nxt, 1)) - jsRound(nxt)
    busy = Busy_new()
    out = newMap()
    for each ch in GuideGenerator_dependencyOrder(lineup)
        s = GG_scheduleOne(ch, start, nxt, year, lengths, jan1, busy)
        out[ch.id] = s
        busy.add(s)
    end for
    return out
end function

' One channel's day on its own (no other channel in the way).
function GuideGenerator_schedule(channel as Object, day as Double) as Object
    s = GuideGenerator_scheduleLineup([channel], day)[channel.id]
    if s = invalid then return []
    return s
end function

function GG_scheduleOne(ch as Object, start as Double, finish as Double, year as Integer, lengths as Object, jan1 as Dynamic, busy as Object) as Object
    if ch.items.Count() = 0 then return []
    if GuideGenerator_isContinuous(ch) then
        t = Tape_new(ch, year)
        day = jsRound(finish) - jsRound(start)
        fits = newMap()
        for each l in concat(lengths, [day])
            k = iStr(l)
            if fits[k] = invalid then fits[k] = t.fit(l)
        end for
        return GG_tileRun(t, start, finish, GG_stateAt(t, lengths, fits), fits, busy, ch.order = "shuffle", jan1)
    end if
    ' A day opens with one of its pool's first two items, so tonight's last slot steers clear of both of tomorrow's; of
    ' the first only when the pool has only two. Not an In order holiday channel: its films are the day's own.
    tomorrow = GuideGenerator_pool(ch, finish)
    two = []
    for each it in prefix(tomorrow, 2)
        two.Push(GuideGenerator_repeatKey(it))
    end for
    opens = []
    if ch.order <> "inOrder" then
        other = false
        for each it in tomorrow
            if not contains(two, GuideGenerator_repeatKey(it)) then
                other = true
                exit for
            end if
        end for
        if other then opens = two else opens = prefix(two, 1)
    end if
    return GuideGenerator_tile(GuideGenerator_pool(ch, start), start, finish, opens, busy)
end function

' ---- The tape (marathons that keep going, shows taking turns) ----

' The show an episode belongs to; a film, or an episode with no show, is its own.
function GuideGenerator_showKey(item as Object) as String
    if item.seriesID <> invalid then return item.seriesID
    if item.seriesTitle <> invalid then return item.seriesTitle
    return item.id
end function

' Episodes of two or more shows: on Shuffle the shows take turns, each in order.
function GuideGenerator_takesTurns(ch as Object) as Boolean
    shows = newMap()
    n = 0
    for each it in ch.items
        if it.kind <> "episode" then return false
        k = GuideGenerator_showKey(it)
        if shows[k] = invalid then
            shows[k] = true
            n = n + 1
        end if
    end for
    return n >= 2
end function

' Runs on the tape. Never the holiday channel: its films are the day's holiday's.
function GuideGenerator_isContinuous(ch as Object) as Boolean
    if ChannelDefinition_hasChip(ch.definition, "holiday") then return false
    return ch.order = "inOrder" or (ch.order = "shuffle" and GuideGenerator_takesTurns(ch))
end function

' Who gives way to whom: In order channels never do, then turns channels, then shuffle and newest first, and last the
' "what's new" channels and any with an Unwatched chip.
function GG_tier(ch as Object) as Integer
    if ChannelBuilder_isFresh(ch.definition) or ChannelDefinition_hasChip(ch.definition, "unwatched") then return 3
    if not GuideGenerator_isContinuous(ch) then return 2
    if ch.order = "inOrder" then return 0
    return 1
end function

function GG_byTierNumberID(a as Object, b as Object, ctx as Dynamic) as Integer
    if a.t <> b.t then return a.t - b.t
    c = compareValues(a.ch.number, b.ch.number)
    if c <> 0 then return c
    return swiftCompare(a.ch.id, b.ch.id)
end function

' The lineup by (tier, number, id), hidden channels and channel 99 included.
function GuideGenerator_dependencyOrder(channels as Object) as Object
    tagged = []
    for each ch in channels
        tagged.Push({t: GG_tier(ch), ch: ch})
    end for
    out = []
    for each e in stableSort(tagged, GG_byTierNumberID)
        out.Push(e.ch)
    end for
    return out
end function

function GG_byShowName(a as Object, b as Object, ctx as Dynamic) as Integer
    c = swiftCompare(a.name, b.name)
    if c <> 0 then return c
    return swiftCompare(a.k, b.k)
end function

function GG_byEpisodeIndex(a as Integer, b as Integer, items as Object) as Integer
    return ChannelBuilder_episodeOrder(items[a], items[b])
end function

' The channel's items as one endless tape. In order: the items as they are, round and round. Turns: show A's next
' episode, then B's, then C's (shows by name), each show in order, wrapping on its own.
function Tape_new(ch as Object, year as Integer) as Object
    items = ch.items
    n = items.Count()
    t = {items: items, len: [], part: [], short: [], keyID: [], shows: [], showOf: [], keyMin: [], at: Tape_at, fit: Tape_fit}
    ids = newMap()
    nIDs = 0
    for i = 0 to n - 1
        it = items[i]
        l = GuideGenerator_slotLength(it)
        t.len.Push(l)
        t.part.Push(GuideGenerator_partLength(it))
        t.short.Push(it.runtime * 2 <= l)   ' tile's packing test
        k = GuideGenerator_repeatKey(it)
        id = ids[k]
        if id = invalid then
            id = nIDs
            ids[k] = id
            nIDs = nIDs + 1
            t.keyMin.Push(1.0e30#)
        end if
        t.keyID.Push(id)
        if l < t.keyMin[id] then t.keyMin[id] = l
    end for
    if ch.order = "shuffle" then
        groups = newMap()   ' in first-seen order
        gkeys = []
        for i = 0 to n - 1
            k = GuideGenerator_showKey(items[i])
            if groups[k] = invalid then
                groups[k] = []
                gkeys.Push(k)
            end if
            groups[k].Push(i)
        end for
        entries = []
        for each k in gkeys
            g = groups[k]
            name = items[g[0]].seriesTitle
            if name = invalid then name = ""
            entries.Push({name: name, k: k, g: g})
        end for
        for each e in stableSort(entries, GG_byShowName)
            t.shows.Push(stableSort(e.g, GG_byEpisodeIndex, items))
        end for
    else
        all = []
        for i = 0 to n - 1
            all.Push(i)
        end for
        t.shows.Push(all)
    end if
    for i = 0 to n - 1
        t.showOf.Push(0)
    end for
    for s = 0 to t.shows.Count() - 1
        for each i in t.shows[s]
            t.showOf[i] = s
        end for
    end for
    ' Where January 1 starts, this year and next, seeded by the channel and the year.
    t.p0 = U64_mod(StableHash_fnv1a(ch.id + "|" + iStr(year)), n)
    t.nextP0 = U64_mod(StableHash_fnv1a(ch.id + "|" + iStr(year + 1)), n)
    return t
end function

' The item at tape position p (>= 0).
function Tape_at(p as Integer) as Integer
    ns = m.shows.Count()
    g = m.shows[p mod ns]
    return g[(p \ ns) mod g.Count()]
end function

' For a day `length` seconds long: how many keys have something that fits it (0: nothing does).
function Tape_fit(length as Double) as Integer
    n = 0
    for each k in m.keyMin
        if k <= length then n = n + 1
    end for
    return n
end function

' One day of the tape: {plan: the slots it airs (tape positions: the program, then any packed parts), state: {p, last}}.
function GG_walk(t as Object, state as Object, day as Double, fit as Integer, collect as Boolean) as Object
    p = state.p
    last = state.last
    used = 0
    plan = []
    if fit = 0 then   ' longer than the whole day: airs cut
        i = t.at(p)
        return {plan: [[p]], state: {p: p + 1, last: t.keyID[i]}}
    end if
    nShows = t.shows.Count()
    while true
        i = t.at(p)
        if t.len[i] > day then
            p = p + 1
        else if fit >= 2 and t.keyID[i] = last then
            p = p + 1
        else
            if used + t.len[i] > day then exit while
            slot = [p]
            p = p + 1
            used = used + t.len[i]
            last = t.keyID[i]
            if t.short[i] and t.items.Count() > 1 then
                room = t.len[i] - t.part[i]
                while true
                    j = t.at(p)
                    ' Already in this slot: an item comes round every (shows x its show's items) positions.
                    if t.part[j] > room or t.keyID[j] = last or slot.Count() >= nShows * t.shows[t.showOf[j]].Count() then exit while
                    slot.Push(p)
                    room = room - t.part[j]
                    last = t.keyID[j]
                    p = p + 1
                end while
            end if
            if collect then plan.Push(slot)
        end if
    end while
    return {plan: plan, state: {p: p, last: last}}
end function

' The year so far: January 1 starts at p0, and every day since walks on from the one before.
' ponytail: re-walks the year on every lineup-day call; memoize the furthest (day, p, last) per channel if a big
' library's guide is slow to fill on a Roku.
function GG_stateAt(t as Object, lengths as Object, fits as Object) as Object
    s = {p: t.p0, last: -1}
    for each l in lengths
        s = GG_walk(t, s, l, fits[iStr(l)], false).state
    end for
    return s
end function

' The day's year and the length in seconds of each day of it before dayStart: {year, lengths}.
function GuideGenerator_dayLengths(dayStart as Double) as Object
    year = Time_localYear(dayStart)
    lengths = []
    d = Time_midnight(year, 1, 1)
    while d < dayStart
        nd = Time_addDays(d, 1)
        lengths.Push(jsRound(nd - d))
        d = nd
    end while
    return {year: year, lengths: lengths}
end function

' Tiles the day from the tape at `state`. A turns channel (swaps) whose next episode is on another channel airs another
' show's next episode from the same round instead; what the tape can't fit before midnight is an encore of the longest
' program aired earlier that day, else the last slot runs on.
function GG_tileRun(t as Object, start as Double, finish as Double, state as Object, fits as Object, busy as Object, swaps as Boolean, jan1 as Dynamic) as Object
    s0 = jsRound(start)
    e0 = jsRound(finish)
    dayFit = fits[iStr(e0 - s0)]
    w = GG_walk(t, state, e0 - s0, dayFit, true)
    plan = w.plan
    ' What opens tomorrow: the next position; on December 31 what January 1's walk places first.
    opener = t.keyID[t.at(w.state.p)]
    if jan1 <> invalid then
        opener = t.keyID[t.at(GG_walk(t, {p: t.nextP0, last: -1}, jan1, t.fit(jan1), true).plan[0][0])]
        tail = plan[plan.Count() - 1]
        if plan.Count() > 1 and dayFit >= 2 and t.keyID[t.at(tail[tail.Count() - 1])] = opener then
            if tail.Count() > 1 then tail.Pop() else plan.Pop()
        end if
    end if
    cursor = s0
    prev = -1
    idx = 0
    slots = []
    whole = []
    while idx < plan.Count()
        first = t.at(plan[idx][0])
        ' ponytail: a packed half hour never swaps, so two turns cartoon channels sharing a short can overlap for a few
        ' minutes. Upgrade: swap whole packs.
        if swaps and plan[idx].Count() = 1 and busy.conflicts(GuideGenerator_repeatKey(t.items[first]), Busy_airs(t.items[first], cursor)) then
            seen = newMap()   ' shows with an entry between idx and u
            for u = idx + 1 to plan.Count() - 1
                showsU = newMap()
                for each q in plan[u]
                    showsU[iStr(t.showOf[t.at(q)])] = true
                end for
                if showsU[iStr(t.showOf[first])] <> invalid then exit for   ' never past its own show's next episode
                cand = t.at(plan[u][0])
                if plan[u].Count() = 1 and seen[iStr(t.showOf[cand])] = invalid and t.keyID[cand] <> t.keyID[first] and not busy.conflicts(GuideGenerator_repeatKey(t.items[cand]), Busy_airs(t.items[cand], cursor)) then
                    q = []
                    q.Append(plan)
                    q[idx] = plan[u]
                    q[u] = plan[idx]
                    ' Each moved entry against what airs before it: the entry before, or for the day's first what the
                    ' tape placed last yesterday (state.last, nothing on January 1).
                    repeats = false
                    for each x in [idx, idx + 1, u, u + 1]
                        if x < q.Count() then
                            if x = 0 then
                                before = state.last
                            else
                                pq = q[x - 1]
                                before = t.keyID[t.at(pq[pq.Count() - 1])]
                            end if
                            if t.keyID[t.at(q[x][0])] = before then
                                repeats = true
                                exit for
                            end if
                        end if
                    end for
                    if not repeats and not (u = plan.Count() - 1 and t.keyID[first] = opener) then
                        plan = q
                        first = cand
                        exit for
                    end if
                end if
                for each sk in showsU
                    seen[sk] = true
                end for
            end for
        end if
        slotEnd = cursor + t.len[first]
        if slotEnd > e0 then slotEnd = e0
        parts = []
        for each q in plan[idx]
            parts.Push(t.at(q))
        end for
        if parts.Count() = 1 and slotEnd - cursor = t.len[first] then whole.Push(first)
        for pk = 0 to parts.Count() - 1
            i = parts[pk]
            if pk = parts.Count() - 1 then partEnd = slotEnd else partEnd = cursor + t.part[i]
            slots.Push(Slot_new(t.items[i], cursor, partEnd))
            cursor = partEnd
        end for
        prev = t.keyID[parts[parts.Count() - 1]]
        idx = idx + 1
    end while
    if cursor < e0 then   ' the time the next one didn't fit
        encore = -1
        for each i in whole
            if t.len[i] <= e0 - cursor and t.keyID[i] <> prev and t.keyID[i] <> opener and not busy.conflicts(GuideGenerator_repeatKey(t.items[i]), Busy_airs(t.items[i], cursor)) then
                if encore < 0 then
                    encore = i
                else if t.len[i] > t.len[encore] then
                    encore = i   ' the longest, the earliest on ties
                end if
            end if
        end for
        if encore >= 0 then
            slots.Push(Slot_new(t.items[encore], cursor, finish))   ' its leftover is its break
        else
            l = slots.Pop()
            slots.Push(Slot_new(l.item, l.start, finish))
        end if
    end if
    return slots
end function

' ---- One program on one channel at a time ----

' The airing windows of everything placed so far today, by repeatKey, in whole epoch seconds.
function Busy_new() as Object
    return {windows: newMap(), conflicts: Busy_conflicts, add: Busy_add}
end function

' When `item` would air if it started at `at`: [at, at + whole runtime].
function Busy_airs(item as Object, at as Double) as Object
    return [at, at + Fix(item.runtime)]
end function

function Busy_conflicts(key as String, w as Object) as Boolean
    ws = m.windows[key]
    if ws = invalid then return false
    for each x in ws
        if x[0] < w[1] and w[0] < x[1] then return true
    end for
    return false
end function

function Busy_add(slots as Object)
    for each s in slots
        a = jsRound(s.start)
        k = GuideGenerator_repeatKey(s.item)
        w = [a, a + minD(jsRound(s.finish) - a, Fix(s.item.runtime))]
        ws = m.windows[k]
        if ws = invalid then m.windows[k] = [w] else ws.Push(w)
    end for
end function

' What mustn't air twice in a row: the item, or for a film any copy of it (same title and year). A cut is part of the
' title, so two cuts are two films. Episodes go by item.
function GuideGenerator_repeatKey(item as Object) as String
    if item.kind = "movie" then
        y = 0
        if item.year <> invalid then y = item.year
        return "film:" + item.title + "|" + iStr(y)
    end if
    return "item:" + item.id
end function

' The day's play order, seeded by channel and date. `day` is a local midnight. The holiday channel's is the day's
' holiday's films only.
function GuideGenerator_pool(channel as Object, day as Double) as Object
    ymd = Time_localYMD(day)
    rng = SeededGenerator(channel.id + "|" + zeroPad(ymd[0], 4) + "-" + zeroPad(ymd[1], 2) + "-" + zeroPad(ymd[2], 2))
    items = channel.items
    if ChannelDefinition_hasChip(channel.definition, "holiday") then items = Holiday_pick(channel.items, day).films
    if channel.order = "shuffle" then return shuffled(items, rng)
    r = U64_mod(rng.nextRaw(), items.Count())   ' plain modulo, not Lemire: as Swift and Kotlin
    return concat(suffixFrom(items, r), prefix(items, r))
end function

' The longest pool item that fits `window` and repeats neither `before` nor `clear`; with `free`, also one no other
' channel airs at `at`. Starts from `item` when it qualifies. Invalid when none does.
function GG_longest(pool as Object, nxt as Integer, item as Object, window as Double, before as String, clear as Object, free as Boolean, busy as Object, at as Double) as Dynamic
    found = invalid
    if GG_longestOK(item, before, clear, free, busy, at) then found = item
    n = pool.Count()
    for k = 0 to n - 1
        it = pool[(nxt + k) mod n]
        if found = invalid then fl = 0 else fl = GuideGenerator_slotLength(found)
        if GuideGenerator_slotLength(it) <= window and GuideGenerator_slotLength(it) > fl and GG_longestOK(it, before, clear, free, busy, at) then found = it
    end for
    return found
end function

function GG_longestOK(it as Object, before as String, clear as Object, free as Boolean, busy as Object, at as Double) as Boolean
    k = GuideGenerator_repeatKey(it)
    if k = before or contains(clear, k) then return false
    return not (free and busy.conflicts(k, Busy_airs(it, at)))
end function

' Tiles [start, finish) from `pool` as GuideGenerator.ts `tile` describes. `opens`: the repeatKeys of tomorrow's two
' openers; `busy`: what other channels air.
function GuideGenerator_tile(pool as Object, start as Double, finish as Double, opens as Object, busy = invalid as Dynamic) as Object
    if busy = invalid then busy = Busy_new()
    slots = []
    cursor = start
    nxt = 0
    n = pool.Count()
    day = finish - start
    while cursor < finish
        previous = invalid
        if slots.Count() > 0 then previous = GuideGenerator_repeatKey(slots[slots.Count() - 1].item)
        pick = -1
        blocked = -1
        again = -1
        for k = 0 to n - 1
            if k = 2 and slots.Count() = 0 and opens.Count() > 0 and blocked >= 0 then exit for   ' the day's first slot: one of the first two
            i = (nxt + k) mod n
            slotEnd = cursor + GuideGenerator_slotLength(pool[i])
            if slotEnd <= finish then
                key = GuideGenerator_repeatKey(pool[i])
                if slots.Count() = 0 or (key <> previous and (slotEnd < finish or not contains(opens, key))) then
                    if not busy.conflicts(key, Busy_airs(pool[i], jsRound(cursor))) then
                        pick = i
                        exit for
                    end if
                    if blocked < 0 then blocked = i
                else if again < 0 then
                    again = i
                end if
            end if
        end for
        if pick < 0 then pick = blocked
        ' Only the same thing again fits: fine on a channel with nothing else that could air today.
        if pick < 0 and again >= 0 then
            other = false
            for each it in pool
                if GuideGenerator_repeatKey(it) <> previous and GuideGenerator_slotLength(it) <= day then
                    other = true
                    exit for
                end if
            end for
            if not other then pick = again
        end if
        if pick < 0 then
            last = slots.Pop()
            ' A half hour of short programs goes as a whole, so the re-picked slot starts on the half-hour grid.
            while last <> invalid and (Int(last.start - start) mod 1800) <> 0
                before = slots.Pop()
                if before = invalid then exit while
                last = before
            end while
            if last <> invalid then
                best = last.item   ' fits by construction; a longer one that also fits leaves a shorter break
                if slots.Count() > 0 then   ' (the day's opener itself never changes)
                    before = GuideGenerator_repeatKey(slots[slots.Count() - 1].item)
                    window = finish - last.start
                    at = jsRound(last.start)
                    best = GG_longest(pool, nxt, last.item, window, before, opens, true, busy, at)
                    if best = invalid then best = GG_longest(pool, nxt, last.item, window, before, opens, false, busy, at)
                    if best = invalid then best = GG_longest(pool, nxt, last.item, window, before, prefix(opens, 1), false, busy, at)
                    if best = invalid then best = last.item
                end if
                slots.Push(Slot_new(best, last.start, finish))
            else
                slots.Push(Slot_new(pool[nxt], cursor, finish))   ' longer than the whole day
            end if
            exit while
        end if
        slotEnd = cursor + GuideGenerator_slotLength(pool[pick])
        ' A short program (half its half hour or less) doesn't leave the rest of it empty: the next ones in order that
        ' fit play right after it, each in its own slot. Nothing crosses the half hour.
        parts = [pool[pick]]
        used = GuideGenerator_partLength(pool[pick])
        nxt = (pick + 1) mod n
        if pool[pick].runtime <= (slotEnd - cursor) / 2 then
            while n > 1
                it = pool[nxt]
                if used + GuideGenerator_partLength(it) > slotEnd - cursor then exit while
                dup = false
                for each p in parts
                    if p.id = it.id then
                        dup = true
                        exit for
                    end if
                end for
                if dup then exit while
                key = GuideGenerator_repeatKey(it)
                if key = GuideGenerator_repeatKey(parts[parts.Count() - 1]) then exit while
                if not (slotEnd < finish or not contains(opens, key)) then exit while
                if busy.conflicts(key, Busy_airs(it, jsRound(cursor) + used)) then exit while
                parts.Push(it)
                used = used + GuideGenerator_partLength(it)
                nxt = (nxt + 1) mod n
            end while
        end if
        for pn = 0 to parts.Count() - 1   ' the last one keeps whatever is left of the half hour as its break
            if pn = parts.Count() - 1 then partEnd = slotEnd else partEnd = cursor + GuideGenerator_partLength(parts[pn])
            slots.Push(Slot_new(parts[pn], cursor, partEnd))
            cursor = partEnd
        end for
    end while
    return slots
end function

' A packed program's slot: its runtime in whole seconds, so the next one starts as it ends.
function GuideGenerator_partLength(item as Object) as Double
    return maxD(1, Int(item.runtime))
end function

' Slots on `channel` intersecting [from, to]. Spans days as needed.
function GuideGenerator_scheduleRange(channel as Object, from as Double, upTo as Double) as Object
    out = []
    day = Time_startOfDay(from)
    while day < upTo
        for each s in GuideGenerator_schedule(channel, day)
            if s.finish > from and s.start < upTo then out.Push(s)
        end for
        day = Time_addDays(day, 1)
    end while
    return out
end function

' The slot containing `at` on `ch`.
function GuideGenerator_slot(ch as Object, at as Double) as Dynamic
    for each s in GuideGenerator_schedule(ch, at)
        if s.start <= at and at < s.finish then return s
    end for
    return invalid
end function

' The slot by its exact start, if the generator still produces it (sub-second tolerance for a start that went through JSON).
function GuideGenerator_slotStartingAt(ch as Object, startingAt as Double) as Dynamic
    for each s in GuideGenerator_schedule(ch, startingAt)
        if Abs(s.start - startingAt) < 1 then return s
    end for
    return invalid
end function

' later: before start, live: item playing, break: item over and slot not, past: slot over.
function GuideGenerator_status(s as Object, at as Double) as String
    if at < s.start then return "later"
    if at >= s.finish then return "past"
    if at >= Slot_itemEnd(s) then return "break"
    return "live"
end function

function GuideGenerator_slotLength(item as Object) as Double
    ' Channel 99's programs fill their slots exactly: no pad, so the scramble never drops into a station break.
    padded = item.runtime + 180
    if startsWith(item.id, "scrambled") then padded = item.runtime
    return maxD(1, ceil(padded / 1800)) * 1800
end function

' ---- Holiday: the holiday channel's calendar (US holidays) ----

function Holiday_entries() as Object
    return ["newYear", "valentines", "stPatricks", "easter", "july4", "halloween", "thanksgiving", "christmas"]
end function

function Holiday_rawValue(h as String) as String
    names = {newYear: "New Year’s", valentines: "Valentine’s Day", stPatricks: "St. Patrick’s Day", easter: "Easter",
             july4: "Fourth of July", halloween: "Halloween", thanksgiving: "Thanksgiving", christmas: "Christmas"}
    return names[h]
end function

' Fewer and the holiday sits the year out.
function Holiday_minFilms() as Integer
    return 4
end function

' Days before the holiday that its season starts.
function Holiday_lead(h as String) as Integer
    if h = "newYear" then return 6            ' from the day after Christmas
    if h = "valentines" then return 13
    if h = "halloween" then return 30         ' all October
    if h = "thanksgiving" then return 27      ' all November up to it
    if h = "christmas" then return 33         ' from the day after Thanksgiving
    return 7
end function

' Its [month, day] in `year`.
function Holiday_date(h as String, year as Integer) as Object
    if h = "newYear" then return [1, 1]
    if h = "valentines" then return [2, 14]
    if h = "stPatricks" then return [3, 17]
    if h = "easter" then return Holiday_easter(year)
    if h = "july4" then return [7, 4]
    if h = "halloween" then return [10, 31]
    if h = "thanksgiving" then return [11, 22 + (11 - Holiday_weekday(year, 11, 1)) mod 7]   ' the fourth Thursday
    return [12, 25]
end function

' Word starts in a film's title or overview that make it this holiday's.
function Holiday_words(h as String) as Object
    if h = "newYear" then return ["new year", "auld lang syne"]
    if h = "valentines" then return ["valentine"]
    if h = "stPatricks" then return ["st. patrick", "st patrick", "saint patrick", "leprechaun", "ireland"]
    if h = "easter" then return ["easter bunny", "easter egg", "easter parade", "easter sunday", "jesus", "ten commandments", "ben-hur"]
    if h = "july4" then return ["fourth of july", "4th of july", "july 4", "july fourth", "independence day"]
    if h = "halloween" then return ["halloween", "trick or treat", "trick-or-treat"]
    if h = "thanksgiving" then return ["thanksgiving"]
    return ["christmas", "xmas", "santa claus", "north pole", "yuletide", "scrooge", "grinch", "nutcracker", "kris kringle", "reindeer"]
end function

' Genres that make a film this holiday's.
function Holiday_genres(h as String) as Object
    if h = "valentines" then return ["Romance"]
    if h = "halloween" then return ["Horror"]
    return []
end function

' A film for this holiday.
function Holiday_has(h as String, item as Object) as Boolean
    if item.kind <> "movie" then return false
    if ChannelBuilder_mentions(item, Holiday_words(h)) then return true
    for each gn in Holiday_genres(h)
        if ChannelBuilder_matches(RuleChip_genre(gn), item) then return true
    end for
    return false
end function

' Groundhog Day's own film, by its title, any cut of it.
function Holiday_isGroundhogDay(item as Object) as Boolean
    if item.kind <> "movie" then return false
    t = LCase(item.title)
    return t = "groundhog day" or startsWith(t, "groundhog day (")
end function

function Holiday_byKey(a as Object, b as Object, ctx as Dynamic) as Integer
    if a.k[0] <> b.k[0] then return a.k[0] - b.k[0]
    return a.k[1] - b.k[1]
end function

' What the holiday channel airs on `day`'s local day, and its holiday's name: {name, films}.
function Holiday_pick(films as Object, day as Double) as Object
    ymd = Time_localYMD(day)
    y = ymd[0]
    if ymd[1] = 2 and ymd[2] = 2 then
        g = []
        for each it in films
            if Holiday_isGroundhogDay(it) then g.Push(it)
        end for
        if g.Count() > 0 then return {name: "Groundhog Day", films: g}
    end if
    today = Time_daysFromCivil(y, ymd[1], ymd[2])
    ' In its season (0), else how far from it; then the nearer holiday.
    ranked = []
    for each h in Holiday_entries()
        best = invalid
        for year = y - 1 to y + 1
            md = Holiday_date(h, year)
            at = Time_daysFromCivil(year, md[0], md[1])
            st = at - Holiday_lead(h)
            if today < st then k0 = st - today else k0 = today - at
            if k0 < 0 then k0 = 0
            k = [k0, Abs(at - today)]
            if best = invalid then
                best = k
            else if k[0] < best[0] or (k[0] = best[0] and k[1] < best[1]) then
                best = k
            end if
        end for
        ranked.Push({h: h, k: best})
    end for
    for each e in stableSort(ranked, Holiday_byKey)
        mine = []
        for each it in films
            if Holiday_has(e.h, it) then mine.Push(it)
        end for
        if mine.Count() >= Holiday_minFilms() then return {name: Holiday_rawValue(e.h), films: mine}
    end for
    return {name: "Holiday", films: films}
end function

' 0 = Sunday.
function Holiday_weekday(y as Integer, mo as Integer, d as Integer) as Integer
    return ((Time_daysFromCivil(y, mo, d) mod 7) + 11) mod 7   ' 1970-01-01 was a Thursday
end function

' Western Easter Sunday (the anonymous Gregorian algorithm): [month, day].
function Holiday_easter(y as Integer) as Object
    a = y mod 19
    b = y \ 100
    c = y mod 100
    d = b \ 4
    e = b mod 4
    f = (b + 8) \ 25
    g = (b - f + 1) \ 3
    h = (19 * a + b - d - g + 15) mod 30
    i = c \ 4
    k = c mod 4
    l = (32 + 2 * e + 2 * i - h - k) mod 7
    mm = (a + 11 * h + 22 * l) \ 451
    n = h + l - 7 * mm + 114
    return [n \ 31, n mod 31 + 1]
end function
