package com.rerunguide.core

/**
 * The same film or episode in two of the user's libraries ("Movies" and "4K Movies", a kids' library) comes back from
 * the server as two items, and would count and air twice. The library keeps one of each: the first in library order
 * (the one that plays), watched if any copy is, added when the first copy was (a copy with no date counts as old, so a
 * new copy doesn't make the film new). A show whose episodes turn up in two libraries becomes one show. Cuts stay apart
 * (their title carries the cut), and so do films with no year.
 */
object Duplicates {
    /** What copies share: a film's title, as search reads it, and its year; an episode's show, season, number, title and
     *  year (two shows of one name, a UK original and its US remake, aired years apart even where a pilot's title is
     *  the same). null: never merged (no year, no number, a title with no letters or digits). */
    fun key(item: MediaItem): String? {
        val t = TitleSearch.keys(item.title).full
        if (t.isEmpty()) return null
        return when (item.kind) {
            MediaItem.Kind.movie -> item.year?.let { "movie|$t|$it" }
            MediaItem.Kind.episode -> {
                val show = item.seriesTitle; val s = item.season; val e = item.episode
                if (show == null || s == null || e == null) null
                else "episode|${TitleSearch.keys(show).full}|$s|$e|$t|${item.year ?: 0}"
            }
        }
    }

    /** Libraries whose copies play only when no other library has the film: 4K ones ("4K Movies", "Movies (UHD)"), which a
     *  friend's shared server often won't stream and a remote connection struggles to carry. */
    fun lastResort(sections: List<LibrarySection>): Set<String> =
        sections.filter { s -> s.title.lowercase().let { t -> listOf("4k", "uhd", "2160").any { it in t } } }.map { it.id }.toSet()

    /** `items` with each film and episode once, in their order, but copies from `lastResort` libraries behind the rest. */
    fun merge(items: List<MediaItem>, lastResort: Set<String> = emptySet()): List<MediaItem> {
        val ordered = if (lastResort.isEmpty()) items
            else items.partition { (it.libraryID ?: "") !in lastResort }.let { (rest, last) -> rest + last }
        val out = ArrayList<MediaItem>(ordered.size); val at = HashMap<String, Int>(); val ids = HashSet<String>()
        val show = HashMap<String, String>(); val seen = HashMap<String, Int>()
        fun root(id: String): String = generateSequence(id) { show[it] }.last()
        for (item in ordered) {
            if (!ids.add(item.id)) continue   // one item listed twice (two chosen libraries sharing it)
            item.seriesID?.let { seen.getOrPut(it) { seen.size } }   // the order shows turn up in
            val k = key(item)
            if (k == null) { out += item; continue }
            val i = at[k]
            if (i == null) { at[k] = out.size; out += item; continue }
            val first = out[i]; val a = first.addedAt; val b = item.addedAt
            out[i] = first.copy(watched = first.watched || item.watched, addedAt = if (a != null && b != null) minOf(a, b) else null)
            // The copy's show and the kept one's are one show: under whichever turned up first, so libraries that come
            // interleaved can't leave it in two.
            val ra = item.seriesID?.let(::root); val rb = first.seriesID?.let(::root)
            if (ra != null && rb != null && ra != rb) {
                if ((seen[ra] ?: 0) < (seen[rb] ?: 0)) show[rb] = ra else show[ra] = rb
            }
        }
        if (show.isEmpty()) return out
        return out.map { m ->
            val s = m.seriesID ?: return@map m
            val r = root(s)
            if (r == s) m else m.copy(seriesID = r)
        }
    }
}
