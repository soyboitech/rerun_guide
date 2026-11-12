' Port of web/src/core/TitleSearch.ts: Options > Search. Films by title and shows by series title, and when each airs
' next. Matching ignores case, accents and punctuation, and a leading "The", "A" or "An" needn't be typed.

' The most results a search returns; how far ahead "airs next" looks.
function TitleSearch_limit() as Integer
    return 50
end function

function TitleSearch_window() as Integer
    return 24 * 3600
end function

' Every film and show keyed for matching, sorted the way equal matches are listed: {entries, entryOf (item id -> entry id)}.
' An entry: {id: "movie:<full>|<year>" or "show:<series title>", title, year, isShow, item, full, bare}.
function TitleSearch_index(library as Object) as Object
    entries = []
    at = newMap()
    entryOf = newMap()
    for each item in library
        show = item.kind = "episode"
        if show then title = item.seriesTitle else title = item.title
        if title <> invalid then
            key = invalid
            id = "show:" + title
            if not show then
                key = TitleSearch_keys(title)
                y = 0
                if item.year <> invalid then y = item.year
                id = "movie:" + key.full + "|" + iStr(y)
            end if
            entryOf[item.id] = id
            i = at[id]
            if i <> invalid then
                e = entries[i]
                if show and item.year <> invalid and (e.year = invalid or item.year < e.year) then e.year = item.year
            else
                if key = invalid then key = TitleSearch_keys(title)
                at[id] = entries.Count()
                entries.Push({id: id, title: title, year: item.year, isShow: show, item: item, full: key.full, bare: key.bare})
            end if
        end if
    end for
    return {entries: stableSort(entries, TS_byKeys), entryOf: entryOf}
end function

' By bare, then year (none as 0), films before shows, then full and the raw title.
function TS_byKeys(a as Object, b as Object, ctx as Dynamic) as Integer
    c = swiftCompare(a.bare, b.bare)
    if c <> 0 then return c
    ya = a.year
    if ya = invalid then ya = 0
    yb = b.year
    if yb = invalid then yb = 0
    if ya <> yb then return ya - yb
    if a.isShow <> b.isShow then
        if a.isShow then return 1
        return -1
    end if
    c = swiftCompare(a.full, b.full)
    if c <> 0 then return c
    return swiftCompare(a.title, b.title)
end function

' Up to `limit` entries: exact titles first, then titles that start with the query, then any other match.
function TitleSearch_search(query as String, index as Object, limit = 50 as Integer) as Object
    q = TitleSearch_keys(query).full
    if q = "" then return []
    exact = []
    starts = []
    other = []
    for each e in index.entries   ' already in tie order, so each list stays sorted
        if e.full = q or e.bare = q then
            exact.Push(e)
        else if startsWith(e.full, q) or startsWith(e.bare, q) then
            if starts.Count() < limit then starts.Push(e)
        else if other.Count() < limit and Instr(1, e.full, q) > 0 then
            other.Push(e)
        end if
    end for
    out = concat(exact, starts)
    out.Append(other)
    return prefix(out, limit)
end function

' "The Schindler’s List" -> {full: "theschindlerslist", bare: "schindlerslist"}: lowercased, accents dropped, split into
' words at anything but a letter or a digit, joined; bare drops a leading article when more words follow.
function TitleSearch_keys(s as String) as Object
    g = GetGlobalAA()
    if g.tsNonASCII = invalid then
        g.tsNonASCII = CreateObject("roRegex", "[^\x00-\x7F]", "")
        g.tsSplit = CreateObject("roRegex", "[^a-z0-9]+", "")
    end if
    words = []
    if g.tsNonASCII.IsMatch(s) then
        words = TS_unicodeWords(s)
    else
        for each w in g.tsSplit.Split(LCase(s))
            if w <> "" then words.Push(w)
        end for
    end if
    full = words.Join("")
    bare = full
    if words.Count() > 1 then
        if words[0] = "the" or words[0] = "a" or words[0] = "an" then bare = suffixFrom(words, 1).Join("")
    end if
    return {full: full, bare: bare}
end function

' The words of a title with non-ASCII letters: accented Latin letters lose their accents (as NFD plus dropping the marks
' does), combining marks go, ς reads as σ.
' ponytail: a fold table for Latin-1 and Latin Extended-A, not full NFD; other scripts keep their letters as they are.
function TS_unicodeWords(s as String) as Object
    fold = TS_foldTable()
    words = []
    cur = ""
    n = Len(s)
    for i = 1 to n
        c = Mid(s, i, 1)
        r = fold[c]
        if r <> invalid then
            cur = cur + r
        else
            lc = LCase(c)
            cp = Asc(lc)
            if cp >= &h300 and cp <= &h36F then
                ' a combining mark: dropped, not a word break
            else if (cp >= 48 and cp <= 57) or (cp >= 97 and cp <= 122) or (cp >= 128 and isLetterCode(cp)) then
                cur = cur + lc
            else if cur <> "" then
                words.Push(cur)
                cur = ""
            end if
        end if
    end for
    if cur <> "" then words.Push(cur)
    return words
end function

function TS_foldTable() as Object
    g = GetGlobalAA()
    if g.tsFold <> invalid then return g.tsFold
    t = newMap()
    groups = [
        ["a", "àáâãäåāăąÀÁÂÃÄÅĀĂĄ"], ["c", "çćĉċčÇĆĈĊČ"], ["d", "ďĎ"], ["e", "èéêëēĕėęěÈÉÊËĒĔĖĘĚ"],
        ["g", "ĝğġģĜĞĠĢ"], ["h", "ĥĤ"], ["i", "ìíîïĩīĭįÌÍÎÏĨĪĬĮİ"], ["j", "ĵĴ"], ["k", "ķĶ"], ["l", "ĺļľĹĻĽ"],
        ["n", "ñńņňÑŃŅŇ"], ["o", "òóôõöōŏőÒÓÔÕÖŌŎŐ"], ["r", "ŕŗřŔŖŘ"], ["s", "śŝşšŚŜŞŠ"], ["t", "ţťŢŤ"],
        ["u", "ùúûüũūŭůűųÙÚÛÜŨŪŬŮŰŲ"], ["w", "ŵŴ"], ["y", "ýÿŷÝŶŸ"], ["z", "źżžŹŻŽ"], ["σ", "ςΣ"]
    ]
    for each grp in groups
        chars = grp[1]
        for i = 1 to Len(chars)
            t[Mid(chars, i, 1)] = grp[0]
        end for
    end for
    g.tsFold = t
    return t
end function

' The earliest airing of each entry across `lineups` ([{channel, slots}]) from `now` to `window` on, but not past
' tomorrow: an AA by entry id (case-sensitive) of {channelID, number, name, start}.
function TitleSearch_nextAirings(lineups as Object, index as Object, now as Double, window = 86400 as Integer) as Object
    ' No further than tomorrow, so "Tomorrow" stays true: a spring-forward day is 23 hours.
    finish = minD(now + window, Time_addDays(Time_startOfDay(now), 2))
    best = newMap()
    for each l in lineups
        ch = l.channel
        for each s in l.slots
            if s.start < finish and Slot_itemEnd(s) > now then
                id = index.entryOf[s.item.id]
                if id <> invalid then
                    b = best[id]
                    if b = invalid or not (b.start < s.start or (b.start = s.start and b.number <= ch.number)) then
                        best[id] = {channelID: ch.id, number: ch.number, name: ch.name, start: s.start}
                    end if
                end if
            end if
        end for
    end for
    return best
end function

' "On now · Ch 5 Fright Night, 40 min in", "Today 3:00 PM · Ch 5 Fright Night", "Tonight 10:00 PM · …" (later today from
' 6 PM), "Tomorrow 2:00 PM · Ch 22 Gumshoe", or "Not scheduled in the next 24 hours". `clock` is "10:00 PM".
function TitleSearch_airsText(a as Dynamic, now as Double, clock as Function) as String
    if a = invalid then return "Not scheduled in the next 24 hours"
    ch = "Ch " + iStr(a.number) + " " + a.name
    if a.start <= now then return "On now · " + ch + ", " + iStr(Fix((now - a.start) / 60)) + " min in"
    if Time_startOfDay(a.start) <> Time_startOfDay(now) then
        day = "Tomorrow"
    else if Time_localHour(a.start) >= 18 then
        day = "Tonight"
    else
        day = "Today"
    end if
    return day + " " + clock(a.start) + " · " + ch
end function
