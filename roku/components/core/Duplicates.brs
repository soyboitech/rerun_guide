' Port of web/src/core/Duplicates.ts: the same film or episode in two of the user's libraries comes back as two items;
' the library keeps one of each (the first in library order), watched if any copy is, added when the first copy was. A
' show whose episodes turn up in two libraries becomes one show. Cuts stay apart, and so do films with no year.

' What copies share, or invalid (never merged).
function Duplicates_key(item as Object) as Dynamic
    t = TitleSearch_keys(item.title).full
    if t = "" then return invalid
    if item.kind = "movie" then
        if item.year = invalid then return invalid
        return "movie|" + t + "|" + iStr(item.year)
    end if
    if item.seriesTitle = invalid or item.season = invalid or item.episode = invalid then return invalid
    y = 0
    if item.year <> invalid then y = item.year
    return "episode|" + TitleSearch_keys(item.seriesTitle).full + "|" + iStr(item.season) + "|" + iStr(item.episode) + "|" + t + "|" + iStr(y)
end function

' Libraries whose copies play only when no other library has the film: 4K ones. A Set (AA of true) of section ids.
function Duplicates_lastResort(sections as Object) as Object
    out = newMap()
    for each s in sections
        t = LCase(s.title)
        if Instr(1, t, "4k") > 0 or Instr(1, t, "uhd") > 0 or Instr(1, t, "2160") > 0 then out[s.id] = true
    end for
    return out
end function

function DUP_root(show as Object, id as String) as String
    while show[id] <> invalid
        id = show[id]
    end while
    return id
end function

' `items` with each film and episode once, in their order, but copies from `lastResort` libraries behind the rest.
function Duplicates_merge(items as Object, lastResort = invalid as Dynamic) as Object
    if lastResort = invalid then lastResort = newMap()
    ordered = items
    if lastResort.Count() > 0 then
        ordered = []
        late = []
        for each it in items
            lib = it.libraryID
            if lib = invalid then lib = ""
            if lastResort[lib] <> invalid then late.Push(it) else ordered.Push(it)
        end for
        ordered.Append(late)
    end if
    out = []
    at = newMap()
    ids = newMap()
    show = newMap()
    seen = newMap()
    nSeen = 0
    for each item in ordered
        if ids[item.id] = invalid then   ' one item listed twice (two chosen libraries sharing it) counts once
            ids[item.id] = true
            if item.seriesID <> invalid and seen[item.seriesID] = invalid then
                seen[item.seriesID] = nSeen   ' the order shows turn up in
                nSeen = nSeen + 1
            end if
            k = Duplicates_key(item)
            if k = invalid then
                out.Push(item)
            else if at[k] = invalid then
                at[k] = out.Count()
                out.Push(item)
            else
                i = at[k]
                first = out[i]
                added = invalid
                if first.addedAt <> invalid and item.addedAt <> invalid then added = minD(first.addedAt, item.addedAt)
                out[i] = MediaItem_copy(first, {watched: first.watched or item.watched, addedAt: added})
                ' The copy's show and the kept one's are one show, under whichever turned up first.
                if item.seriesID <> invalid and first.seriesID <> invalid then
                    a = DUP_root(show, item.seriesID)
                    b = DUP_root(show, first.seriesID)
                    if a <> b then
                        sa = seen[a]
                        if sa = invalid then sa = 0
                        sb = seen[b]
                        if sb = invalid then sb = 0
                        if sa < sb then show[b] = a else show[a] = b
                    end if
                end if
            end if
        end if
    end for
    if show.Count() = 0 then return out
    merged = []
    for each it in out
        if it.seriesID = invalid then
            merged.Push(it)
        else
            r = DUP_root(show, it.seriesID)
            if r = it.seriesID then merged.Push(it) else merged.Push(MediaItem_copy(it, {seriesID: r}))
        end if
    end for
    return merged
end function
