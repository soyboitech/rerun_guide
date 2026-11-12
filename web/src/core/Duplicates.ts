// Port of android/core Duplicates.kt.
import { LibrarySection, MediaItem } from './Models'
import { TitleSearch } from './TitleSearch'

/**
 * The same film or episode in two of the user's libraries ("Movies" and "4K Movies", a kids' library) comes back from
 * the server as two items, and would count and air twice. The library keeps one of each: the first in library order
 * (the one that plays), watched if any copy is, added when the first copy was (a copy with no date counts as old, so a
 * new copy doesn't make the film new). A show whose episodes turn up in two libraries becomes one show. Cuts stay apart
 * (their title carries the cut), and so do films with no year.
 */
export const Duplicates = {
  /** What copies share: a film's title, as search reads it, and its year; an episode's show, season, number, title and
   *  year (two shows of one name, a UK original and its US remake, aired years apart even where a pilot's title is
   *  the same). null: never merged (no year, no number, a title with no letters or digits). */
  key(item: MediaItem): string | null {
    const t = TitleSearch.keys(item.title).full
    if (t === '') return null
    if (item.kind === 'movie') return item.year == null ? null : `movie|${t}|${item.year}`
    const show = item.seriesTitle, s = item.season, e = item.episode
    if (show == null || s == null || e == null) return null
    return `episode|${TitleSearch.keys(show).full}|${s}|${e}|${t}|${item.year ?? 0}`
  },

  /** Libraries whose copies play only when no other library has the film: 4K ones ("4K Movies", "Movies (UHD)"), which a
   *  friend's shared server often won't stream and a remote connection struggles to carry. */
  lastResort(sections: readonly LibrarySection[]): Set<string> {
    return new Set(sections.filter(s => {
      const t = s.title.toLowerCase()
      return ['4k', 'uhd', '2160'].some(w => t.indexOf(w) >= 0)
    }).map(s => s.id))
  },

  /** `items` with each film and episode once, in their order, but copies from `lastResort` libraries behind the rest. */
  merge(items: readonly MediaItem[], lastResort: ReadonlySet<string> = new Set()): MediaItem[] {
    const last = (it: MediaItem) => lastResort.has(it.libraryID ?? '')
    const ordered = lastResort.size === 0 ? items : items.filter(it => !last(it)).concat(items.filter(last))
    const out: MediaItem[] = [], at = new Map<string, number>(), ids = new Set<string>(), show = new Map<string, string>()
    const seen = new Map<string, number>()
    const root = (id: string): string => { let up: string | undefined; while ((up = show.get(id)) != null) id = up; return id }
    for (const item of ordered) {
      if (ids.has(item.id)) continue   // one item listed twice (two chosen libraries sharing it)
      ids.add(item.id)
      if (item.seriesID != null && !seen.has(item.seriesID)) seen.set(item.seriesID, seen.size)   // the order shows turn up in
      const k = Duplicates.key(item)
      if (k == null) { out.push(item); continue }
      const i = at.get(k)
      if (i == null) { at.set(k, out.length); out.push(item); continue }
      const first = out[i]
      out[i] = first.copy({
        watched: first.watched || item.watched,
        addedAt: first.addedAt == null || item.addedAt == null ? null : Math.min(first.addedAt, item.addedAt),
      })
      // The copy's show and the kept one's are one show: under whichever turned up first, so libraries that come
      // interleaved can't leave it in two.
      if (item.seriesID != null && first.seriesID != null) {
        const a = root(item.seriesID), b = root(first.seriesID)
        if (a !== b) {
          if ((seen.get(a) ?? 0) < (seen.get(b) ?? 0)) show.set(b, a); else show.set(a, b)
        }
      }
    }
    if (show.size === 0) return out
    return out.map(m => {
      if (m.seriesID == null) return m
      const r = root(m.seriesID)
      return r === m.seriesID ? m : m.copy({ seriesID: r })
    })
  },
}
