import Foundation

/// The same film or episode in two of the user's libraries ("Movies" and "4K Movies", a kids' library) comes back from
/// the server as two items, and would count and air twice. The library keeps one of each: the first in library order
/// (the one that plays), watched if any copy is, added when the first copy was (a copy with no date counts as old, so a
/// new copy doesn't make the film new). A show whose episodes turn up in two libraries becomes one show. Cuts stay apart
/// (their title carries the cut), and so do films with no year.
public enum Duplicates {
    /// What copies share: a film's title, as search reads it, and its year; an episode's show, season, number, title and
    /// year (two shows of one name, a UK original and its US remake, aired years apart even where a pilot's title is
    /// the same). nil: never merged (no year, no number, a title with no letters or digits).
    public static func key(_ item: MediaItem) -> String? {
        let t = TitleSearch.keys(item.title).full
        guard !t.isEmpty else { return nil }
        switch item.kind {
        case .movie:
            guard let y = item.year else { return nil }
            return "movie|\(t)|\(y)"
        case .episode:
            guard let show = item.seriesTitle, let s = item.season, let e = item.episode else { return nil }
            return "episode|\(TitleSearch.keys(show).full)|\(s)|\(e)|\(t)|\(item.year ?? 0)"
        }
    }

    /// Libraries whose copies play only when no other library has the film: 4K ones ("4K Movies", "Movies (UHD)"), which a
    /// friend's shared server often won't stream and a remote connection struggles to carry.
    public static func lastResort(_ sections: [LibrarySection]) -> Set<String> {
        Set(sections.filter { s in let t = s.title.lowercased(); return ["4k", "uhd", "2160"].contains { t.contains($0) } }.map(\.id))
    }

    /// `items` with each film and episode once, in their order, but copies from `lastResort` libraries behind the rest.
    public static func merge(_ items: [MediaItem], lastResort: Set<String> = []) -> [MediaItem] {
        let items = lastResort.isEmpty ? items
            : items.filter { !lastResort.contains($0.libraryID ?? "") } + items.filter { lastResort.contains($0.libraryID ?? "") }
        var out: [MediaItem] = [], at: [String: Int] = [:], ids: Set<String> = [], show: [String: String] = [:], seen: [String: Int] = [:]
        func root(_ id: String) -> String { var id = id; while let up = show[id] { id = up }; return id }
        for item in items where ids.insert(item.id).inserted {   // one item listed twice (two chosen libraries sharing it)
            if let s = item.seriesID, seen[s] == nil { seen[s] = seen.count }   // the order shows turn up in
            guard let k = key(item) else { out.append(item); continue }
            guard let i = at[k] else { at[k] = out.count; out.append(item); continue }
            let first = out[i]
            out[i] = first.with(watched: first.watched || item.watched, addedAt: first.addedAt.flatMap { a in item.addedAt.map { min(a, $0) } },
                                seriesID: first.seriesID)
            // The copy's show and the kept one's are one show: under whichever turned up first, so libraries that come
            // interleaved can't leave it in two.
            if let a = item.seriesID.map(root), let b = first.seriesID.map(root), a != b {
                if seen[a, default: 0] < seen[b, default: 0] { show[b] = a } else { show[a] = b }
            }
        }
        guard !show.isEmpty else { return out }
        return out.map { m in
            guard let s = m.seriesID, case let r = root(s), r != s else { return m }
            return m.with(watched: m.watched, addedAt: m.addedAt, seriesID: r)
        }
    }
}

private extension MediaItem {
    func with(watched: Bool, addedAt: Date?, seriesID: String?) -> MediaItem {
        MediaItem(id: id, kind: kind, title: title, seriesTitle: seriesTitle, seriesID: seriesID, season: season, episode: episode,
                  year: year, genres: genres, runtime: runtime, artworkPath: artworkPath, backdropPath: backdropPath, overview: overview,
                  contentRating: contentRating, directors: directors, actors: actors, libraryID: libraryID, addedAt: addedAt,
                  watched: watched)
    }
}
