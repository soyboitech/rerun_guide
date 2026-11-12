package com.rerunguide.app

import com.rerunguide.core.MediaItem
import com.rerunguide.core.instantOf
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.File

/** The library cache is a line of JSON for each item. What was saved comes back, a line break in a title stays inside
 *  its line, and a file that is another server's, cut short or missing reads as no cache (the refresh replaces it). */
class LibraryCacheTest {
    @Test fun roundTripAndUnreadableFiles() {
        val file = File.createTempFile("library", ".jsonl").apply { deleteOnExit() }
        val items = listOf(
            MediaItem(id = "1", kind = MediaItem.Kind.movie, title = "Two\nlines, \"quoted\" \\ é  ", year = 1984,
                genres = listOf("Comedy", "Sci-Fi"), runtime = 6300.5, artworkPath = "/library/metadata/1/thumb/1",
                overview = "One.\r\nTwo.", contentRating = "PG", directors = listOf("A"), actors = listOf("B", "C"),
                libraryID = "2", addedAt = instantOf(1_700_000_000.0), watched = true),
            MediaItem(id = "2", kind = MediaItem.Kind.episode, title = "Pilot", seriesTitle = "Show", seriesID = "s1",
                season = 1, episode = 1, runtime = 1320.0),
        )
        LibraryCache.write(file, items, "m|u")
        assertEquals(items, LibraryCache.read(file, "m|u"))
        val lines = file.readLines()
        assertEquals(3, lines.size)   // the link, then an item on each line
        assertNull(LibraryCache.read(file, "other|u"))   // another server's or account's

        file.writeText(lines.take(2).joinToString("\n"))   // cut between two lines
        assertNull(LibraryCache.read(file, "m|u"))
        file.writeText(lines.joinToString("\n").dropLast(5))   // cut inside the last one
        assertNull(LibraryCache.read(file, "m|u"))
        file.delete()
        assertNull(LibraryCache.read(file, "m|u"))

        LibraryCache.write(file, emptyList(), "m|u")   // a server with nothing on it is a cache too
        assertEquals(emptyList<MediaItem>(), LibraryCache.read(file, "m|u"))
    }
}
