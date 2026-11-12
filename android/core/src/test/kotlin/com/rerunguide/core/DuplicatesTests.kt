package com.rerunguide.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** The same film or episode in two libraries is one item: once on every channel, counted once, one show. */
class DuplicatesTests {
    private fun film(id: String, title: String, year: Int?, lib: String = "movies", watched: Boolean = false, added: Double? = null) =
        MediaItem(id = id, kind = MediaItem.Kind.movie, title = title, year = year, genres = listOf("Drama"), runtime = 6000.0,
            directors = listOf("Dee Rector"), libraryID = lib, addedAt = added?.let(::instantOf), watched = watched)
    private fun ep(id: String, show: String, sid: String, s: Int, e: Int, title: String, lib: String = "tv", year: Int = 1990) =
        MediaItem(id = id, kind = MediaItem.Kind.episode, title = title, seriesTitle = show, seriesID = sid, season = s, episode = e,
            year = year, genres = listOf("Comedy"), runtime = 1320.0, libraryID = lib)

    /** The first copy stays (it plays); watched if either copy is, added when the first copy was. */
    @Test fun testFilmCopies() {
        val merged = Duplicates.merge(listOf(film("m1", "The Thing", 1982, added = 1_000.0),
            film("u1", "The thing!", 1982, lib = "4k", watched = true, added = 2_000.0)))
        assertEquals(listOf("m1"), merged.map { it.id })
        assertEquals("movies", merged[0].libraryID)
        assertTrue(merged[0].watched)
        assertEquals(instantOf(1_000.0), merged[0].addedAt)
        // The 4K copy came first: it stays, and still dates from the older copy.
        val other = Duplicates.merge(listOf(film("u1", "The Thing", 1982, lib = "4k", added = 2_000.0), film("m1", "The Thing", 1982, added = 1_000.0)))
        assertEquals(listOf("u1"), other.map { it.id })
        assertEquals(instantOf(1_000.0), other[0].addedAt)
        // A copy with no date counts as old: a new copy of an undated film doesn't make it new.
        assertNull(Duplicates.merge(listOf(film("m1", "The Thing", 1982), film("u1", "The Thing", 1982, lib = "4k", added = 2_000.0)))[0].addedAt)
    }

    /** A copy in a 4K library plays only when no other library has the film; a film only there still airs. */
    @Test fun testFourKLibraryIsLastResort() {
        val sections = listOf(LibrarySection("4k", "4K Movies", LibrarySection.Kind.movies), LibrarySection("movies", "Movies", LibrarySection.Kind.movies),
            LibrarySection("uhd", "Films (UHD)", LibrarySection.Kind.movies))
        assertEquals(setOf("4k", "uhd"), Duplicates.lastResort(sections))
        val items = listOf(film("u1", "The Thing", 1982, lib = "4k", watched = true), film("u2", "Alien", 1979, lib = "4k"), film("m1", "The Thing", 1982))
        val merged = Duplicates.merge(items, lastResort = Duplicates.lastResort(sections))
        assertEquals(listOf("m1", "u2"), merged.map { it.id })
        assertTrue(merged[0].watched)
    }

    /** Two cuts are two films; a remake (another year) is another film; with no year there's no telling, so both stay. */
    @Test fun testWhatStaysApart() {
        val items = listOf(film("a", "Blade Runner", 1982), film("b", "Blade Runner (The Final Cut)", 1982),
            film("c", "The Thing", 1982), film("d", "The Thing", 2011), film("e", "Home Video", null), film("f", "Home Video", null))
        assertEquals(listOf("a", "b", "c", "d", "e", "f"), Duplicates.merge(items).map { it.id })
    }

    /** One item listed twice (two chosen libraries sharing it on Emby or Jellyfin) is once. */
    @Test fun testSameItemTwice() {
        val e = ep("e1", "Cheers", "s1", 1, 1, "Give Me a Ring Sometime")
        assertEquals(listOf("e1", "m"), Duplicates.merge(listOf(e, film("m", "Diner", 1982), e)).map { it.id })
    }

    /** A show in two libraries is one show: its copies go, and what only the second library has joins the first's show. */
    @Test fun testShowInTwoLibraries() {
        val items = listOf(ep("a1", "Cheers", "s1", 1, 1, "Give Me a Ring Sometime"), ep("a2", "Cheers", "s1", 1, 2, "Sams Women"),
            ep("b1", "Cheers", "s9", 1, 1, "Give Me a Ring Sometime", lib = "tv2"), ep("b2", "Cheers", "s9", 1, 2, "Sam's Women", lib = "tv2"),
            ep("b3", "Cheers", "s9", 1, 3, "The Tortelli Tort", lib = "tv2"))
        val merged = Duplicates.merge(items)
        assertEquals(listOf("a1", "a2", "b3"), merged.map { it.id })
        assertEquals(setOf("s1"), merged.mapNotNull { it.seriesID }.toSet())
        val marathons = ChannelBuilder.automaticChannels(merged, minItems = 3).filter { it.tag == "Marathon" }
        assertEquals(listOf("Cheers"), marathons.map { it.name })
    }

    /** Two shows of one name (the UK and US Office) aren't copies of each other: other episode titles, or the same pilot
     *  title years apart. */
    @Test fun testShowsOfOneName() {
        val items = listOf(ep("uk1", "The Office", "uk", 1, 1, "Downsize"), ep("us1", "The Office", "us", 1, 1, "Pilot"),
            ep("sk1", "Skins", "skuk", 1, 1, "Tony", year = 2007), ep("sk2", "Skins", "skus", 1, 1, "Tony", year = 2011))
        val merged = Duplicates.merge(items)
        assertEquals(listOf("uk1", "us1", "sk1", "sk2"), merged.map { it.id })
        assertEquals(listOf("uk", "us", "skuk", "skus"), merged.mapNotNull { it.seriesID })
    }

    /** A custom marathon made from the second library's copy of a show still airs once that show is merged into the first. */
    @Test fun testCustomMarathonFollowsMergedShow() {
        val items = listOf(ep("a1", "Cheers", "s1", 1, 1, "Give Me a Ring Sometime"), ep("b1", "Cheers", "s9", 1, 1, "Give Me a Ring Sometime", lib = "tv2"),
            ep("b2", "Cheers", "s9", 1, 2, "Sams Women", lib = "tv2"))
        val custom = ChannelDefinition(id = "custom:c", number = 50, name = "Cheers", tag = "Marathon", rule = listOf(RuleChip.series(id = "s9", title = "Cheers")),
            order = PlayOrder.inOrder, isCustom = true)
        assertEquals(listOf("a1", "b2"), ChannelBuilder.resolve(custom, Duplicates.merge(items)).map { it.id })
    }

    /** Libraries that come interleaved (one recursive query) still make one show, under the id that turned up first. */
    @Test fun testInterleavedShow() {
        val items = listOf(ep("b1", "Cheers", "s9", 1, 1, "Give Me a Ring Sometime", lib = "tv2"), ep("a1", "Cheers", "s1", 1, 1, "Give Me a Ring Sometime"),
            ep("a2", "Cheers", "s1", 1, 2, "Sams Women"), ep("b2", "Cheers", "s9", 1, 2, "Sam's Women", lib = "tv2"),
            ep("b3", "Cheers", "s9", 1, 3, "The Tortelli Tort", lib = "tv2"))
        val merged = Duplicates.merge(items)
        assertEquals(listOf("b1", "a2", "b3"), merged.map { it.id })
        assertEquals(setOf("s9"), merged.mapNotNull { it.seriesID }.toSet())
    }

    /** A title with no letters or digits says nothing about the film: never merged. */
    @Test fun testEmptyTitle() {
        assertEquals(listOf("x", "y"), Duplicates.merge(listOf(film("x", "?", 1990), film("y", "!", 1990))).map { it.id })
    }

    /** A library with a 4K copy of every film builds the same lineup as one without, once merged. */
    @Test fun testLineupCountsFilmsOnce() {
        val now = Instant.now()
        val films = (0 until 6).map { film("f$it", "Film $it", 1980 + it) }
        val copies = (0 until 6).map { film("k$it", "Film $it", 1980 + it, lib = "4k", added = now.epochSeconds) }
        assertNotEquals(ChannelBuilder.automaticChannels(films + copies, now = now), ChannelBuilder.automaticChannels(films, now = now))
        assertEquals(ChannelBuilder.automaticChannels(Duplicates.merge(films + copies), now = now),
            ChannelBuilder.automaticChannels(films, now = now))
    }
}
