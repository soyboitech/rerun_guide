import Foundation
import Observation
import UIKit
import RerunGuideCore

/// What the picture is showing right now (port of the prototype's wInfo).
struct WatchInfo {
    let channel: Channel
    let slot: Slot
    /// Seconds into the slot. `runtime ≤ position < duration` is the break after the program.
    let position: TimeInterval
    let live: Bool
    /// What the channel's current schedule airs at `slot.end` (what live rolls into).
    let next: Slot?
    var isBreak: Bool { position >= slot.item.runtime }

    /// The progress bar: the time into the program ("1:02:15"), the clock time it ends (later while paused), and its fill
    /// over the program's runtime. A break keeps the slot's clock times, filled over the whole slot.
    @MainActor func bar(at now: Date) -> (elapsed: String, ends: String, progress: Double) {
        let runtime = slot.item.runtime
        guard !isBreak, runtime > 0 else { return (Clock.time(slot.start), Clock.time(slot.end), max(0, min(1, position / slot.duration))) }
        let s = Int(position), end = now.addingTimeInterval(runtime - position)
        return (s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60),
                "Ends \(Clock.time(end)) \(Clock.ap(end))", max(0, position / runtime))
    }
}

/// Watching: banner, channel up/down, last channel, pause/time-shift (port of k_watch/wInfo/flip/togglePause/watchActs).
extension AppModel {
    func watchInfo(at now: Date = .now) -> WatchInfo? {
        guard let pb = playback, let ch = channel(pb.channelID) ?? visibleChannels.first else { return nil }
        // The slot tune() snapshotted, unless its channel is gone: a library refresh reshuffles every lineup and the
        // program must not change under the viewer. Live rolls into the current schedule once the snapshot ends.
        let kept = ch.id == pb.channelID ? pb.slot : nil
        if pb.mode == .start, let s = kept ?? slot(ch, startingAt: pb.programStart) ?? slotOnAir(ch, at: now) {
            let position = pb.offset + (pb.paused ? 0 : now.timeIntervalSince(pb.startedAt))
            // Caught up: a started-over program that has ended is live again as soon as the clock is past its end too
            // (`watchTick` makes it the playback, and says so, once a program is on). So its break is the channel's
            // own: it ends with the slot and the next program starts on time, however long a pause or a call held this
            // one. Further behind than the break is long, there is none left: it joins what is on. One started before
            // it aired is ahead of the clock: its break runs as long as the slot's first, unless the clock gets to the
            // program's end sooner. A pause holds everything, a break too.
            if pb.paused || position < min(s.item.runtime, s.duration) || (now < s.itemEnd && position < s.duration) {
                return WatchInfo(channel: ch, slot: s, position: position, live: false, next: slotOnAir(ch, at: s.end))
            }
        }
        // On air: a kept slot that has not begun (one watched before it aired, live again since) waits its turn.
        guard let s = kept.flatMap({ $0.start <= now && now < $0.end ? $0 : nil }) ?? slotOnAir(ch, at: now) else { return nil }
        return WatchInfo(channel: ch, slot: s, position: now.timeIntervalSince(s.start), live: true, next: slotOnAir(ch, at: s.end))
    }

    func pressWatch(_ cmd: RemoteCommand) {
        guard let pb = playback else { return }
        if pb.paused {   // any press puts the program's art away for another 15 s; Back with it up does only that
            let artUp = pauseArtShown()
            armPauseArt()
            if artUp && cmd == .back { return }
        }
        if trackMenu != nil, cmd != .play { pressTrackMenu(cmd); return }
        switch cmd {
        // From the banner's buttons Up goes to its progress bar, and Down comes back; otherwise they change channels.
        case .up: if bannerVisible && bannerFocus >= 0 { barFocused = true; bannerLater() } else { flip(1) }
        case .down: if bannerVisible && bannerFocus >= 0 && barFocused { barFocused = false; bannerLater() } else { flip(-1) }
        case .back:   // Back hides the banner first (its info alone too); held upright none is drawn, and Back leaves at once. Full screen goes back to portrait Now playing
            if bannerVisible && !portrait { hideBanner() } else if fullScreen { fullScreen = false } else { toGuide(from: pb.channelID) }
        // In a break Play/Pause is "watch it again": pausing a break holds nothing. A break that is paused all the same (the
        // sleep timer, headphones pulled) goes back to live (`togglePause`).
        case .play: if !pb.paused, watchInfo()?.isBreak == true { restartFromBreak() } else { togglePause() }
        case .left, .right, .select:
            if bannerVisible && bannerFocus >= 0 && barFocused {   // the progress bar: Left / Right skip, OK is Play/Pause
                if cmd != .select { skip(cmd == .left ? -10 : 10) } else if watchInfo()?.isBreak != true { togglePause() }
                bannerLater(); return
            }
            if bannerVisible && bannerFocus >= 0 {
                let acts = watchActions()
                guard !acts.isEmpty else { hideBanner(); return }   // no watchInfo (channels gone mid-program)
                switch cmd {
                case .left: bannerFocus = max(0, bannerFocus - 1)
                case .right: bannerFocus = min(acts.count - 1, bannerFocus + 1)
                default: acts[min(bannerFocus, acts.count - 1)].run()
                }
                bannerLater(); return
            }
            // The spot: Select / Right skip it once its countdown is done, and do nothing before that.
            if cmd != .left, SpotOnAir.shared.started != nil { skipSpot(); return }
            if cmd == .select, let info = watchInfo(), info.isBreak, info.next != nil { startNextFromBreak(); return }   // the break card's OK
            if cmd == .left { skip(-10); return }
            if cmd == .right { skip(10); return }
            bannerVisible = true; bannerFocus = 0; barFocused = false
            bannerLater()
        }
    }

    /// In a break, for its card: the viewer saw this program end, so it "just ended" whatever the clock says; otherwise
    /// the card gives the clock time it ended at. A break after a program watched behind the clock reads live
    /// (`watchInfo`), but its playback is still the started-over one, on this slot, until the next program
    /// (`watchTick`): that tells it from a break joined on the air, and from another program's break it ran into.
    func justEnded(_ info: WatchInfo) -> Bool { !info.live || (playback?.mode == .start && playback?.slot == info.slot) }

    /// In a break: the program that just ended, from its beginning (Play/Pause, or the break card's pill).
    func restartFromBreak() {
        guard let info = watchInfo() else { return }
        tune(info.channel.id, mode: .start, programStart: info.slot.start)
    }

    /// In a break: the next program, from its beginning, without waiting for its slot (Select, or the break card's pill).
    func startNextFromBreak() {
        guard let info = watchInfo(), let next = info.next else { return }
        tune(info.channel.id, mode: .start, programStart: next.start)
    }

    /// Hide the banner 6 s from now.
    func bannerLater() { later("banner", seconds: 6) { [weak self] in guard let self, overlay == nil, trackMenu == nil else { return }; bannerVisible = false; bannerFocus = -1 } }
    func hideBanner() { cancelTimer("banner"); bannerVisible = false; bannerFocus = -1; trackMenu = nil }

    /// Channel up (+1) / down (−1) through the visible channels, wrapping. From a channel outside them (typed, searched
    /// or Last channel under the Favorites guide), the next one above or below it on the dial.
    func flip(_ d: Int) {
        let list = visibleChannels
        guard !list.isEmpty, let pb = playback else { return }
        if let i = list.firstIndex(where: { $0.id == pb.channelID }) {
            if list.count > 1 { tune(list[((i + d) % list.count + list.count) % list.count].id, mode: .live) }   // the only one: nothing to reload
        } else {
            let n = channel(pb.channelID)?.number ?? 0
            tune((d > 0 ? list.first { $0.number > n } ?? list[0] : list.last { $0.number < n } ?? list[list.count - 1]).id, mode: .live)
        }
    }

    // MARK: Number keys

    /// The channel numbered `n` in this profile's lineup: a hidden one counts as missing.
    func channel(numbered n: Int) -> Channel? { channels.first { $0.number == n && !isHidden($0.id) } }
    /// The channel the digits typed so far name.
    var entryChannel: Channel? { channelEntry.flatMap { Int($0.digits) }.flatMap(channel(numbered:)) }

    /// A number key on the guide or the player with nothing over them: the box in the top-right corner collects up to
    /// three digits and tunes 2 s after the last one, at the third, or on OK. Digits do nothing anywhere else.
    func pressDigit(_ d: Int) {
        guard overlay == nil, editingField == nil, trackMenu == nil, screen == .guide || screen == .watch else { return }
        if attracting { attractReset() }   // the box wakes the screen instead of sitting on the screensaver
        let digits = (channelEntry.flatMap { $0.missing ? nil : $0.digits } ?? "") + String(d)
        channelEntry = ChannelEntry(digits: digits); lastEntry = channelEntry
        if digits.count == 3 { commitEntry() } else { later("entry", seconds: 2) { [weak self] in self?.commitEntry() } }
    }

    /// While the box collects digits, OK tunes now and Back cancels; any other press closes it and does what it does.
    /// True when the box took the press.
    func pressEntry(_ cmd: RemoteCommand) -> Bool {
        guard channelEntry?.missing == false else { return false }
        if cmd == .select { commitEntry(); return true }
        closeEntry()
        return cmd == .back
    }

    /// Put the box away without tuning: a tap, a channel change or a screen went elsewhere.
    func closeEntry() { cancelTimer("entry"); channelEntry = nil }

    /// Tune to the typed number like a channel change (the tune-mode setting applies). The channel already on screen
    /// just closes the box; a number with no channel says so for 2 s and changes nothing.
    func commitEntry() {
        guard let e = channelEntry, !e.missing, let n = Int(e.digits) else { return }
        closeEntry()
        guard overlay == nil, editingField == nil, !pip, screen == .guide || screen == .watch else { return }   // moved on, or away in picture in picture
        guard let ch = channel(numbered: n) else {
            channelEntry = ChannelEntry(digits: e.digits, missing: true); lastEntry = channelEntry
            later("entry", seconds: 2) { [weak self] in self?.channelEntry = nil }
            return
        }
        if screen == .watch, playback?.channelID == ch.id { return }
        let fromGuide = screen == .guide
        tune(ch.id, mode: .live)
        if fromGuide { bannerVisible = watchInfo()?.isBreak != true }   // a number names a channel, not what's on it
    }

    // MARK: Background

    /// Leaving for the Home screen (Back from Options over the guide, or the TV button): ask the server to stop both
    /// streams now, instead of leaving it transcoding until it notices nobody is pulling, and hold a started-over
    /// program's place. A live program needs nothing held: it rejoins live on the way back, like changing back to a
    /// channel.
    func enteredBackground() {
        guard !backgrounded, !pip else { return }   // picture in picture plays on: `pipChanged` comes back here when it closes
        backgrounded = true
        writeShelf()   // the Top Shelf and the widget, from what the guide shows now
        if var pb = playback, pb.mode == .start, !pb.paused, let info = watchInfo(), !info.live {   // live: caught up, whatever the mode still says
            pb.offset = info.position; pb.paused = true; playback = pb; resumeAfterBackground = true
            pauseArtAt = nil   // held, not paused by the viewer: no art behind the Home screen
        } else if playback?.mode == .live, playback?.markDue == false { playback?.fromStart = false }   // a caught-up start-over rejoins live on the way back: no longer from the beginning
        cancelTimer("seek"); closeEntry()   // a typed number doesn't tune behind the Home screen
        guard let server else { return }
        let task = BackgroundTask.begin("stop-streams")   // the app is suspended in seconds; finish the two requests first
        Task { await server.stopPlayback(session: "watch"); await server.stopPlayback(session: "preview"); task.end() }
        // A plain-http Plex link may come back on another network, where the guide's artwork and preview would carry the
        // token before the return's pick finishes. Dropped now, that pick rebuilds it once its address checks out.
        if plainHTTPLink { self.server = nil }
    }

    /// A plain-http Plex link off TV (a LAN address, where the router hides plex.direct): dropped while the app is away
    /// and checked again on the way back before the token goes to it.
    var plainHTTPLink: Bool {
        !Platform.isTV && persisted.serverConfig?.addresses != nil && persisted.serverConfig?.baseURL.scheme == "http"
    }

    /// The player went into picture in picture (iPhone, iPad: Home while it plays) or out of it. The app is away meanwhile
    /// (and may sleep through a network change while the window is paused): a plain-http link's client goes, as in
    /// `enteredBackground` (the window plays on: past start.m3u8 its requests carry no token), and address picks wait.
    /// Closed while the app is still away, its stream stops as on any other way out (a plain-http link's server can't be
    /// asked to: it ends the stream once nothing pulls it). Brought back paused (the window's own
    /// pause, behind the clock), or after a call stopped it in the window, or on a plain-http link, it comes back as from
    /// Home: on the clock, the banner up, the link checked before anything reloads. Brought back playing otherwise, it
    /// just carries on.
    func pipChanged(_ on: Bool, paused: Bool = false) {
        let was = pip
        pip = on
        if on {
            // The window only starts on a picture that plays: a hold whose end the screen had not seen yet (it looks once
            // a second) ends here. Left held, it would last as long as the window, and end by starting the program again
            // where the call came in.
            if var pb = playback, pb.held { pb.held = false; pb.paused = false; pb.startedAt = .now; playback = pb; followEndOfProgram() }
            if plainHTTPLink { server = nil }
            return
        }
        guard was else { return }
        if UIApplication.shared.applicationState == .background { enteredBackground() }
        else if paused || plainHTTPLink { backgrounded = true; returnedToForeground() }   // its stream isn't stopped: the reload replaces it
    }

    /// Back from the Home screen: reload whatever is on screen (its stream was stopped), resume a program kept for Home
    /// where it was, and show the banner so the viewer sees where they landed.
    func returnedToForeground() {
        guard backgrounded else { return }
        backgrounded = false
        if Platform.isTV, overlay == .options, optionsTopLevel { closeOverlay() }   // left from Options: back on the drifting guide
        if resumeAfterBackground, var pb = playback { pb.paused = false; pb.startedAt = .now; playback = pb; followEndOfProgram() }
        // The reload below, or the address pick's, fetches a fresh stream: Play needs no second one. Stamped here as well as
        // in WatchScreen's load: Play while a plain-http link's pick runs would otherwise reload into the dropped link.
        if playback?.paused == true { playback?.startedAt = .now }
        resumeAfterBackground = false
        if screen == .watch, watchInfo()?.isBreak != true { bannerVisible = true; bannerFocus = -1; trackMenu = nil; bannerLater() }   // a break's card says it all
        // A plain-http Plex link (dropped on the way out) picks its address again before anything reloads: the reload
        // carries the token there. With nothing verified to move to, it stays dropped and the reload finds none.
        let pickFirst = plainHTTPLink
        let reload = { [self] in foregroundSerial += 1; if screen == .watch { tunes += 1 } }
        if !pickFirst { reload() }
        Task {
            #if !os(tvOS)
            // The device may have left (or come home to) the server's network: an https link reloaded already and reloads
            // again if its address moves (a movie started on the old one); a dropped http link reloads below once checked.
            if pickFirst { await pickPlexAddress() } else { await networkChanged() }
            #endif
            if pickFirst, !backgrounded, !pip { reload() }   // away again meanwhile: that way back picks and reloads
            await checkRecentlyAdded()   // opening the app brings the "what's new" channels up to date
        }
    }

    // MARK: Soyboi spot

    /// The bundled spots, in the order they take turns. Each is 30 s, 1080p H.264 + AAC.
    static let spotURLs = ["beacon-they-live", "beacon-rental", "beacon-trail", "beacon-cafe"].compactMap { Bundle.main.url(forResource: $0, withExtension: "mp4") }
    static let spotLength: TimeInterval = 30

    /// The spot this break opens with, or nil. One trailer break in 15 with room for a whole spot (counted once per
    /// break, across launches), the spots taking turns; never on channel 99, never with the setting or this channel's
    /// trailers off.
    func dueSpot(_ ch: Channel, slot: Slot, at now: Date = .now) -> URL? {
        guard let first = Self.spotURLs.first else { return nil }
        if spotOverride { spotOverride = false; return first }
        guard settings.houseSpots, settings.trailerBreaks, ch.trailerBreaks, !ch.isScrambled,
              slot.end.timeIntervalSince(now) >= Self.spotLength + 2 else { return nil }
        let d = UserDefaults.standard
        var r = d.data(forKey: "spotRotation").flatMap { try? JSONDecoder().decode(SpotRotation.self, from: $0) } ?? SpotRotation()
        let due = r.next("\(ch.id)|\(Int(slot.start.timeIntervalSince1970))")
        d.set(try? JSONEncoder().encode(r), forKey: "spotRotation")
        return due ? Self.spotURLs[r.pick(of: Self.spotURLs.count)] : nil
    }

    /// Seconds into the spot before it can be skipped.
    static let spotSkipDelay: TimeInterval = 5
    /// The Sleep chip's choices after Off, in minutes; 0 is End of program.
    static let sleepSteps = [0, 30, 60, 90]
    /// The sleep toast comes this long before the pause; also the grace for a deadline passed while the player wasn't ticking.
    static let sleepWarning: TimeInterval = 60
    /// Play after a pause longer than this reloads the stream at that spot.
    /// ponytail: Jellyfin kills an idle HLS job at 60 s and restarts it on demand; Plex within minutes (about 3, from server
    /// logs, undocumented); Emby unknown. Raise it only if a server dashboard shows sessions outliving it.
    static let stalePause: TimeInterval = 60

    /// WatchScreen: the spot started playing (`end` hands over to the trailers, like the spot's own end), or, with nil, it's gone.
    func spotChanged(end: (@MainActor () -> Void)?) {
        let s = SpotOnAir.shared
        cancelTimer("spot")
        s.started = end == nil ? nil : .now; s.skippable = false; s.end = end ?? {}
        if end != nil { later("spot", seconds: Self.spotSkipDelay) { s.skippable = true } }
    }

    /// Select / Right, or a tap on the Skip chip, during the spot: once the countdown is done, end it like its own end.
    func skipSpot() {
        let s = SpotOnAir.shared
        guard s.started != nil, s.skippable else { return }
        let end = s.end
        spotChanged(end: nil); end()
    }

    func goLast() {
        if let c = lastChannel { tune(c.id, mode: .live) } else { toast("No last channel yet. Change channels first.") }
    }

    /// Left / Right while watching: 10 s back or ahead per press, the step Apple's own player uses. The player
    /// moves the picture as far inside the stream it has (`seek`); a stream that does not reach is loaded again
    /// from the new spot. Rewinding a live program time-shifts it; fast-forwarding a shifted one can catch up to live.
    func skip(_ seconds: TimeInterval) {
        guard var pb = playback, let info = watchInfo() else { return }
        bannerVisible = true; bannerLater()
        let runtime = info.slot.item.runtime, sinceStart = Date.now.timeIntervalSince(info.slot.start)
        guard info.position < runtime else { return }   // a trailer break: nothing to scrub
        // A program ahead of the clock (started before it aired) has no live point to catch up to: it stays
        // time-shifted, also once its slot is on the air, and a skip moves it 10 s, not back to the clock.
        let liveEdge = sinceStart > 0 && info.position < sinceStart + 1 ? sinceStart : .infinity
        let target = max(0, min(info.position + seconds, runtime - 1, liveEdge))
        let fromStart = pb.fromStart && info.slot == pb.slot   // not onto the next program, joined midway once the kept slot ended
        // Paused, `startedAt` says how fresh the stream is (`togglePause`, WatchScreen's `load`): a skip keeps that, and
        // past `stalePause` the player is told to ask for a new stream instead of seeking in one the server has dropped.
        let fresh = pb.paused ? pb.startedAt : .now, stale = pb.paused && Date.now.timeIntervalSince(pb.startedAt) > Self.stalePause
        // Ahead to within 5 s of live is live: every seek on the way back and forth put the clock back by as long as its
        // picture stood still (`seekLanded`), and back 10 then ahead 10 means live.
        // ponytail: 5 s covers a few seeks. Keep the sum of those corrections in Playback if a slow server leaves viewers short of live.
        if target >= liveEdge - (seconds > 0 ? 5 : 1), !pb.paused {   // caught up, or never left live; a paused one stays paused, at the live point at most
            guard !info.live else { return }   // not the mode: a program that has caught up reads live before the tick says so
            pb = Playback(channelID: pb.channelID, mode: .live, programStart: info.slot.start, slot: info.slot, tracks: pb.tracks, fromStart: fromStart)
        } else {
            pb = Playback(channelID: pb.channelID, mode: .start, programStart: info.slot.start, offset: target, startedAt: fresh, paused: pb.paused, slot: info.slot, tracks: pb.tracks, fromStart: fromStart)
        }
        playback = pb
        followEndOfProgram()
        skipCue = seconds < 0 ? -1 : 1; later("skip-cue", seconds: 1) { [weak self] in self?.skipCue = 0 }
        seek = Seek(n: seek.n + 1, moved: seek.moved + (pb.mode == .live ? sinceStart : target) - info.position, stale: stale)
    }

    /// A skip's seek left the picture `behind` seconds further behind the program's clock than it was (WatchScreen's
    /// player says so once it plays again): the clock ran on while the picture stood still, and the picture may have
    /// come back a key frame past where it was sent (then `behind` can be negative). The clock follows the picture, by
    /// a minute at most and never to before the program's start. Left alone, every skip moved the two further apart,
    /// and the break cut that much off the program's ending, or came that much after it. A live program stays on
    /// the clock.
    func seekLanded(behind: TimeInterval) {
        guard var pb = playback, pb.mode == .start, !pb.paused else { return }
        pb.startedAt = min(pb.startedAt + max(-60, min(behind, 60)), Date.now + pb.offset)
        playback = pb
        followEndOfProgram()
    }

    /// Play/Pause: live becomes time-shifted and paused; paused resumes (a paused break goes back to live); playing pauses.
    /// `now` is the tick's own second when the sleep timer pauses: read a moment later, a program in its last second
    /// could be over, and the pause would land on what live has moved on to.
    func togglePause(at now: Date = .now) {
        guard var pb = playback, let info = watchInfo(at: now) else { return }
        // `info.live`, not the mode: a started-over program that has caught up reads live before the tick says so,
        // all through its break. A mark still owed for the same slot stays owed: the paused break reports it once the
        // server is back.
        if info.live {
            let same = info.slot == pb.slot   // as in `skip`
            pb = Playback(channelID: pb.channelID, mode: .start, programStart: info.slot.start, offset: info.position, paused: true, slot: info.slot, tracks: pb.tracks, fromStart: pb.fromStart && same, markDue: pb.markDue && same)
        }
        else if pb.paused {
            // A paused break (the sleep timer, headphones pulled) held nothing: Play goes back to the clock, where the break
            // carries on into the next program or is long over.
            if info.isBreak { tune(info.channel.id, mode: .live, force: true); return }
            if now.timeIntervalSince(pb.startedAt) > Self.stalePause { tunes += 1 }   // the server has likely dropped the stream
            pb.startedAt = now; pb.paused = false; pb.held = false
        }
        else { pb.offset = info.position; pb.startedAt = now; pb.paused = true }
        playback = pb
        followEndOfProgram()
        if pb.paused { armPauseArt() }
        bannerVisible = true; bannerLater()
    }

    /// A call, an alarm or Siri took the sound and the system stopped the player (`began`), or the player is playing
    /// again. The program is held as by Play/Pause for as long and plays on from the same place: left running, the
    /// picture came back behind the clock and the break cut the program's ending by as much. WatchScreen keeps asking
    /// a held player to play, as it asks any that isn't paused, so the hold ends when the system lets it play: after
    /// the call, or on the way back from the call's own screen. A break and channel 99 hold nothing. `resume` false
    /// gives the hold up, a plain pause from there on (headphones pulled, the sleep timer). The viewer's own Play, a
    /// skip, another tune and the picture-in-picture window starting end it too.
    // ponytail: Play pressed while the call is still on ends the hold although the player cannot play yet, so the
    // picture then comes back behind the clock as it used to. Hold again when a play is refused if viewers do that.
    // A hold longer than `stalePause` ends with a second of the old stream before the reload that saves a dropped one.
    func audioInterrupted(_ began: Bool, resume: Bool = true) {
        if began {
            guard !backgrounded, playback?.paused == false, let info = watchInfo(), !info.isBreak, !info.channel.isScrambled else { return }
            togglePause(); playback?.held = true
            if overlay != nil { hideBanner() }   // Program info is up: the pause's banner would be stranded under it
        } else if playback?.held == true {
            guard resume else { playback?.held = false; return }
            guard !backgrounded else { return }   // away: it stays held, and the way back asks the player again
            togglePause()
            if bannerFocus < 0 { hideBanner() }   // it plays on as it was: no banner for that, unless the viewer is in it
        }
    }

    /// Paused this long with no press, the program's art covers the paused picture (WatchScreen).
    static let pauseArtDelay: TimeInterval = 15

    /// The pause, or a press while paused: the art comes `pauseArtDelay` after the next whole second, the screen's tick,
    /// so what `pauseArtShown` says is what is drawn.
    func armPauseArt() { pauseArtAt = Date(timeIntervalSinceReferenceDate: Date.now.timeIntervalSinceReferenceDate.rounded(.up) + Self.pauseArtDelay) }

    /// The program's art is over the paused picture: not on channel 99 (it draws itself), not in a break (the card or a
    /// trailer is on, not the program) nor in picture in picture. WatchScreen draws it from this and the remote's Back
    /// reads it, so they agree.
    func pauseArtShown(at now: Date = .now) -> Bool {
        guard playback?.paused == true, !pip, let at = pauseArtAt, now >= at, let info = watchInfo(at: now) else { return false }
        return !info.channel.isScrambled && !info.isBreak   // nothing of it on screen: nothing to put away either
    }

    static func sleepLabel(_ minutes: Int?) -> String { minutes.map { $0 == 0 ? "End of program" : "\($0) min" } ?? "Off" }
    func cycleSleep() {
        let i = sleep.flatMap { Self.sleepSteps.firstIndex(of: $0.minutes) } ?? -1
        setSleep(i + 1 < Self.sleepSteps.count ? Self.sleepSteps[i + 1] : nil)
    }
    /// Arm (0 = when the program on screen ends, in a break when the next one ends) or clear (nil). A whole second, the
    /// tick's. End of program is the last whole second inside the program, never the break's first. A packed short ends
    /// with its slot, not its runtime (`watchInfo`'s caught-up rule uses the same bound).
    func setSleep(_ minutes: Int?) {
        guard let minutes, let info = watchInfo() else { sleep = nil; return }
        let now = Date.now.timeIntervalSinceReferenceDate
        let at: TimeInterval
        if minutes > 0 { at = (now + Double(minutes * 60)).rounded(.up) }
        else {
            var end = now + min(info.slot.item.runtime, info.slot.duration) - info.position
            if info.isBreak {
                // A time-shifted break doesn't roll into `next`: when it runs out, live picks up what is on air then
                // (`watchInfo`'s caught-up rule), or the program after that if it is already in its own break.
                let handover = Date(timeIntervalSinceReferenceDate: now + info.slot.duration - info.position)
                var next = info.live ? info.next : slotOnAir(info.channel, at: handover)
                if !info.live, let n = next, n.itemEnd <= handover { next = slotOnAir(info.channel, at: n.end) }
                end = (next?.itemEnd ?? info.slot.end).timeIntervalSinceReferenceDate
            }
            at = max(now.rounded(.up) + 1, end.rounded(.up) - 1)
        }
        // A re-arm (a pause or Play) a moment after the one-minute toast keeps it gone: the rounding can put the new
        // deadline a fraction over the minute.
        sleepWarned = at - now <= Self.sleepWarning || (sleep?.minutes == 0 && sleepWarned && at - now <= Self.sleepWarning + 1)
        sleep = Sleep(at: Date(timeIntervalSinceReferenceDate: at), minutes: minutes)
    }
    /// End of program follows the program on screen: its end is read again after anything that moves it against the
    /// clock (a tune, Pause or Play, a skip, the return of a program kept for Home).
    func followEndOfProgram() { if sleep?.minutes == 0 { setSleep(0) } }
    /// When the timer goes off: its whole second, except that End of program waits while its program is paused. Paused,
    /// the program's end moves on with the clock, so it reads what is left of the program, never under a second, until
    /// Play arms it again.
    func sleepAt(_ now: Date = .now) -> Date? {
        guard let s = sleep else { return nil }
        guard s.minutes == 0, playback?.paused == true, let info = watchInfo(at: now), !info.isBreak else { return s.at }
        return now.addingTimeInterval(max(1, min(info.slot.item.runtime, info.slot.duration) - info.position))
    }
    /// "Sleep in 38 min" (the banner's status line), or spoken, "38 minutes left". Minutes rounded up.
    func sleepText(at now: Date = .now, spoken: Bool = false) -> String? {
        guard let due = sleepAt(now) else { return nil }
        let m = max(1, Int((due.timeIntervalSince(now) / 60).rounded(.up)))
        return spoken ? "\(m) minute\(m == 1 ? "" : "s") left" : "Sleep in \(m) min"
    }

    /// Banner buttons: [Pause | Play] (not in a break), [Start over | Back to live], Program info, Audio, Subtitles,
    /// Last channel · N, Sleep · Off. Audio and Subtitles open a list of the program's tracks over the button, the one on checked.
    func watchActions() -> [(label: String, run: @MainActor () -> Void)] {
        guard let info = watchInfo() else { return [] }
        let ch = info.channel, slot = info.slot
        var a: [(label: String, run: @MainActor () -> Void)] = []
        if !info.isBreak { a.append((playback?.paused == true ? "Play" : "Pause", { [weak self] in self?.togglePause() })) }
        if info.live { a.append(("Start over", { [weak self] in self?.tune(ch.id, mode: .start, programStart: slot.start) })) }
        else { a.append(("Back to live", { [weak self] in self?.tune(ch.id, mode: .live, force: true) })) }
        a.append(("Program info", { [weak self] in self?.openInfo(ProgramKey(channelID: ch.id, start: slot.start)) }))
        for (kind, name) in [(MediaTrack.Kind.audio, "Audio"), (.subtitle, "Subtitles")] where trackChoices(kind).count >= 2 {   // one audio track: nothing to pick
            a.append((name, { [weak self] in self?.openTrackMenu(kind) }))
        }
        if let last = lastChannel { a.append(("Last channel · \(last.number)", { [weak self] in self?.goLast() })) }
        a.append(("Sleep · " + Self.sleepLabel(sleep?.minutes), { [weak self] in self?.cycleSleep() }))
        return a
    }

    /// The rows of the banner's Audio or Subtitles list, the one playing marked `on`. Subtitles: Off, Forced only (only
    /// while it's the choice: the server's pick, which the list can't offer back once left), then each track.
    func trackChoices(_ kind: MediaTrack.Kind) -> [(label: String, on: Bool, apply: (inout TrackSelection) -> Void)] {
        guard let item = watchInfo()?.slot.item else { return [] }
        let tracks = playbackTracks.filter { $0.kind == kind }, sel = trackSelection(for: playbackTracks, itemID: item.id)
        if kind == .audio {
            let on = tracks.firstIndex { $0.id == sel.audioID } ?? tracks.firstIndex(where: \.isDefault) ?? 0
            return tracks.enumerated().map { i, t in (Self.trackName(t, among: tracks), i == on, { $0.audioID = t.id }) }
        }
        guard !tracks.isEmpty else { return [] }
        var rows: [(label: String, on: Bool, apply: (inout TrackSelection) -> Void)] = [("Off", sel.subtitle == .off, { $0.subtitle = .off })]
        if sel.subtitle == .auto { rows.append(("Forced only", true, { $0.subtitle = .auto })) }
        rows += tracks.map { t in (Self.trackName(t, among: tracks), sel.subtitle == .track(t.id), { $0.subtitle = .track(t.id) }) }
        return rows
    }

    /// The banner's Audio or Subtitles button: its list opens on the choice that's on, and holds the banner up.
    func openTrackMenu(_ kind: MediaTrack.Kind) {
        cancelTimer("banner")
        trackMenu = TrackMenu(kind: kind, focus: trackChoices(kind).firstIndex(where: \.on) ?? 0)
    }

    /// Up / Down move through the list (a drag or the scroll wheel too), Select plays the choice (a reload, unless it's
    /// the one on), Back puts the list away. Left / Right do nothing while it's open.
    func pressTrackMenu(_ cmd: RemoteCommand) {
        guard var m = trackMenu else { return }
        let c = trackChoices(m.kind)
        switch cmd {
        case .up, .down:
            m.focus = max(0, min(c.count - 1, m.focus + (cmd == .down ? 1 : -1))); trackMenu = m
        case .select:
            trackMenu = nil; bannerLater()
            if c.indices.contains(m.focus), !c[m.focus].on { setTracks(c[m.focus].apply) }
        case .back: trackMenu = nil; bannerLater()
        default: break
        }
    }

    /// "English"; the server's own title ("Commentary", "English (AC3 5.1)") when the language is unknown or shared by another track.
    static func trackName(_ t: MediaTrack, among: [MediaTrack]) -> String {
        let lang = MediaTrack.languageName(t.language)
        let shared = among.filter { $0.language == t.language }.count > 1
        return (lang == nil || shared) && !t.title.isEmpty ? t.title : lang ?? "Track \(t.id)"
    }

    /// Per-program override from the banner: the player reloads at the current position with the new tracks.
    /// The override holds for that program only (`itemID`, default the one on now).
    private func setTracks(itemID: String? = nil, _ change: (inout TrackSelection) -> Void) {
        guard playback != nil, let id = itemID ?? watchInfo()?.slot.item.id else { return }
        var sel = trackSelection(for: playbackTracks, itemID: id); change(&sel)
        playback?.tracks = .init(itemID: id, selection: sel); tunes += 1
    }

    /// Program `itemID`, asked for with a subtitle, didn't start: reload it at the same position with subtitles off.
    func dropSubtitles(itemID: String) {
        setTracks(itemID: itemID) { $0.subtitle = .off }
        toast("Couldn’t show subtitles for this one.")
    }

    /// The prototype's onTick: a started-over program that has caught up (`watchInfo`) goes back to live. Also marks a
    /// program started from its beginning watched on the server once it has played to 90%.
    func watchTick(at now: Date = .now) {
        guard screen == .watch, var pb = playback, let info = watchInfo(at: now) else { return }
        // The sleep timer, before the caught-up rule below so nothing overwrites its pause in the same tick. Behind the
        // Home screen the tick may still run (Android, the web): the deadline waits for the return.
        if let due = sleepAt(now), !backgrounded {
            let left = due.timeIntervalSince(now)
            if left > 0 {
                if left <= Self.sleepWarning, !sleepWarned { sleepWarned = true; toast("Sleep timer. One minute left.") }
            } else if SpotOnAir.shared.started == nil {   // a spot on screen plays out first; the next tick after it stops
                sleep = nil   // first, so no tick fires it twice
                if left > -Self.sleepWarning {   // passed while not ticking (Home, picture in picture): a minute late is still honest
                    // Paused by hand already: the pause stands, the toast says why nothing follows. Held for a call: a
                    // plain pause from here on, or the call's end would play on after the good night. Late for a
                    // started-over program that is over, live on another program by now (End of program armed in its
                    // last second, a tick that came late): its own break holds, not the program live has moved on to.
                    // Only for one that ended with the deadline, within 2 s: ended long before, it is not what the
                    // viewer has been looking at. In a break the pause is the ordinary one, and that break holds.
                    if pb.paused { playback?.held = false }
                    else if pb.mode == .start, info.live, !info.isBreak, let kept = pb.slot,
                            due.timeIntervalSince(pb.startedAt) <= min(kept.item.runtime, kept.duration) - pb.offset + 2 {
                        playback?.offset += now.timeIntervalSince(pb.startedAt); playback?.startedAt = now; playback?.paused = true
                    }
                    else { togglePause(at: now) }
                    if overlay != nil { hideBanner() }   // Program info is up: the pause's banner would be stranded under it
                    toast("Sleep timer. Good night.")
                    return
                }
            }
        }
        // Caught up (`watchInfo`) and a program is on: live from here, joined as a tune to what is on would (a kept
        // slot left behind must not come back when the clock gets to it), before the mark below reads the playback.
        // A break is left as it is: it reads live already, a mark still owed is reported in it, and the toast comes
        // with the next program. Not behind the Home screen either, where the tick may still run (Android, the web):
        // the toast is for a viewer. A kept slot with no break to speak of (a packed short started before it aired:
        // none, or under the second a tick takes to see one) is its own program again at another place under the same
        // load key: the stream is asked to move.
        if pb.mode == .start, info.live, !info.isBreak, !backgrounded {
            if info.slot == pb.slot, info.slot.duration - info.slot.item.runtime < 1 { tunes += 1 }
            pb = Playback(channelID: pb.channelID, mode: .live, programStart: info.slot.start, slot: info.slot)
            playback = pb
            toast("Caught up. Back to live.")
        }
        // Only the program tuned counts, not its break (trailers, the spot) nor channel 99. Once per playback, no toast,
        // a failure only logged. No server (a plain-http link dropped while away): a later tick of this slot reports it
        // once it's back, its break too.
        // The library's own `watched` stays as it is, so the lineup doesn't change under the viewer: the Unwatched
        // channel drops the program at the next library refresh.
        if pb.fromStart, info.slot == pb.slot, !info.isBreak || pb.markDue, !info.channel.isScrambled,
           info.position >= 0.9 * info.slot.item.runtime {
            if let server {
                playback?.fromStart = false
                let item = info.slot.item
                Task { do { try await server.markWatched(item) } catch { print("markWatched:", error) } }
            } else if !pb.markDue { playback?.markDue = true }
        }
    }
}

/// The banner's open Audio or Subtitles list: which, and the row the remote is on.
struct TrackMenu: Equatable { let kind: MediaTrack.Kind; var focus: Int }

/// The house spot on screen: WatchScreen holds its stream, the remote and VoiceOver need when it started and whether it
/// can be skipped yet. Its own object since an extension can't add stored properties to AppModel; observed like it.
@MainActor @Observable final class SpotOnAir {
    static let shared = SpotOnAir()
    var started: Date? = nil
    /// The 5 s countdown is done: Select / Right (a tap on touch) end the spot.
    var skippable = false
    @ObservationIgnored var end: @MainActor () -> Void = {}
}

/// A UIKit background task around a short async job. `end` is safe to call twice: the expiration handler may beat it.
@MainActor final class BackgroundTask {
    private var id = UIBackgroundTaskIdentifier.invalid
    static func begin(_ name: String) -> BackgroundTask {
        let t = BackgroundTask()
        t.id = UIApplication.shared.beginBackgroundTask(withName: name) { t.end() }
        return t
    }
    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id); id = .invalid
    }
}
