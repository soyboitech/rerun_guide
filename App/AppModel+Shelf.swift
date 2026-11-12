import Foundation
import RerunGuideCore
#if os(tvOS)
import TVServices
#elseif os(iOS) && !targetEnvironment(macCatalyst)
import WidgetKit
#endif

/// The Top Shelf (Apple TV) and the On now widget (iPhone, iPad): the app leaves them a week of listings on its way to
/// the Home screen (`Shelf`), and their tune links come back through `open`.
extension AppModel {
    func writeShelf() {
        guard Shelf.url != nil else { return }   // no App Group here (the Mac build): nothing to write
        guard let cfg = persisted.serverConfig else { Self.clearShelf(); return }
        guard !channels.isEmpty else { return }   // still loading: the last file stands
        let visible = visibleChannels.isEmpty ? channels.filter { !isHidden($0.id) } : visibleChannels   // an empty Favorites guide is not an empty library
        let shown = Array(visible.filter { !$0.isScrambled }.prefix(Shelf.maxRows)), lineup = channels, theme = profile.theme.rawValue, link = cfg.link
        let task = BackgroundTask.begin("shelf")   // the app is suspended in seconds
        Task {
            let wrote = await Self.saveShelf(lineup, shown: shown, kind: cfg.kind, baseURL: cfg.baseURL, theme: theme)
            if persisted.serverConfig?.link != link { Self.clearShelf() } else if wrote { Self.shelfChanged() }   // signed out or linked elsewhere meanwhile
            task.end()
        }
    }

    /// Off the main actor: a week of the lineup is about 60 ms on a Mac.
    nonisolated static func saveShelf(_ lineup: [Channel], shown: [Channel], kind: ServerKind, baseURL: URL, theme: String) async -> Bool {
        Shelf.save(Shelf.make(lineup: lineup, shown: shown, kind: kind, baseURL: baseURL, theme: theme, now: .now))
    }

    /// Sign-out or a new link: the Home screen drops the old library's listings now, not when it next asks.
    static func clearShelf() { Shelf.clear(); shelfChanged() }

    private static func shelfChanged() {
        #if os(tvOS)
        TVTopShelfContentProvider.topShelfContentDidChange()
        #elseif os(iOS) && !targetEnvironment(macCatalyst)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// `rerunguide://tune?channel=<id>`: only a channel id comes in, never a server, token, profile or edit.
    func open(_ url: URL) {
        guard let id = Shelf.channelID(from: url) else { return }
        pendingTuneID = id
        later("pending-tune", seconds: 30) { [weak self] in self?.pendingTuneID = nil }   // a tap is for now, not for a lineup landing minutes later
        applyPendingTune()
    }

    func applyPendingTune() {
        guard let id = pendingTuneID else { return }
        guard persisted.serverConfig != nil, screen != .building else { pendingTuneID = nil; cancelTimer("pending-tune"); return }   // signed out, or a build on screen
        guard !channels.isEmpty else { return }   // the cache is still decoding: the rebuild's call lands it
        pendingTuneID = nil; cancelTimer("pending-tune")
        if screen == .watch, playback?.channelID == id { return }   // already on: no reload
        if attracting { attractReset() }
        if screen != .guide && screen != .watch { go(.guide) }   // Settings, the editor, Search, Profiles: leave first
        if channel(id) != nil { tune(id, mode: .live) } else { toast("That channel is off the air.") }
    }
}
