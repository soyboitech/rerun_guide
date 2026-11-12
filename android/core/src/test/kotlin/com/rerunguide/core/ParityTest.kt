package com.rerunguide.core

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * The Swift Core's output for the demo library (parity-fixture.json, written by tools/fixturegen against
 * RerunGuideCore): the Kotlin port must agree value for value, so a channel airs the same thing at the same minute on
 * an Apple TV and a Google TV.
 */
class ParityTest {
    private val f = JSONObject(javaClass.getResource("/parity-fixture.json")!!.readText())
    private val zone = ZoneId.of(f.getString("timeZone"))
    private val now = instantOf(f.getDouble("now"))

    /**
     * The demo's addedAt is relative to the wall clock when the library loads; the fixture ran at `now` (give or take
     * minutes), so pin it there or "Just Added" drifts as the days pass. Every third film (m3, m6, ...) is watched, as in
     * fixturegen, so Unwatched is checked too.
     */
    private val lib = DemoMediaServer.items.map { m ->
        if (m.addedAt == null) m else m.id.drop(1).toInt().let { n ->
            m.copy(addedAt = now.plusSeconds(-(n * 6).toDouble() * 86_400), watched = n % 3 == 0)
        }
    }

    private fun strings(a: JSONArray) = (0 until a.length()).map { a.get(it).toString() }

    @Test fun testSeededGenerator() {
        val g = SeededGenerator(seed = "parity|2026-10-24")
        assertEquals(strings(f.getJSONArray("seeded")), List(8) { g.next().toString() })
        val g2 = SeededGenerator(seed = "shuffle-check")
        assertEquals(strings(f.getJSONArray("shuffle20")), (0 until 20).toList().shuffled(using = g2).map { it.toString() })
        val g3 = SeededGenerator(seed = "bounded")
        assertEquals(strings(f.getJSONArray("bounded")), (0 until 12).map { i -> g3.nextInt((i + 3) * 7).toString() })
    }

    @Test fun testFnv1a() {
        val cases = f.getJSONArray("fnv1a").objects()
        assertEquals(5, cases.size)
        for (c in cases) assertEquals(c.getString("s"), c.getString("h"), StableHash.fnv1a(c.getString("s")).toString())
    }

    @Test fun testDemoItems() {
        val want = f.getJSONArray("demoItems").objects()
        assertEquals(want.size, lib.size)
        for ((w, m) in want.zip(lib)) {
            assertEquals(w.getString("id"), m.id)
            assertEquals(w.getString("kind"), m.kind.rawValue)
            assertEquals(w.getString("title"), m.title)
            assertEquals(w.getDouble("runtime"), m.runtime, 0.0)
            assertEquals(w.intOrNull("year"), m.year)
            assertEquals(w.strings("genres"), m.genres)
            assertEquals(w.stringOrNull("seriesID"), m.seriesID)
            assertEquals(w.getBoolean("watched"), m.watched)
        }
    }

    @Test fun testAutomaticChannels() {
        val want = f.getJSONArray("automatic").objects()
        val defs = ChannelBuilder.automaticChannels(from = lib, now = now)
        assertEquals(want.map { it.getString("id") }, defs.map { it.id })
        for ((w, d) in want.zip(defs)) {
            assertEquals(w.getString("id"), w.getInt("number"), d.number)
            assertEquals(w.getString("name"), d.name)
            assertEquals(w.getString("tag"), d.tag)
            assertEquals(w.strings("rule"), d.rule.map { it.label })
            assertEquals(w.getString("order"), d.order.rawValue)
        }
    }

    @Test fun testChannelsAndThreeDaysOfSlots() {
        val want = f.getJSONArray("channels").objects()
        val chans = ChannelBuilder.channels(ChannelBuilder.automaticChannels(from = lib, now = now), lib, now = now) + Channel.scrambled
        assertEquals(want.map { it.getString("id") }, chans.map { it.id })
        val today = now.atZone(zone).toLocalDate().atStartOfDay(zone)
        // One lineup pass a day, as the app schedules it.
        val lineupDays = (0 until 3).map { GuideGenerator.schedule(chans, today.plusDays(it.toLong()).toInstant(), zone) }
        var slotCount = 0
        for ((w, ch) in want.zip(chans)) {
            assertEquals(ch.id, w.strings("items"), ch.items.map { it.id })
            val days = w.getJSONArray("days").objects()
            assertEquals(3, days.size)
            for ((d, wd) in days.withIndex()) {
                val day = today.plusDays(d.toLong()).toInstant()
                assertEquals(wd.getDouble("day"), day.epochSeconds, 0.0)
                val got = lineupDays[d][ch.id] ?: emptyList()
                val ws = wd.getJSONArray("slots").objects()
                assertEquals("${ch.id} day $d", ws.map { listOf(it.getString("item"), it.getDouble("start"), it.getDouble("end")) },
                             got.map { listOf(it.item.id, it.start.epochSeconds, it.end.epochSeconds) })
                slotCount += got.size
            }
        }
        assertEquals(true, slotCount > 1000)
    }

    private fun rows(a: JSONArray) = (0 until a.length()).map { a.getJSONArray(it).let { s -> listOf(s.getString(0), s.getDouble(1), s.getDouble(2)) } }
    private fun rows(slots: List<Slot>) = slots.map { listOf(it.item.id, it.start.epochSeconds, it.end.epochSeconds) }
    private val demoChannels by lazy { ChannelBuilder.channels(ChannelBuilder.automaticChannels(from = lib, now = now), lib, now = now) }

    /** The tape on its own: two marathons and the two-show Comedy TV shelf over both DST changes and New Year. */
    @Test fun testContinuity() {
        for (w in f.getJSONArray("continuity").objects()) {
            val ch = demoChannels.first { it.id == w.getString("id") }
            for (wd in w.getJSONArray("days").objects()) {
                assertEquals("${ch.id} ${wd.getDouble("day")}", rows(wd.getJSONArray("slots")), rows(GuideGenerator.schedule(ch, instantOf(wd.getDouble("day")), zone)))
            }
        }
    }

    private val turns by lazy {
        Channel(id = "turns", number = 2, name = "Turns", items = f.getJSONObject("turns").getJSONArray("items").objects().map {
            MediaItem(id = it.getString("id"), kind = MediaItem.Kind.episode, title = it.getString("title"), seriesTitle = it.getString("seriesTitle"),
                      seriesID = it.getString("seriesID"), season = it.getInt("season"), episode = it.getInt("episode"), runtime = it.getDouble("runtime"))
        })
    }

    /** Shows taking turns: four shows handed over interleaved. */
    @Test fun testTurns() {
        assertEquals(true, GuideGenerator.takesTurns(turns))
        for (wd in f.getJSONObject("turns").getJSONArray("days").objects()) {
            assertEquals(rows(wd.getJSONArray("slots")), rows(GuideGenerator.schedule(turns, instantOf(wd.getDouble("day")), zone)))
        }
    }

    /** One program on one channel at a time: the order channels give way in, their slots, and no overlap in the rows.
     *  The lineup ends with the turns channel behind a marathon of nine episodes of its show B (B1 and B2 shared). */
    @Test fun testExclusive() {
        val x = f.getJSONObject("exclusive")
        val films = x.getJSONArray("films").objects().map {
            MediaItem(id = it.getString("id"), kind = MediaItem.Kind.movie, title = it.getString("title"), year = it.getInt("year"), runtime = it.getDouble("runtime"))
        }
        val b = (1..9).map { MediaItem(id = "B$it", kind = MediaItem.Kind.episode, title = "B $it", seriesTitle = "B", seriesID = "B", season = 1, episode = it, runtime = 1320.0) }
        val lineup = listOf(Channel(id = "x1", number = 10, name = "X1", items = films), Channel(id = "x2", number = 11, name = "X2", items = films),
                            demoChannels.first { it.id == "series:smh" }, demoChannels.first { it.id == "genre:Comedy:tv" },
                            turns, Channel(id = "series:B", number = 30, name = "B", items = b, order = PlayOrder.inOrder))
        assertEquals(strings(x.getJSONArray("order")), GuideGenerator.dependencyOrder(lineup).map { it.id })
        for (wd in x.getJSONArray("days").objects()) {
            val got = GuideGenerator.schedule(lineup, instantOf(wd.getDouble("day")), zone)
            val want = wd.getJSONArray("channels").objects()
            for (c in want) assertEquals(c.getString("id"), rows(c.getJSONArray("slots")), rows(got.getValue(c.getString("id"))))
            // The rule itself, over the fixture's own rows: one item's airing windows never overlap on two channels.
            val byItem = HashMap<String, MutableList<Triple<String, Double, Double>>>()
            for (c in want) for (r in rows(c.getJSONArray("slots"))) {
                val item = (films + lineup.flatMap { it.items }).first { it.id == r[0] }
                byItem.getOrPut(GuideGenerator.repeatKey(item)) { mutableListOf() }.add(Triple(c.getString("id"), r[1] as Double, minOf(r[2] as Double, r[1] as Double + item.runtime)))
            }
            for ((k, ws) in byItem) for (i in ws.indices) for (j in i + 1 until ws.size) {
                if (ws[i].first != ws[j].first) assertEquals("$k ${ws[i]} ${ws[j]}", false, ws[i].second < ws[j].third && ws[j].second < ws[i].third)
            }
        }
    }

    /** Short programs sharing a half hour, with fractional runtimes as servers report them: in order and shuffled. */
    @Test fun testPackedShortPrograms() {
        val shorts = listOf(130.7, 245.2, 480.4, 540.9, 701.0, 150.0, 453.3, 720.0, 780.0, 1320.0).mapIndexed { i, r ->
            MediaItem(id = "s$i", kind = MediaItem.Kind.episode, title = "S$i", seriesTitle = "Shorts", seriesID = "shorts", season = 1, episode = i + 1, runtime = r)
        }
        val chans = listOf(Channel(id = "shorts", number = 2, name = "Shorts", items = shorts, order = PlayOrder.inOrder),
                           Channel(id = "shorts-mix", number = 3, name = "Mix", items = shorts, order = PlayOrder.shuffle))
        val want = f.getJSONArray("packed")
        val today = now.atZone(zone).toLocalDate().atStartOfDay(zone)
        for ((c, ch) in chans.withIndex()) for (d in 0 until 3) {
            val ws = want.getJSONArray(c).getJSONArray(d)
            val got = GuideGenerator.schedule(ch, day = today.plusDays(d.toLong()).toInstant(), calendar = zone)
            assertEquals("${ch.id} day $d", (0 until ws.length()).map { ws.getJSONArray(it).let { s -> listOf(s.getString(0), s.getDouble(1), s.getDouble(2)) } },
                         got.map { listOf(it.item.id, it.start.epochSeconds, it.end.epochSeconds) })
        }
    }

    @Test fun testBouncer() {
        val want = f.getJSONArray("bouncer")
        val b = Bouncer(stage = 1920.0 to 1080.0, logo = 400.0 to 400.0, start = 300.0 to 200.0)
        val got = mutableListOf<List<Double>>()
        for (i in 1..(60 * 60 * 3)) { b.step(1.0 / 60); if (i % 600 == 0) got.add(listOf(b.time, b.x, b.y, b.vx, b.vy, b.corners.toDouble())) }
        assertEquals(want.length(), got.size)
        for ((i, g) in got.withIndex()) {
            val w = want.getJSONArray(i)
            for (k in 0 until 6) assertEquals("sample $i field $k", w.getDouble(k), g[k], 0.0)
        }
    }

    /**
     * The holiday channel's calendar: Easter and Thanksgiving for 2000 to 2040, and what each day of 2026 and 2027 airs
     * (noon in the fixture's zone), for a library with every holiday (and Groundhog Day) and for one with only Halloween
     * and Christmas; and what the channel itself airs on 7 of those days, slot by slot.
     */
    @Test fun testHolidays() {
        val h = f.getJSONObject("holidays")
        fun ints(key: String) = h.getJSONArray(key).let { a -> (0 until a.length()).map { a.getJSONArray(it).let { r -> (0 until r.length()).map(r::getInt) } } }
        assertEquals(ints("easter"), (2000..2040).map { y -> Holiday.easter.date(y).let { (m, d) -> listOf(y, m, d) } })
        assertEquals(ints("thanksgiving"), (2000..2040).map { y -> listOf(y, Holiday.thanksgiving.date(y).second) })
        val films = h.getJSONArray("films").objects().map {
            MediaItem(id = it.getString("id"), kind = MediaItem.Kind.movie, title = it.getString("title"), genres = it.strings("genres"),
                      runtime = it.getDouble("runtime"), overview = it.getString("overview").ifEmpty { null })
        }
        assertEquals(33, films.size)
        val thin = films.filter { it.id.startsWith("halloween") || it.id.startsWith("christmas") }
        val noon = ZonedDateTime.of(2026, 1, 1, 12, 0, 0, 0, zone)
        for ((key, lib) in listOf("days" to films, "thin" to thin)) {
            val want = h.getJSONArray(key)
            assertEquals(730, want.length())
            for (i in 0 until want.length()) {
                val w = want.getJSONArray(i)
                val day = noon.plusDays(i.toLong()).toInstant()
                val p = Holiday.pick(lib, on = day, calendar = zone)
                assertEquals("$key day $i", listOf(w.getDouble(0), w.getString(1), strings(w.getJSONArray(2))), listOf(day.epochSeconds, p.name, p.films.map { it.id }))
            }
        }
        val ch = Channel(ChannelDefinition(id = "holiday", number = 2, name = "Holiday Special", tag = "", rule = listOf(RuleChip.holiday)), films)
        val days = h.getJSONArray("slots").objects()
        assertEquals(7, days.size)
        for (d in days) {
            val day = instantOf(d.getDouble("day"))
            val ws = d.getJSONArray("slots")
            assertEquals("slots $day", (0 until ws.length()).map { ws.getJSONArray(it).let { s -> listOf(s.getString(0), s.getDouble(1), s.getDouble(2)) } },
                         GuideGenerator.schedule(ch, day = day, calendar = zone).map { listOf(it.item.id, it.start.epochSeconds, it.end.epochSeconds) })
        }
    }

    /**
     * Copies in a second library (punctuation and accents differ), a cut, films with no year, one item twice, a show in
     * two libraries, one whose libraries come interleaved, shows of one name, empty titles and 4K copies (last resort):
     * what the merge keeps, in order, with its show, watched and added.
     */
    @Test fun testDedup() {
        val d = f.getJSONObject("dedup")
        val items = d.getJSONArray("input").objects().map {
            val kind = MediaItem.Kind.valueOf(it.getString("kind"))
            MediaItem(id = it.getString("id"), kind = kind, title = it.getString("title"), seriesTitle = it.stringOrNull("seriesTitle"),
                      seriesID = it.stringOrNull("seriesID"), season = it.intOrNull("season"), episode = it.intOrNull("episode"),
                      year = it.intOrNull("year"), runtime = if (kind == MediaItem.Kind.movie) 6000.0 else 1320.0,
                      libraryID = it.stringOrNull("libraryID"), addedAt = it.doubleOrNull("addedAt")?.let(::instantOf),
                      watched = it.getBoolean("watched"))
        }
        assertEquals(28, items.size)
        val lastResort = strings(d.getJSONArray("lastResort")).toSet()
        assertEquals(setOf("4k"), lastResort)
        assertEquals(d.getJSONArray("merged").objects().map { listOf(it.getString("id"), it.stringOrNull("seriesID"), it.getBoolean("watched"), it.doubleOrNull("addedAt")) },
                     Duplicates.merge(items, lastResort).map { listOf(it.id, it.seriesID, it.watched, it.addedAt?.epochSeconds) })
    }

    @Test fun testSpotRotation() {
        val rot = SpotRotation()
        val got = (listOf("a", "b", "a", "c", "d", "d") + (1..30).map { "n$it" }).map { rot.next(it) }
        val want = f.getJSONArray("spotRotation")
        assertEquals((0 until want.length()).map { want.getBoolean(it) }, got)
    }

    /** Not from the fixture: what the app persists comes back equal (missing keys → defaults). */
    @Test fun testPersistedJsonRoundTrip() {
        val def = ChannelDefinition(id = "c", number = 7, name = "N", tag = "T", order = PlayOrder.newestFirst, trailerBreaks = false,
            isCustom = true, tuneMode = TuneMode.start, rule = listOf(RuleChip.genre("G"), RuleChip.years(1900, 1969), RuleChip.director("D"),
                RuleChip.actor("A"), RuleChip.series(id = "s", title = "S"), RuleChip.year(1985), RuleChip.movies, RuleChip.tv,
                RuleChip.addedWithin(days = 60), RuleChip.anyGenre(listOf("x", "y")), RuleChip.keywords(listOf("k")), RuleChip.unwatched, RuleChip.holiday))
        assertEquals(def, ChannelDefinition.fromJson(JSONObject(def.toJson().toString())))
        assertEquals(ChannelDefinition(id = "c", number = 0, name = "", tag = "", rule = emptyList()), ChannelDefinition.fromJson(JSONObject("""{"id":"c"}""")))
        for (m in lib + Channel.scrambled.items) assertEquals(m, MediaItem.fromJson(JSONObject(m.toJson().toString())))
        val t = TrackSelection(audioID = "2", subtitle = TrackSelection.Subtitle.track("5"))
        assertEquals(t, TrackSelection.fromJson(JSONObject(t.toJson().toString())))
        assertEquals(TrackSelection(), TrackSelection.fromJson(JSONObject(TrackSelection().toJson().toString())))
        val s = LibrarySection(id = "1", title = "Movies", kind = LibrarySection.Kind.movies, itemCount = 3)
        assertEquals(s, LibrarySection.fromJson(JSONObject(s.toJson().toString())))
        val a = PlexAddress(url = "http://10.0.0.2:32400", local = true)
        assertEquals(a, PlexAddress.fromJson(JSONObject(a.toJson().toString())))
    }
}
