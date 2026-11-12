@preconcurrency import TVServices   // its content types predate Sendable
import RerunGuideCore

/// The Apple TV Home screen's "On now" row: one poster per channel of the guide, what the app's listings (`Shelf`) say
/// is on; "Up next" too when fewer than five have one. Select or Play opens the app on that channel.
final class ContentProvider: TVTopShelfContentProvider {
    // The completion-handler form: an async override runs @concurrent and can't safely hand back the content, which
    // isn't Sendable. Nothing here waits anyway.
    override func loadTopShelfContent(completionHandler: @escaping ((any TVTopShelfContent)?) -> Void) {
        completionHandler(content())
    }

    private func content() -> (any TVTopShelfContent)? {
        let now = Date.now
        guard let shelf = Shelf.load(), now < shelf.until, shelf.zone == TimeZone.current.identifier, shelf.kind != .demo,
              let token = Keychain.get("token") else { return nil }   // nothing to say: the static image
        let server = shelf.kind.makeServer(baseURL: shelf.baseURL, token: token, userID: nil, deviceID: "", name: "")
        func item(_ row: Shelf.Row, _ p: Shelf.Program, live: Bool) -> TVTopShelfSectionedItem? {
            guard let art = server.artworkURL(path: p.art) else { return nil }   // no poster: no card
            let it = TVTopShelfSectionedItem(identifier: "\(row.id)|\(Int(p.start.timeIntervalSince1970))")
            it.title = "\(p.title) · \(row.number) \(row.name)"
            it.imageShape = .poster
            it.setImageURL(art, for: .screenScale1x)
            it.setImageURL(art, for: .screenScale2x)
            if live { it.playbackProgress = min(1, now.timeIntervalSince(p.start) / max(1, p.itemEnd.timeIntervalSince(p.start))) }
            let open = TVTopShelfAction(url: Shelf.tuneURL(row.id))
            it.playAction = open; it.displayAction = open
            return it
        }
        let onNow = shelf.rows.compactMap { r in r.program(at: now).flatMap { item(r, $0, live: true) } }
        guard !onNow.isEmpty else { return nil }
        var sections = [TVTopShelfItemCollection(items: onNow)]
        sections[0].title = "On now"
        if onNow.count < 5 {
            let next = TVTopShelfItemCollection(items: shelf.rows.compactMap { r in r.next(after: now).flatMap { item(r, $0, live: false) } })
            next.title = "Up next"
            if !next.items.isEmpty { sections.append(next) }
        }
        return TVTopShelfSectionedContent(sections: sections)
    }
}
