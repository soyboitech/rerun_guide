package com.rerunguide.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * The holiday channel: each day the nearest holiday's films, Groundhog Day back to back on February 2, and a lineup
 * that keeps every other channel's number.
 */
class HolidayTests {
    private val cal: ZoneId = ZoneId.of("America/Los_Angeles")
    private fun date(y: Int, m: Int, d: Int, h: Int = 12): Instant = ZonedDateTime.of(y, m, d, h, 0, 0, 0, cal).toInstant()
    private fun film(id: String, title: String, overview: String? = null, genres: List<String> = emptyList()) =
        MediaItem(id = id, kind = MediaItem.Kind.movie, title = title, genres = genres, runtime = 5400.0, overview = overview)
    /**
     * Four films for every holiday, by its words alone (no genre or year: they would add shelves of their own), and
     * Groundhog Day.
     */
    private val films: List<MediaItem> = listOf(
        "newYear" to "A party on New Year’s Eve.", "valentines" to "A Valentine’s card goes astray.",
        "stPatricks" to "A leprechaun wants his gold back.", "easter" to "The Easter Bunny is missing.",
        "july4" to "Fireworks on the Fourth of July.", "halloween" to "Trick or treat on the wrong street.",
        "thanksgiving" to "Home for Thanksgiving.", "christmas" to "Santa Claus is stuck in the chimney.",
    ).flatMap { (name, overview) -> (0 until 4).map { film("$name$it", "Film $it", overview = overview) } } + film("ghd", "Groundhog Day")
    private fun pick(y: Int, m: Int, d: Int, films: List<MediaItem> = this.films): String =
        Holiday.pick(films, on = date(y, m, d), calendar = cal).name

    @Test fun testDates() {
        assertEquals(listOf(420, 405, 328), listOf(2025, 2026, 2027).map { Holiday.easter.date(it).let { (m, d) -> m * 100 + d } })
        assertEquals(listOf(27, 26, 25), listOf(2025, 2026, 2027).map { Holiday.thanksgiving.date(it).second })
        assertEquals(0, Holiday.dayNumber(1970, 1, 1))
        assertEquals(20_760, Holiday.dayNumber(2026, 11, 3))
        assertEquals(2, Holiday.weekday(2026, 11, 3))   // a Tuesday
    }

    @Test fun testSeasons() {
        assertEquals("Halloween", pick(2026, 10, 1))
        assertEquals("Halloween", pick(2026, 10, 31))
        assertEquals("Thanksgiving", pick(2026, 11, 1))
        assertEquals("Thanksgiving", pick(2025, 11, 1))   // with Thanksgiving on the 27th
        assertEquals("Halloween", pick(2025, 10, 31))
        assertEquals("Thanksgiving", pick(2026, 11, 26))
        assertEquals("Christmas", pick(2026, 11, 27))   // the day after Thanksgiving
        assertEquals("Thanksgiving", pick(2025, 11, 23))   // Thanksgiving 2025 is the 27th; Christmas's season overlaps
        assertEquals("Christmas", pick(2026, 12, 25))
        assertEquals("New Year’s", pick(2026, 12, 26))
        assertEquals("New Year’s", pick(2027, 1, 1))
        assertEquals("Valentine’s Day", pick(2027, 2, 1))
        assertEquals("Valentine’s Day", pick(2027, 2, 14))
        assertEquals("St. Patrick’s Day", pick(2027, 3, 17))
        assertEquals("Easter", pick(2027, 3, 28))
        assertEquals("Fourth of July", pick(2027, 7, 4))
        assertEquals("Fourth of July", pick(2027, 7, 5))   // between seasons: the nearest one
        assertEquals("Halloween", pick(2027, 9, 10))
    }

    @Test fun testGroundhogDay() {
        assertEquals("Groundhog Day", pick(2027, 2, 2))
        assertEquals(listOf("ghd"), Holiday.pick(films, on = date(2027, 2, 2), calendar = cal).films.map { it.id })
        assertEquals("Valentine’s Day", pick(2027, 2, 2, films.filter { it.id != "ghd" }))   // without the film, the season
        assertEquals("Valentine’s Day", pick(2027, 2, 3))
        // The day is the film again and again, with its break between.
        val ch = Channel(ChannelDefinition(id = "holiday", number = 2, name = "Holiday Special", tag = "", rule = listOf(RuleChip.holiday)), films)
        val slots = GuideGenerator.schedule(ch, day = date(2027, 2, 2), calendar = cal)
        assertEquals(setOf("ghd"), slots.map { it.item.id }.toSet())
        assertEquals(date(2027, 2, 2, 0), slots.first().start)
        assertEquals(12, slots.size)
        // A cut of the film counts too.
        assertEquals("Groundhog Day", pick(2027, 2, 2, films.filter { it.id != "ghd" } + film("ghd4k", "Groundhog Day (Remastered)")))
        // The day after is Valentine's again.
        assertTrue(GuideGenerator.schedule(ch, day = date(2027, 2, 3), calendar = cal).all { it.item.id.startsWith("valentines") })
    }

    /** A holiday with too few films sits out: its days go to the nearest one that has enough. */
    @Test fun testThinHolidaysSitOut() {
        val some = films.filter { !it.id.startsWith("thanksgiving") } + film("tg", "Pieces of April", overview = "Thanksgiving dinner.")
        assertEquals("Halloween", pick(2026, 11, 10, some))
        assertEquals("Christmas", pick(2026, 11, 20, some))
        val two = films.filter { it.id.startsWith("halloween") || it.id.startsWith("christmas") }
        assertEquals("Halloween", pick(2027, 6, 1, two))
        assertEquals("Christmas", pick(2027, 2, 2, two))
    }

    /** Romance is Valentine's and horror Halloween's, but not a kids' horror (the `RuleChip.genre` rule's own exception). */
    @Test fun testGenres() {
        assertTrue(Holiday.valentines.has(film("r", "R", genres = listOf("Romance"))))
        assertTrue(Holiday.halloween.has(film("h", "H", genres = listOf("Horror"))))
        assertFalse(Holiday.halloween.has(film("k", "K", genres = listOf("Horror", "Family"))))
        assertTrue(Holiday.halloween.has(film("k2", "K2", overview = "A Halloween night out.", genres = listOf("Horror", "Family"))))
        assertFalse(Holiday.christmas.has(MediaItem(id = "e", kind = MediaItem.Kind.episode, title = "A Christmas Special", runtime = 1500.0)))   // films only
        assertFalse(Holiday.easter.has(film("w", "W", overview = "Eastern Europe, 1946.")))   // Easter's words are phrases
        assertFalse(Holiday.halloween.has(film("j", "J", overview = "A jack-of-all-trades.")))
        assertTrue(Holiday.christmas.has(film("é", "É", overview = "Noël: «Christmas»")))   // after a two-byte non-letter
        assertFalse(Holiday.christmas.has(film("ü", "Ü", overview = "Noëlëchristmas")))   // after a two-byte letter
    }

    /** The channel goes last, so no other channel's number moves, and only when some holiday has enough films. */
    @Test fun testLineup() {
        val now = date(2026, 12, 1)
        val base = DemoMediaServer.items.filter { "Horror" !in it.genres }   // the demo's horror is Halloween's
        val plain = ChannelBuilder.automaticChannels(base, now = now)
        assertFalse(plain.any { it.id == "holiday" })
        val festive = ChannelBuilder.automaticChannels(base + films, now = now)
        val h = festive.last()
        assertEquals(listOf("holiday", "Holiday Special", "Films for the nearest holiday"), listOf(h.id, h.name, h.tag))
        assertEquals(listOf(RuleChip.holiday), h.rule)
        assertEquals(listOf("Nearest holiday"), h.rule.map { it.label })
        val before = plain.associate { it.id to it.number }
        for (d in festive) before[d.id]?.let { assertEquals(d.id, it, d.number) }
        assertTrue(h.number - festive[festive.size - 2].number in 1..3)
        val ch = ChannelBuilder.channels(listOf(h), base + films, now = now)[0]
        assertEquals(films.size, ch.items.size)   // every holiday's films, Groundhog Day too; the day picks
        assertFalse(ch.items.any { it.kind == MediaItem.Kind.episode })
    }
}
