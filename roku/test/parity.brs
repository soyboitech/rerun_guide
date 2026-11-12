' web/test/parity.test.ts for the Roku port: the Swift Core's output for the demo library (parity-fixture.json, written
' by tools/fixturegen) must come out value for value, so a channel airs the same thing at the same minute on an Apple TV,
' a Google TV, an LG or Samsung TV and a Roku. Run by `npm test` in roku/ (build.mjs): brs-cli with the fixture's folder
' mounted as ext1: and the zone pinned to Los Angeles. Prints one line per failure and a PASS/FAIL summary.

sub main()
    t = {fails: 0, checks: 0, printed: 0}
    f = ParseJson(ReadAsciiFile("ext1:/parity-fixture.json"))
    if f = invalid then
        print "FAIL could not read ext1:/parity-fixture.json"
        return
    end if
    now = f.now * 1#
    ' The demo's addedAt pinned to the fixture's now, and every third film watched (m3, m6, ...), as in fixturegen.
    lib = []
    for each it in DemoServer_items(now)
        if it.kind = "movie" then it.watched = (Val(Mid(it.id, 2)) mod 3) = 0
        lib.Push(it)
    end for

    PT_seeded(t, f)
    PT_fnv(t, f)
    PT_demoItems(t, f, lib)
    PT_automatic(t, f, lib, now)
    PT_channels(t, f, lib, now)
    PT_continuity(t, f, lib, now)
    PT_turns(t, f)
    PT_exclusive(t, f, lib, now)
    PT_packed(t, f, now)
    PT_holidays(t, f)
    PT_dedup(t, f)
    PT_persisted(t, lib)

    if t.fails = 0 then
        print "PASS parity: " + iStr(t.checks) + " checks"
    else
        print "FAIL parity: " + iStr(t.fails) + " of " + iStr(t.checks) + " checks failed"
    end if
end sub

sub PT_check(t as Object, ok as Boolean, label as String)
    t.checks = t.checks + 1
    if not ok then
        t.fails = t.fails + 1
        if t.printed < 40 then print "FAIL " + label
        t.printed = t.printed + 1
    end if
end sub

' Two lists of strings, element by element; one failure names the first difference.
sub PT_eqList(t as Object, got as Object, want as Object, label as String)
    if got.Count() <> want.Count() then
        PT_check(t, false, label + ": " + iStr(got.Count()) + " rows, want " + iStr(want.Count()) + PT_firstDiff(got, want))
        return
    end if
    for i = 0 to got.Count() - 1
        if got[i] <> want[i] then
            PT_check(t, false, label + " [" + iStr(i) + "]: " + got[i] + " want " + want[i])
            return
        end if
    end for
    PT_check(t, true, label)
end sub

function PT_firstDiff(got as Object, want as Object) as String
    n = got.Count()
    if want.Count() < n then n = want.Count()
    for i = 0 to n - 1
        if got[i] <> want[i] then return " (first difference [" + iStr(i) + "]: " + got[i] + " want " + want[i] + ")"
    end for
    return ""
end function

' Slots as "id start end".
function PT_rows(slots as Object) as Object
    out = []
    for each s in slots
        out.Push(s.item.id + " " + iStr(s.start) + " " + iStr(s.finish))
    end for
    return out
end function

' The fixture's slots, as {item, start, end} or [id, start, end].
function PT_wantRows(slots as Object) as Object
    out = []
    for each s in slots
        if type(s) = "roAssociativeArray" then
            out.Push(s.item + " " + iStr(s.start) + " " + iStr(s["end"]))
        else
            out.Push(s[0] + " " + iStr(s[1]) + " " + iStr(s[2]))
        end if
    end for
    return out
end function

function PT_strs(a as Object) as Object
    out = []
    for each v in a
        if type(v) = "String" or type(v) = "roString" then out.Push(v) else out.Push(PT_val(v))
    end for
    return out
end function

function PT_val(v as Dynamic) as String
    if v = invalid then return "null"
    ty = type(v)
    if ty = "String" or ty = "roString" then return v
    if ty = "Boolean" or ty = "roBoolean" then
        if v then return "true"
        return "false"
    end if
    if ty = "roArray" then return "[" + PT_strs(v).Join(",") + "]"
    if ty = "Float" or ty = "Double" or ty = "roFloat" or ty = "roDouble" then
        if v = Int(v) then return iStr(v)
        return Str(v).Trim()
    end if
    return v.ToStr()
end function

sub PT_seeded(t as Object, f as Object)
    g = SeededGenerator("parity|2026-10-24")
    got = []
    for i = 1 to 8
        got.Push(U64_toStr(g.nextRaw()))
    end for
    PT_eqList(t, got, f.seeded, "seeded")
    nums = []
    for i = 0 to 19
        nums.Push(i)
    end for
    PT_eqList(t, PT_strs(shuffled(nums, SeededGenerator("shuffle-check"))), PT_strs(f.shuffle20), "shuffle20")
    g3 = SeededGenerator("bounded")
    got = []
    for i = 0 to 11
        got.Push(g3.nextInt((i + 3) * 7))
    end for
    PT_eqList(t, PT_strs(got), PT_strs(f.bounded), "bounded")
end sub

sub PT_fnv(t as Object, f as Object)
    PT_check(t, f.fnv1a.Count() = 5, "fnv1a cases")
    for each c in f.fnv1a
        h = U64_toStr(StableHash_fnv1a(c.s))
        PT_check(t, h = c.h, "fnv1a '" + c.s + "': " + h + " want " + c.h)
    end for
end sub

sub PT_demoItems(t as Object, f as Object, lib as Object)
    want = f.demoItems
    PT_check(t, lib.Count() = want.Count(), "demo item count")
    for i = 0 to want.Count() - 1
        w = want[i]
        it = lib[i]
        got = [it.id, it.kind, it.title, PT_val(it.runtime), PT_val(it.year), PT_val(it.genres), PT_val(it.seriesID), PT_val(it.watched)]
        exp = [w.id, w.kind, w.title, PT_val(w.runtime), PT_val(w.year), PT_val(w.genres), PT_val(w.seriesID), PT_val(w.watched)]
        PT_eqList(t, got, exp, "demo item " + w.id)
    end for
end sub

sub PT_automatic(t as Object, f as Object, lib as Object, now as Double)
    defs = ChannelBuilder_automaticChannels(lib, 4, 24, 12, now)
    want = f.automatic
    got = []
    for each d in defs
        got.Push(d.id)
    end for
    exp = []
    for each w in want
        exp.Push(w.id)
    end for
    PT_eqList(t, got, exp, "automatic ids")
    if defs.Count() <> want.Count() then return
    for i = 0 to want.Count() - 1
        d = defs[i]
        w = want[i]
        labels = []
        for each c in d.rule
            labels.Push(RuleChip_label(c))
        end for
        PT_eqList(t, [iStr(d.number), d.name, d.tag, labels.Join(" + "), PlayOrder_rawValue(d.order)],
            [iStr(w.number), w.name, w.tag, w.rule.Join(" + "), w.order], "automatic " + w.id)
    end for
end sub

function PT_demoChannels(lib as Object, now as Double) as Object
    return ChannelBuilder_channelsFrom(ChannelBuilder_automaticChannels(lib, 4, 24, 12, now), lib, now)
end function

function PT_find(chans as Object, id as String) as Dynamic
    for each c in chans
        if c.id = id then return c
    end for
    return invalid
end function

sub PT_channels(t as Object, f as Object, lib as Object, now as Double)
    chans = PT_demoChannels(lib, now)
    chans.Push(Channel_scrambled())
    want = f.channels
    got = []
    for each c in chans
        got.Push(c.id)
    end for
    exp = []
    for each w in want
        exp.Push(w.id)
    end for
    PT_eqList(t, got, exp, "channel ids")
    if chans.Count() <> want.Count() then return
    today = Time_startOfDay(now)
    lineupDays = []
    for d = 0 to 2   ' one pass a day, as the app
        lineupDays.Push(GuideGenerator_scheduleLineup(chans, Time_addDays(today, d)))
    end for
    slotCount = 0
    for c = 0 to want.Count() - 1
        ch = chans[c]
        w = want[c]
        ids = []
        for each it in ch.items
            ids.Push(it.id)
        end for
        PT_eqList(t, ids, w.items, ch.id + " items")
        PT_check(t, w.days.Count() = 3, ch.id + " days")
        for d = 0 to 2
            wd = w.days[d]
            day = Time_addDays(today, d)
            PT_check(t, iStr(day) = iStr(wd.day), ch.id + " day " + iStr(d) + " starts " + iStr(day) + " want " + iStr(wd.day))
            s = lineupDays[d][ch.id]
            if s = invalid then s = []
            PT_eqList(t, PT_rows(s), PT_wantRows(wd.slots), ch.id + " day " + iStr(d))
            slotCount = slotCount + s.Count()
        end for
    end for
    PT_check(t, slotCount > 1000, "over 1000 slots")
end sub

sub PT_continuity(t as Object, f as Object, lib as Object, now as Double)
    chans = PT_demoChannels(lib, now)
    for each w in f.continuity
        ch = PT_find(chans, w.id)
        for each wd in w.days
            PT_eqList(t, PT_rows(GuideGenerator_schedule(ch, wd.day * 1#)), PT_wantRows(wd.slots), "continuity " + w.id + " " + iStr(wd.day))
        end for
    end for
end sub

function PT_turnsChannel(f as Object) as Object
    items = []
    for each r in f.turns.items
        items.Push(MediaItem_new({id: r.id, kind: "episode", title: r.title, seriesTitle: r.seriesTitle, seriesID: r.seriesID,
            season: r.season, episode: r.episode, runtime: r.runtime}))
    end for
    return Channel_make("turns", 2, "Turns", items)
end function

sub PT_turns(t as Object, f as Object)
    ch = PT_turnsChannel(f)
    PT_check(t, GuideGenerator_takesTurns(ch), "turns takes turns")
    for each wd in f.turns.days
        PT_eqList(t, PT_rows(GuideGenerator_schedule(ch, wd.day * 1#)), PT_wantRows(wd.slots), "turns " + iStr(wd.day))
    end for
end sub

sub PT_exclusive(t as Object, f as Object, lib as Object, now as Double)
    films = []
    for each r in f.exclusive.films
        films.Push(MediaItem_new({id: r.id, kind: "movie", title: r.title, year: r.year, runtime: r.runtime}))
    end for
    chans = PT_demoChannels(lib, now)
    b = []
    for i = 1 to 9
        b.Push(MediaItem_new({id: "B" + iStr(i), kind: "episode", title: "B " + iStr(i), seriesTitle: "B", seriesID: "B", season: 1,
            episode: i, runtime: 1320}))
    end for
    lineup = [Channel_make("x1", 10, "X1", films), Channel_make("x2", 11, "X2", films), PT_find(chans, "series:smh"),
        PT_find(chans, "genre:Comedy:tv"), PT_turnsChannel(f), Channel_make("series:B", 30, "B", b, "", "inOrder")]
    got = []
    for each c in GuideGenerator_dependencyOrder(lineup)
        got.Push(c.id)
    end for
    PT_eqList(t, got, f.exclusive.order, "exclusive order")
    for each wd in f.exclusive.days
        all = GuideGenerator_scheduleLineup(lineup, wd.day * 1#)
        for each c in wd.channels
            PT_eqList(t, PT_rows(all[c.id]), PT_wantRows(c.slots), "exclusive " + c.id + " " + iStr(wd.day))
        end for
    end for
end sub

sub PT_packed(t as Object, f as Object, now as Double)
    ' Short programs sharing a half hour, with fractional runtimes as servers report them.
    runtimes = [130.7#, 245.2#, 480.4#, 540.9#, 701.0#, 150.0#, 453.3#, 720.0#, 780.0#, 1320.0#]
    shorts = []
    for i = 0 to runtimes.Count() - 1
        shorts.Push(MediaItem_new({id: "s" + iStr(i), kind: "episode", title: "S" + iStr(i), seriesTitle: "Shorts", seriesID: "shorts",
            season: 1, episode: i + 1, runtime: runtimes[i]}))
    end for
    chans = [Channel_make("shorts", 2, "Shorts", shorts, "", "inOrder"), Channel_make("shorts-mix", 3, "Mix", shorts, "", "shuffle")]
    today = Time_startOfDay(now)
    for c = 0 to 1
        for d = 0 to 2
            PT_eqList(t, PT_rows(GuideGenerator_schedule(chans[c], Time_addDays(today, d))), PT_wantRows(f.packed[c][d]), chans[c].id + " packed day " + iStr(d))
        end for
    end for
end sub

sub PT_holidays(t as Object, f as Object)
    h = f.holidays
    PT_check(t, h.easter.Count() = 41 and h.thanksgiving.Count() = 41, "holiday year counts")
    for each e in h.easter
        md = Holiday_date("easter", e[0])
        PT_check(t, md[0] = e[1] and md[1] = e[2], "Easter " + iStr(e[0]))
    end for
    for each e in h.thanksgiving
        PT_check(t, Holiday_date("thanksgiving", e[0])[1] = e[1], "Thanksgiving " + iStr(e[0]))
    end for
    films = []
    for each w in h.films
        overview = w.overview
        if overview = "" then overview = invalid
        films.Push(MediaItem_new({id: w.id, kind: "movie", title: w.title, genres: w.genres, runtime: w.runtime, overview: overview}))
    end for
    thin = []
    for each it in films
        if startsWith(it.id, "halloween") or startsWith(it.id, "christmas") then thin.Push(it)
    end for
    for each pair in [[films, h.days, "full"], [thin, h.thin, "thin"]]
        PT_check(t, pair[1].Count() = 730, "holiday days " + pair[2])
        for each w in pair[1]
            p = Holiday_pick(pair[0], w[0] * 1#)
            ids = []
            for each it in p.films
                ids.Push(it.id)
            end for
            PT_eqList(t, concat([p.name], ids), concat([w[1]], w[2]), "holiday " + pair[2] + " " + iStr(w[0]))
        end for
    end for
    ch = Channel_new(ChannelDefinition_new({id: "holiday", number: 2, name: "Holiday Special", tag: "", rule: [RuleChip_holiday()]}), films)
    PT_check(t, h.slots.Count() = 7, "holiday slot days")
    for each w in h.slots
        PT_eqList(t, PT_rows(GuideGenerator_schedule(ch, w.day * 1#)), PT_wantRows(w.slots), "holiday channel " + iStr(w.day))
    end for
end sub

sub PT_dedup(t as Object, f as Object)
    items = []
    for each w in f.dedup.input
        if w.kind = "movie" then runtime = 6000 else runtime = 1320
        items.Push(MediaItem_new({id: w.id, kind: w.kind, title: w.title, seriesTitle: w.seriesTitle, seriesID: w.seriesID,
            season: w.season, episode: w.episode, year: w.year, runtime: runtime, libraryID: w.libraryID, addedAt: w.addedAt,
            watched: w.watched}))
    end for
    last = newMap()
    for each id in f.dedup.lastResort
        last[id] = true
    end for
    got = []
    for each it in Duplicates_merge(items, last)
        got.Push(it.id + " " + PT_val(it.seriesID) + " " + PT_val(it.watched) + " " + PT_val(it.addedAt))
    end for
    exp = []
    for each w in f.dedup.merged
        exp.Push(w.id + " " + PT_val(w.seriesID) + " " + PT_val(w.watched) + " " + PT_val(w.addedAt))
    end for
    PT_eqList(t, got, exp, "dedup merge")
end sub

' Not from the fixture: what the app persists comes back equal.
sub PT_persisted(t as Object, lib as Object)
    def = ChannelDefinition_new({id: "c", number: 7, name: "N", tag: "T", order: "newestFirst", trailerBreaks: false, isCustom: true,
        tuneMode: "start", rule: [RuleChip_genre("G"), RuleChip_years(1900, 1969), RuleChip_director("D"), RuleChip_actor("A"),
        RuleChip_series("s", "S"), RuleChip_year(1985), RuleChip_movies(), RuleChip_tv(), RuleChip_addedWithin(60),
        RuleChip_anyGenre(["x", "y"]), RuleChip_keywords(["k"])]})
    back = ChannelDefinition_fromJson(ParseJson(FormatJson(ChannelDefinition_toJson(def))))
    PT_check(t, FormatJson(ChannelDefinition_toJson(back)) = FormatJson(ChannelDefinition_toJson(def)), "definition round trip")
    for each it in lib
        b = MediaItem_fromJson(ParseJson(FormatJson(MediaItem_toJson(it))))
        PT_check(t, b <> invalid and FormatJson(MediaItem_toJson(b)) = FormatJson(MediaItem_toJson(it)), "item round trip " + it.id)
    end for
end sub
