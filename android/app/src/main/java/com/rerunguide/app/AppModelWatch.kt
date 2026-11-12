package com.rerunguide.app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.rerunguide.core.*
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.time.Instant
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/** What the picture is showing right now (port of the prototype's wInfo). */
data class WatchInfo(
    val channel: Channel,
    val slot: Slot,
    /** Seconds into the slot. `runtime ≤ position < duration` is the break after the program. */
    val position: Double,
    val live: Boolean,
    /** What the channel's current schedule airs at `slot.end` (what live rolls into). */
    val next: Slot?,
) {
    val isBreak: Boolean get() = position >= slot.item.runtime

    /** The progress bar: the time into the program ("1:02:15"), the clock time it ends (later while paused), and its fill
     *  over the program's runtime. A break keeps the slot's clock times, filled over the whole slot. */
    fun bar(now: Instant): Triple<String, String, Double> {
        val runtime = slot.item.runtime
        if (isBreak || runtime <= 0) return Triple(Clock.time(slot.start), Clock.time(slot.end), (position / slot.duration).coerceIn(0.0, 1.0))
        val s = position.toInt(); val end = now.plusSeconds(runtime - position)
        return Triple(if (s >= 3600) String.format(Locale.ROOT, "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) else String.format(Locale.ROOT, "%d:%02d", s / 60, s % 60),
            "Ends ${Clock.time(end)} ${Clock.ap(end)}", max(0.0, position / runtime))
    }
}

/** One banner button: the Swift `(label: String, run: () -> Void)` tuple. */
class WatchAction(val label: String, val run: () -> Unit)

/* Watching: banner, channel up/down, last channel, pause/time-shift (port of the prototype's k_watch/wInfo/flip/togglePause/watchActs). */

fun AppModel.watchInfo(at: Instant = Instant.now()): WatchInfo? {
    val pb = playback ?: return null
    val ch = channel(pb.channelID) ?: visibleChannels.firstOrNull() ?: return null
    // The slot tune() snapshotted, unless its channel is gone: a library refresh reshuffles every lineup and the
    // program must not change under the viewer. Live rolls into the current schedule once the snapshot ends.
    val kept = if (ch.id == pb.channelID) pb.slot else null
    if (pb.mode == Playback.Mode.start) {
        val s = kept ?: slot(ch, pb.programStart) ?: slotOnAir(ch, at) ?: return null
        val position = pb.offset + (if (pb.paused) 0.0 else at.secondsSince(pb.startedAt))
        // Caught up: a started-over program that has ended is live again as soon as the clock is past its end too
        // (`watchTick` makes it the playback, and says so, once a program is on). So its break is the channel's
        // own: it ends with the slot and the next program starts on time, however long a pause or a call held this
        // one. Further behind than the break is long, there is none left: it joins what is on. One started before
        // it aired is ahead of the clock: its break runs as long as the slot's first, unless the clock gets to the
        // program's end sooner. A pause holds everything, a break too.
        if (pb.paused || position < minOf(s.item.runtime, s.duration) || (at < s.itemEnd && position < s.duration))
            return WatchInfo(ch, s, position, live = false, next = slotOnAir(ch, s.end))
    }
    // On air: a kept slot that has not begun (one watched before it aired, live again since) waits its turn.
    val s = kept?.takeIf { it.start <= at && at < it.end } ?: slotOnAir(ch, at) ?: return null
    return WatchInfo(ch, s, at.secondsSince(s.start), live = true, next = slotOnAir(ch, s.end))
}

fun AppModel.pressWatch(cmd: RemoteCommand) {
    val pb = playback ?: return
    if (pb.paused) {   // any press puts the program's art away for another 15 s; Back with it up does only that
        val artUp = pauseArtShown()
        armPauseArt()
        if (artUp && cmd == RemoteCommand.back) return
    }
    if (trackMenu != null && cmd != RemoteCommand.play) { pressTrackMenu(cmd); return }
    when (cmd) {
        // From the banner's buttons Up goes to its progress bar, and Down comes back; otherwise they change channels.
        RemoteCommand.up -> if (bannerVisible && bannerFocus >= 0) { barFocused = true; bannerLater() } else flip(1)
        RemoteCommand.down -> if (bannerVisible && bannerFocus >= 0 && barFocused) { barFocused = false; bannerLater() } else flip(-1)
        // Back hides the banner first (its info alone too); held upright none is drawn, and Back leaves at once. Full
        // screen goes back to portrait Now playing.
        RemoteCommand.back -> if (bannerVisible && !portrait) hideBanner() else if (fullScreen) fullScreen = false else toGuide(pb.channelID)
        // In a break Play/Pause is "watch it again": pausing a break holds nothing. A break that is paused all the same (the
        // sleep timer, headphones pulled, the audio focus lost) goes back to live (`togglePause`).
        RemoteCommand.play -> if (!pb.paused && watchInfo()?.isBreak == true) restartFromBreak() else togglePause()
        RemoteCommand.left, RemoteCommand.right, RemoteCommand.select -> {
            if (bannerVisible && bannerFocus >= 0 && barFocused) {   // the progress bar: Left / Right skip, OK is Play/Pause
                if (cmd != RemoteCommand.select) skip(if (cmd == RemoteCommand.left) -10.0 else 10.0) else if (watchInfo()?.isBreak != true) togglePause()
                bannerLater(); return
            }
            if (bannerVisible && bannerFocus >= 0) {
                val acts = watchActions()
                if (acts.isEmpty()) { hideBanner(); return }   // no watchInfo (channels gone mid-program)
                when (cmd) {
                    RemoteCommand.left -> bannerFocus = max(0, bannerFocus - 1)
                    RemoteCommand.right -> bannerFocus = min(acts.size - 1, bannerFocus + 1)
                    else -> acts[min(bannerFocus, acts.size - 1)].run()
                }
                bannerLater(); return
            }
            // The spot: Select / Right skip it once its countdown is done, and do nothing before that.
            if (cmd != RemoteCommand.left && SpotOnAir.started != null) { skipSpot(); return }
            if (cmd == RemoteCommand.select && watchInfo()?.let { it.isBreak && it.next != null } == true) { startNextFromBreak(); return }   // the break card's OK
            if (cmd == RemoteCommand.left) { skip(-10.0); return }
            if (cmd == RemoteCommand.right) { skip(10.0); return }
            bannerVisible = true; bannerFocus = 0; barFocused = false
            bannerLater()
        }
    }
}

/** In a break, for its card: the viewer saw this program end, so it "just ended" whatever the clock says; otherwise the
 *  card gives the clock time it ended at. A break after a program watched behind the clock reads live (`watchInfo`),
 *  but its playback is still the started-over one, on this slot, until the next program (`watchTick`): that tells it
 *  from a break joined on the air, and from another program's break it ran into. */
fun AppModel.justEnded(info: WatchInfo): Boolean = !info.live || (playback?.mode == Playback.Mode.start && playback?.slot == info.slot)

/** In a break: the program that just ended, from its beginning (Play/Pause, or the break card's pill). */
fun AppModel.restartFromBreak() {
    val info = watchInfo() ?: return
    tune(info.channel.id, Playback.Mode.start, programStart = info.slot.start)
}

/** In a break: the next program, from its beginning, without waiting for its slot (Select, or the break card's pill). */
fun AppModel.startNextFromBreak() {
    val info = watchInfo() ?: return
    val next = info.next ?: return
    tune(info.channel.id, Playback.Mode.start, programStart = next.start)
}

/** Hide the banner 6 s from now. */
fun AppModel.bannerLater() = later("banner", seconds = 6.0) { if (overlay == null && trackMenu == null) { bannerVisible = false; bannerFocus = -1 } }
fun AppModel.hideBanner() { cancelTimer("banner"); bannerVisible = false; bannerFocus = -1; trackMenu = null }

/** Channel up (+1) / down (−1) through the visible channels, wrapping. From a channel outside them (typed, searched or
 *  Last channel under the Favorites guide), the next one above or below it on the dial. */
fun AppModel.flip(d: Int) {
    val list = visibleChannels
    val pb = playback
    if (list.isEmpty() || pb == null) return
    val i = list.indexOfFirst { it.id == pb.channelID }
    if (i >= 0) { if (list.size > 1) tune(list[((i + d) % list.size + list.size) % list.size].id, Playback.Mode.live); return }   // the only one: nothing to reload
    val n = channel(pb.channelID)?.number ?: 0
    tune((if (d > 0) list.firstOrNull { it.number > n } ?: list[0] else list.lastOrNull { it.number < n } ?: list[list.size - 1]).id, Playback.Mode.live)
}

// MARK: Number keys

/** The channel numbered `numbered` in this profile's lineup: a hidden one counts as missing. */
fun AppModel.channel(numbered: Int): Channel? = channels.firstOrNull { it.number == numbered && !isHidden(it.id) }
/** The channel the digits typed so far name. */
val AppModel.entryChannel: Channel? get() = channelEntry?.digits?.toIntOrNull()?.let { channel(numbered = it) }

/** A number key on the guide or the player with nothing over them: the box in the top-right corner collects up to
 *  three digits and tunes 2 s after the last one, at the third, or on OK. Digits do nothing anywhere else. */
fun AppModel.pressDigit(d: Int) {
    if (overlay != null || editingField != null || trackMenu != null || (screen != Screen.guide && screen != Screen.watch)) return
    if (attracting) attractReset()   // the box wakes the screen instead of sitting on the screensaver
    val digits = (channelEntry?.takeIf { !it.missing }?.digits ?: "") + d
    channelEntry = AppModel.ChannelEntry(digits); lastEntry = channelEntry
    if (digits.length == 3) commitEntry() else later("entry", seconds = 2.0) { commitEntry() }
}

/** While the box collects digits, OK tunes now and Back cancels; any other press closes it and does what it does.
 *  True when the box took the press. */
fun AppModel.pressEntry(cmd: RemoteCommand): Boolean {
    if (channelEntry?.missing != false) return false
    if (cmd == RemoteCommand.select) { commitEntry(); return true }
    closeEntry()
    return cmd == RemoteCommand.back
}

/** Put the box away without tuning: a tap, a channel change or a screen went elsewhere. */
fun AppModel.closeEntry() { cancelTimer("entry"); channelEntry = null }

/** Tune to the typed number like a channel change (the tune-mode setting applies). The channel already on screen
 *  just closes the box; a number with no channel says so for 2 s and changes nothing. */
fun AppModel.commitEntry() {
    val e = channelEntry ?: return
    val n = e.digits.toIntOrNull()
    if (e.missing || n == null) return
    closeEntry()
    if (overlay != null || editingField != null || pip || (screen != Screen.guide && screen != Screen.watch)) return   // moved on, or away in picture in picture
    val ch = channel(numbered = n) ?: run {
        channelEntry = AppModel.ChannelEntry(e.digits, missing = true); lastEntry = channelEntry
        later("entry", seconds = 2.0) { channelEntry = null }
        return
    }
    if (screen == Screen.watch && playback?.channelID == ch.id) return
    val fromGuide = screen == Screen.guide
    tune(ch.id, Playback.Mode.live)
    if (fromGuide) bannerVisible = watchInfo()?.isBreak != true   // a number names a channel, not what's on it
}

// MARK: Background

/** Leaving for the Home screen (Back from the guide, or the Home button): ask the server to stop both streams now,
 *  instead of leaving it transcoding until it notices nobody is pulling, and hold a started-over program's place.
 *  A live program needs nothing held: it rejoins live on the way back, like changing back to a channel.
 *  (Android keeps the process running after onStop, so no background-task wrapper is needed.) */
fun AppModel.enteredBackground() {
    if (backgrounded) return
    backgrounded = true
    val pb = playback
    val info = watchInfo()
    if (pb != null && pb.mode == Playback.Mode.start && !pb.paused && info != null && !info.live) {   // live: caught up, whatever the mode still says
        playback = pb.copy(offset = info.position, paused = true); resumeAfterBackground = true
        pauseArtAt = null   // held, not paused by the viewer: no art behind the Home screen
    } else if (pb != null && pb.mode == Playback.Mode.live && !pb.markDue) playback = pb.copy(fromStart = false)   // a caught-up start-over rejoins live on the way back: no longer from the beginning
    cancelTimer("seek"); closeEntry()   // a typed number doesn't tune behind the Home screen
    if (screen == Screen.link) linkTask?.cancel()   // tvOS suspends the app; here the PIN poll would keep running
    val server = server ?: return
    scope.launch { server.stopPlayback("watch"); server.stopPlayback("preview") }
    // A plain-http Plex link may come back on another network, where the guide's posters and preview would carry the
    // token before the return's pick finishes. Dropped now, that pick rebuilds it once its address checks out.
    val cfg = persisted.serverConfig
    if (!Platform.isTV && cfg?.addresses != null && cfg.baseURL.startsWith("http://")) this.server = null
}

/** Back from the Home screen: reload whatever is on screen (its stream was stopped), resume a program kept for Home
 *  where it was, and show the banner so the viewer sees where they landed. */
fun AppModel.returnedToForeground() {
    if (!backgrounded) return
    backgrounded = false
    val pb = playback
    if (resumeAfterBackground && pb != null) { playback = pb.copy(paused = false, startedAt = Instant.now()); followEndOfProgram() }
    playback?.let { if (it.paused) playback = it.copy(startedAt = Instant.now()) }   // the reload below, or the address pick's, fetches a fresh stream, so Play needs no second one
    resumeAfterBackground = false
    fun reload() { foregroundSerial += 1; if (screen == Screen.watch) tunes += 1 }
    // A plain-http Plex link (dropped on the way out) picks first: the reload carries the token, maybe to a stranger's
    // LAN. With nothing verified to move to, it stays dropped and the reload finds none.
    val cfg = persisted.serverConfig
    val pickFirst = !Platform.isTV && cfg?.addresses != null && cfg.baseURL.startsWith("http://")
    if (!pickFirst) reload()
    if (screen == Screen.watch && watchInfo()?.isBreak != true) { bannerVisible = true; bannerFocus = -1; trackMenu = null; bannerLater() }   // a break's card says it all
    if (screen == Screen.link) startLink()   // a fresh code: the poll stopped in the background
    scope.launch {
        // The device may have left (or come home to) the server's network: an https link reloaded already and reloads
        // again if its address moves (a movie started on the old one); a dropped http link reloads below once checked.
        if (!Platform.isTV) { if (pickFirst) pickPlexAddress() else networkChanged() }
        if (pickFirst && !backgrounded) reload()   // hidden again meanwhile: that return picks and reloads
        checkRecentlyAdded()   // opening the app brings the "what's new" channels up to date
    }
}

// MARK: Soyboi spot

/** The bundled spots (res/raw), in the order they take turns, as URI strings ExoPlayer's MediaItem.fromUri takes. Each is
 *  30 s, 1080p H.264 + AAC. */
val AppModel.Companion.spotURLs: List<String>
    get() = listOf(R.raw.beacon_they_live, R.raw.beacon_rental, R.raw.beacon_trail, R.raw.beacon_cafe).map { "android.resource://${BuildConfig.APPLICATION_ID}/$it" }
val AppModel.Companion.spotLength: Double get() = 30.0

/** The spot this break opens with, or null. One trailer break in 15 with room for a whole spot (counted once per
 *  break, across launches), the spots taking turns; never on channel 99, never with the setting or this channel's
 *  trailers off. */
fun AppModel.dueSpot(ch: Channel, slot: Slot, at: Instant = Instant.now()): String? {
    val spots = AppModel.spotURLs
    val first = spots.firstOrNull() ?: return null
    if (spotOverride) { spotOverride = false; return first }
    if (!settings.houseSpots || !settings.trailerBreaks || !ch.trailerBreaks || ch.isScrambled ||
        slot.end.secondsSince(at) < AppModel.spotLength + 2) return null
    val d = AppModel.defaults
    val r = d.getString("spotRotation", null)?.let { runCatching { SpotRotation.fromJson(JSONObject(it)) }.getOrNull() } ?: SpotRotation()
    val due = r.next("${ch.id}|${slot.start.epochSecond}")
    d.edit().putString("spotRotation", r.toJson().toString()).apply()
    return if (due) spots[r.pick(spots.size)] else null
}

/** Seconds into the spot before it can be skipped. */
val AppModel.Companion.spotSkipDelay: Double get() = 5.0
/** The Sleep chip's choices after Off, in minutes; 0 is End of program. */
val AppModel.Companion.sleepSteps: List<Int> get() = listOf(0, 30, 60, 90)
/** The sleep toast comes this long before the pause; also the grace for a deadline passed while the player wasn't ticking. */
val AppModel.Companion.sleepWarning: Double get() = 60.0
/** Play after a pause longer than this reloads the stream at that spot.
 *  ponytail: Jellyfin kills an idle HLS job at 60 s and restarts it on demand; Plex within minutes (about 3, from server
 *  logs, undocumented); Emby unknown. Raise it only if a server dashboard shows sessions outliving it. */
val AppModel.Companion.stalePause: Double get() = 60.0

/** The house spot on screen: WatchScreen holds its stream, the remote and TalkBack need when it started and whether it
 *  can be skipped yet. Its own object since an extension can't add stored properties to AppModel. Its fields are Compose state, like the model's. */
object SpotOnAir {
    var started by mutableStateOf<Instant?>(null)
    /** The 5 s countdown is done: OK / Right (a tap on touch) end the spot. */
    var skippable by mutableStateOf(false)
    var end: () -> Unit = {}
}

/** WatchScreen: the spot started playing (`end` hands over to the trailers, like the spot's own end), or, with null, it's gone. */
fun AppModel.spotChanged(end: (() -> Unit)?) {
    cancelTimer("spot")
    SpotOnAir.started = if (end == null) null else Instant.now(); SpotOnAir.skippable = false; SpotOnAir.end = end ?: {}
    if (end != null) later("spot", seconds = AppModel.spotSkipDelay) { SpotOnAir.skippable = true }
}

/** OK / Right, or a tap on the Skip chip, during the spot: once the countdown is done, end it like its own end. */
fun AppModel.skipSpot() {
    if (SpotOnAir.started == null || !SpotOnAir.skippable) return
    val end = SpotOnAir.end
    spotChanged(null); end()
}

fun AppModel.goLast() {
    val c = lastChannel
    if (c != null) tune(c.id, Playback.Mode.live) else toast("No last channel yet. Change channels first.")
}

/** Left / Right while watching: 10 s back or ahead per press. The player moves the picture as far inside the stream it
 *  has (`seek`); a stream that does not reach is loaded again from the new spot. Rewinding a live program time-shifts
 *  it; fast-forwarding a shifted one can catch up to live. */
fun AppModel.skip(seconds: Double) {
    var pb = playback ?: return
    val info = watchInfo() ?: return
    bannerVisible = true; bannerLater()
    val runtime = info.slot.item.runtime
    val sinceStart = Instant.now().secondsSince(info.slot.start)
    if (info.position >= runtime) return   // a trailer break: nothing to scrub
    // A program ahead of the clock (started before it aired) has no live point to catch up to: it stays time-shifted,
    // also once its slot is on the air, and a skip moves it 10 s, not back to the clock.
    val liveEdge = if (sinceStart > 0 && info.position < sinceStart + 1) sinceStart else Double.POSITIVE_INFINITY
    val target = max(0.0, minOf(info.position + seconds, runtime - 1, liveEdge))
    val fromStart = pb.fromStart && info.slot == pb.slot   // not onto the next program, joined midway once the kept slot ended
    // Paused, `startedAt` says how fresh the stream is (`togglePause`, WatchScreen's `load`): a skip keeps that, and past
    // `stalePause` the player is told to ask for a new stream instead of seeking in one the server has dropped.
    val fresh = if (pb.paused) pb.startedAt else Instant.now()
    val stale = pb.paused && Instant.now().secondsSince(pb.startedAt) > AppModel.stalePause
    // Ahead to within 5 s of live is live: every seek on the way back and forth put the clock back by as long as its
    // picture stood still (`seekLanded`), and back 10 then ahead 10 means live.
    // ponytail: 5 s covers a few seeks. Keep the sum of those corrections in Playback if a slow server leaves viewers short of live.
    if (target >= liveEdge - (if (seconds > 0) 5 else 1) && !pb.paused) {   // caught up, or never left live; a paused one stays paused, at the live point at most
        if (info.live) return   // not the mode: a program that has caught up reads live before the tick says so
        pb = Playback(pb.channelID, Playback.Mode.live, programStart = info.slot.start, slot = info.slot, tracks = pb.tracks, fromStart = fromStart)
    } else {
        pb = Playback(pb.channelID, Playback.Mode.start, programStart = info.slot.start, offset = target, startedAt = fresh, paused = pb.paused, slot = info.slot, tracks = pb.tracks, fromStart = fromStart)
    }
    playback = pb
    followEndOfProgram()
    skipCue = if (seconds < 0) -1 else 1; later("skip-cue", seconds = 1.0) { skipCue = 0 }
    seek = AppModel.Seek(seek.n + 1, seek.moved + (if (pb.mode == Playback.Mode.live) sinceStart else target) - info.position, stale)
}

/** A skip's seek left the picture `behind` seconds further behind the program's clock than it was (WatchScreen's player
 *  says so once it plays again): the clock ran on while the picture stood still, and the picture may have come back a
 *  key frame past where it was sent (then `behind` can be negative). The clock follows the picture, by a minute at
 *  most and never to before the program's start. Left alone, every skip moved the two further apart, and the break
 *  cut that much off the program's ending, or came that much after it. A live program stays on the clock. */
fun AppModel.seekLanded(behind: Double) {
    val pb = playback ?: return
    if (pb.mode != Playback.Mode.start || pb.paused) return
    playback = pb.copy(startedAt = minOf(pb.startedAt.plusSeconds(max(-60.0, min(behind, 60.0))), Instant.now().plusSeconds(pb.offset)))
    followEndOfProgram()
}

/** Play/Pause: live becomes time-shifted and paused; paused resumes (a paused break goes back to live); playing pauses.
 *  `at` is the tick's own second when the sleep timer pauses: read a moment later, a program in its last second could
 *  be over, and the pause would land on what live has moved on to. */
fun AppModel.togglePause(at: Instant = Instant.now()) {
    var pb = playback ?: return
    val info = watchInfo(at) ?: return
    // `info.live`, not the mode: a started-over program that has caught up reads live before the tick says so,
    // all through its break. A mark still owed for the same slot stays owed: the paused break reports it once the
    // server is back.
    val same = info.slot == pb.slot   // as in `skip`
    pb = if (info.live) Playback(pb.channelID, Playback.Mode.start, programStart = info.slot.start, offset = info.position, paused = true, slot = info.slot, tracks = pb.tracks, fromStart = pb.fromStart && same, markDue = pb.markDue && same)
    else if (pb.paused) {
        // A paused break (the sleep timer, headphones pulled, the audio focus lost) held nothing: Play goes back to the
        // clock, where the break carries on into the next program or is long over.
        if (info.isBreak) { tune(info.channel.id, Playback.Mode.live, force = true); return }
        if (at.secondsSince(pb.startedAt) > AppModel.stalePause) tunes += 1   // the server has likely dropped the stream
        pb.copy(startedAt = at, paused = false, held = false)
    }
    else pb.copy(offset = info.position, startedAt = at, paused = true)
    playback = pb
    followEndOfProgram()
    if (pb.paused) armPauseArt()
    bannerVisible = true; bannerLater()
}

/** A call, an alarm or the assistant took the audio for a while and ExoPlayer holds itself (`began`), or the player is
 *  playing again. The program is held as by Play/Pause for as long and plays on from the same place: left running, the
 *  picture came back behind the clock and the break cut the program's ending by as much. WatchScreen keeps a held
 *  player asked to play, as it asks any that isn't paused, so the hold ends when the system lets it play: after the
 *  call, or on the way back from the call's own screen. A break and channel 99 hold nothing. `resume` false gives the
 *  hold up, a plain pause from there on (headphones pulled, the audio lost for good, a separate Pause key, the sleep
 *  timer). A skip or another tune end it too.
 *  Play pressed while the call is still on is held again at once, and so is any program whose request for the audio
 *  is refused (only a call refuses it): WatchScreen's `sync` and `ask`, which asks again until the call lets go.
 *  ponytail: a hold longer than `stalePause` ends with a moment of the old stream before the reload that saves a
 *  dropped one. */
fun AppModel.audioInterrupted(began: Boolean, resume: Boolean = true) {
    val pb = playback ?: return
    if (began) {
        val info = watchInfo() ?: return
        if (backgrounded || pb.paused || info.isBreak || info.channel.isScrambled) return
        togglePause(); playback = playback?.copy(held = true)
        if (overlay != null) hideBanner()   // Program info is up: the pause's banner would be stranded under it
    } else if (pb.held) {
        if (!resume) { playback = pb.copy(held = false); return }
        if (backgrounded) return   // away: it stays held, and the way back asks the player again
        togglePause()
        if (bannerFocus < 0) hideBanner()   // it plays on as it was: no banner for that, unless the viewer is in it
    }
}

/** Paused this long with no press, the program's art covers the paused picture (WatchScreen). */
val AppModel.Companion.pauseArtDelay: Double get() = 15.0

/** The pause, or a press while paused: the art comes `pauseArtDelay` after the next whole second, the screen's tick, so
 *  what `pauseArtShown` says is what is drawn. */
fun AppModel.armPauseArt() { pauseArtAt = Instant.ofEpochSecond(Instant.now().epochSecond + 1 + AppModel.pauseArtDelay.toLong()) }

/** The program's art is over the paused picture: not on channel 99 (it draws itself), not in a break (the card or a
 *  trailer is on, not the program) nor in picture in picture. WatchScreen draws it from this and the remote's Back reads
 *  it, so they agree. */
fun AppModel.pauseArtShown(at: Instant = Instant.now()): Boolean {
    val due = pauseArtAt ?: return false
    if (playback?.paused != true || pip || at < due) return false
    val info = watchInfo(at) ?: return false
    return !info.channel.isScrambled && !info.isBreak   // channel 99, or a break (its card or a trailer is on): nothing of the program to put away
}

fun AppModel.Companion.sleepLabel(minutes: Int?): String = minutes?.let { if (it == 0) "End of program" else "$it min" } ?: "Off"
fun AppModel.cycleSleep() {
    val i = sleep?.let { AppModel.sleepSteps.indexOf(it.minutes) } ?: -1
    setSleep(if (i + 1 < AppModel.sleepSteps.size) AppModel.sleepSteps[i + 1] else null)
}
/** Arm (0 = when the program on screen ends, in a break when the next one ends) or clear (null). A whole second, the
 *  tick's. End of program is the last whole second inside the program, never the break's first. A packed short ends
 *  with its slot, not its runtime (`watchInfo`'s caught-up rule uses the same bound). */
fun AppModel.setSleep(minutes: Int?) {
    val info = watchInfo()
    if (minutes == null || info == null) { sleep = null; return }
    val now = Instant.now().epochSeconds
    val at = if (minutes > 0) ceil(now + minutes * 60.0) else {
        val end = if (!info.isBreak) now + minOf(info.slot.item.runtime, info.slot.duration) - info.position else {
            // A time-shifted break doesn't roll into `next`: when it runs out, live picks up what is on air then
            // (`watchInfo`'s caught-up rule), or the program after that if it is already in its own break.
            val handover = instantOf(now + info.slot.duration - info.position)
            var next = if (info.live) info.next else slotOnAir(info.channel, handover)
            if (!info.live && next != null && next.itemEnd <= handover) next = slotOnAir(info.channel, next.end)
            (next?.itemEnd ?: info.slot.end).epochSeconds
        }
        maxOf(ceil(now) + 1, ceil(end) - 1)
    }
    // A re-arm (a pause or Play) a moment after the one-minute toast keeps it gone: the rounding can put the new
    // deadline a fraction over the minute.
    val prev = sleep
    val warned = at - now <= AppModel.sleepWarning || (prev?.minutes == 0 && prev.warned && at - now <= AppModel.sleepWarning + 1)
    sleep = AppModel.Sleep(instantOf(at), minutes, warned = warned)
}
/** End of program follows the program on screen: its end is read again after anything that moves it against the clock
 *  (a tune, Pause or Play, a skip, the return of a program kept for Home). */
fun AppModel.followEndOfProgram() { if (sleep?.minutes == 0) setSleep(0) }
/** When the timer goes off: its whole second, except that End of program waits while its program is paused. Paused, the
 *  program's end moves on with the clock, so it reads what is left of the program, never under a second, until Play
 *  arms it again. */
fun AppModel.sleepAt(at: Instant = Instant.now()): Instant? {
    val s = sleep ?: return null
    val info = if (s.minutes == 0 && playback?.paused == true) watchInfo(at) else null
    if (info == null || info.isBreak) return s.at
    return instantOf(at.epochSeconds + max(1.0, minOf(info.slot.item.runtime, info.slot.duration) - info.position))
}
/** "Sleep in 38 min" (the banner's status line), or spoken, "38 minutes left". Minutes rounded up. */
fun AppModel.sleepText(at: Instant = Instant.now(), spoken: Boolean = false): String? {
    val due = sleepAt(at) ?: return null
    val m = maxOf(1, ceil(due.secondsSince(at) / 60).toInt())
    return if (spoken) "$m minute${if (m == 1) "" else "s"} left" else "Sleep in $m min"
}

/** Banner buttons: [Pause | Play] (not in a break), [Start over | Back to live], Program info, Audio, Subtitles,
 *  Last channel · N, Sleep · Off. Audio and Subtitles open a list of the program's tracks over the button, the one on checked. */
fun AppModel.watchActions(): List<WatchAction> {
    val info = watchInfo() ?: return emptyList()
    val ch = info.channel; val slot = info.slot
    val a = ArrayList<WatchAction>()
    if (!info.isBreak) a += WatchAction(if (playback?.paused == true) "Play" else "Pause") { togglePause() }
    if (info.live) a += WatchAction("Start over") { tune(ch.id, Playback.Mode.start, programStart = slot.start) }
    else a += WatchAction("Back to live") { tune(ch.id, Playback.Mode.live, force = true) }
    a += WatchAction("Program info") { openInfo(ProgramKey(ch.id, slot.start)) }
    for ((kind, name) in listOf(MediaTrack.Kind.audio to "Audio", MediaTrack.Kind.subtitle to "Subtitles")) {
        if (trackChoices(kind).size >= 2) a += WatchAction(name) { openTrackMenu(kind) }   // one audio track: nothing to pick
    }
    lastChannel?.let { last -> a += WatchAction("Last channel · ${last.number}") { goLast() } }
    a += WatchAction("Sleep · " + AppModel.sleepLabel(sleep?.minutes)) { cycleSleep() }
    return a
}

/** A row of the banner's Audio or Subtitles list. */
class TrackChoice(val label: String, val on: Boolean, val apply: (TrackSelection) -> TrackSelection)

/** The banner's open Audio or Subtitles list: which, and the row the remote is on. */
data class TrackMenu(val kind: MediaTrack.Kind, val focus: Int)

/** The rows of the banner's Audio or Subtitles list, the one playing marked `on`. Subtitles: Off, Forced only (only while
 *  it's the choice: the server's pick, which the list can't offer back once left), then each track. */
fun AppModel.trackChoices(kind: MediaTrack.Kind): List<TrackChoice> {
    val item = watchInfo()?.slot?.item ?: return emptyList()
    val tracks = playbackTracks.filter { it.kind == kind }
    val sel = trackSelection(playbackTracks, item.id)
    if (kind == MediaTrack.Kind.audio) {
        val on = tracks.indexOfFirst { it.id == sel.audioID }.takeIf { it >= 0 } ?: tracks.indexOfFirst { it.isDefault }.takeIf { it >= 0 } ?: 0
        return tracks.mapIndexed { i, t -> TrackChoice(AppModel.trackName(t, tracks), i == on) { it.copy(audioID = t.id) } }
    }
    if (tracks.isEmpty()) return emptyList()
    val rows = arrayListOf(TrackChoice("Off", sel.subtitle == TrackSelection.Subtitle.off) { it.copy(subtitle = TrackSelection.Subtitle.off) })
    if (sel.subtitle == TrackSelection.Subtitle.auto) rows += TrackChoice("Forced only", true) { it.copy(subtitle = TrackSelection.Subtitle.auto) }
    for (t in tracks) {
        val s = TrackSelection.Subtitle.track(t.id)
        rows += TrackChoice(AppModel.trackName(t, tracks), sel.subtitle == s) { it.copy(subtitle = s) }
    }
    return rows
}

/** The banner's Audio or Subtitles button: its list opens on the choice that's on, and holds the banner up. */
fun AppModel.openTrackMenu(kind: MediaTrack.Kind) {
    cancelTimer("banner")
    trackMenu = TrackMenu(kind, trackChoices(kind).indexOfFirst { it.on }.coerceAtLeast(0))
}

/** Up / Down move through the list (a drag too), OK plays the choice (a reload, unless it's the one on), Back puts the
 *  list away. Left / Right do nothing while it's open. */
fun AppModel.pressTrackMenu(cmd: RemoteCommand) {
    val m = trackMenu ?: return
    val c = trackChoices(m.kind)
    when (cmd) {
        RemoteCommand.up, RemoteCommand.down ->
            trackMenu = m.copy(focus = (m.focus + if (cmd == RemoteCommand.down) 1 else -1).coerceIn(0, maxOf(0, c.size - 1)))
        RemoteCommand.select -> {
            trackMenu = null; bannerLater()
            c.getOrNull(m.focus)?.takeIf { !it.on }?.let { setTracks(change = it.apply) }
        }
        RemoteCommand.back -> { trackMenu = null; bannerLater() }
        else -> {}
    }
}

/** "English"; the server's own title ("Commentary", "English (AC3 5.1)") when the language is unknown or shared by another track. */
fun AppModel.Companion.trackName(t: MediaTrack, among: List<MediaTrack>): String {
    val lang = MediaTrack.languageName(t.language)
    val shared = among.count { it.language == t.language } > 1
    return if ((lang == null || shared) && t.title.isNotEmpty()) t.title else lang ?: "Track ${t.id}"
}

/** Per-program override from the banner: the player reloads at the current position with the new tracks.
 *  The override holds for that program only (`itemID`, default the one on now). */
private fun AppModel.setTracks(itemID: String? = null, change: (TrackSelection) -> TrackSelection) {
    val pb = playback ?: return
    val id = itemID ?: watchInfo()?.slot?.item?.id ?: return
    playback = pb.copy(tracks = Playback.TrackOverride(id, change(trackSelection(playbackTracks, id)))); tunes += 1
}

/** Program `itemID`, asked for with a subtitle, didn't start: reload it at the same position with subtitles off. */
fun AppModel.dropSubtitles(itemID: String) {
    setTracks(itemID) { it.copy(subtitle = TrackSelection.Subtitle.off) }
    toast("Couldn’t show subtitles for this one.")
}

/** The prototype's onTick: a started-over program that has caught up (`watchInfo`) goes back to live. Also marks a
 *  program started from its beginning watched on the server once it has played to 90%. */
fun AppModel.watchTick(at: Instant = Instant.now()) {
    var pb = playback ?: return
    if (screen != Screen.watch) return
    val info = watchInfo(at) ?: return
    // The sleep timer, before the caught-up rule below so nothing overwrites its pause in the same tick. Behind the Home
    // screen this tick keeps running (the produceState loop outlives onStop): the deadline waits for the return from
    // Home. Only from Home: in picture in picture the activity stays started, so the deadline fires and pauses there.
    val s = sleep
    if (s != null && !backgrounded) {
        val due = sleepAt(at) ?: s.at
        val left = due.secondsSince(at)
        if (left > 0) {
            if (left <= AppModel.sleepWarning && !s.warned) { s.warned = true; toast("Sleep timer. One minute left.") }
        } else if (SpotOnAir.started == null) {   // a spot on screen plays out first; the next tick after it stops
            sleep = null   // first, so no tick fires it twice
            if (left > -AppModel.sleepWarning) {   // passed while not ticking: a minute late is still honest, later is dropped
                // Paused by hand already: the pause stands, the toast says why nothing follows. Held for a call: a plain
                // pause from here on, or the call's end would play on after the good night. Late for a started-over
                // program that is over, live on another program by now (End of program armed in its last second, a
                // tick that came late): its own break holds, not the program live has moved on to. Only for one that
                // ended with the deadline, within 2 s: ended long before, it is not what the viewer has been looking
                // at. In a break the pause is the ordinary one, and that break holds.
                val kept = pb.slot
                if (pb.paused) playback = pb.copy(held = false)
                else if (pb.mode == Playback.Mode.start && info.live && !info.isBreak && kept != null &&
                    due.secondsSince(pb.startedAt) <= minOf(kept.item.runtime, kept.duration) - pb.offset + 2)
                    playback = pb.copy(offset = pb.offset + at.secondsSince(pb.startedAt), startedAt = at, paused = true)
                else togglePause(at)
                if (overlay != null) hideBanner()   // Program info is up: the pause's banner would be stranded under it
                toast("Sleep timer. Good night.")
                return
            }
        }
    }
    // Caught up (`watchInfo`) and a program is on: live from here, joined as a tune to what is on would (a kept
    // slot left behind must not come back when the clock gets to it), before the mark below reads the playback.
    // A break is left as it is: it reads live already, a mark still owed is reported in it, and the toast comes
    // with the next program. Not behind the Home screen either, where this tick keeps running: the toast is for a
    // viewer. A kept slot with no break to speak of (a packed short started before it aired: none, or under the
    // second a tick takes to see one) is its own program again at another place under the same load key: the
    // stream is asked to move.
    if (pb.mode == Playback.Mode.start && info.live && !info.isBreak && !backgrounded) {
        if (info.slot == pb.slot && info.slot.duration - info.slot.item.runtime < 1) tunes += 1
        pb = Playback(pb.channelID, Playback.Mode.live, programStart = info.slot.start, slot = info.slot)
        playback = pb
        toast("Caught up. Back to live.")
    }
    // Only the program tuned counts, not its break (trailers, the spot) nor channel 99. Once per playback, no toast,
    // a failure only logged. No server (a plain-http link dropped while away): a later tick of this slot reports it
    // once it's back, its break too.
    // The library's own `watched` stays as it is, so the lineup doesn't change under the viewer: the Unwatched
    // channel drops the program at the next library refresh.
    val server = server
    if (pb.fromStart && info.slot == pb.slot && (!info.isBreak || pb.markDue) && !info.channel.isScrambled &&
        info.position >= 0.9 * info.slot.item.runtime) {
        if (server == null) { if (!pb.markDue) playback = pb.copy(markDue = true) }
        else {
            playback = pb.copy(fromStart = false)
            val item = info.slot.item
            scope.launch {
                try { server.markWatched(item) } catch (e: Exception) {
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    println("markWatched: $e")
                }
            }
        }
    }
}
