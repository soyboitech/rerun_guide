' Port of web/src/app/AppModelWatch.ts: watching. The banner, channel up/down, last channel, pause and time-shift, the
' 10 s skips, breaks, and the sleep timer (End of program follows pauses, skips and breaks).
' Not on Roku yet: the Audio and Subtitles pickers, the number box (Roku remotes have no digits) and the house spots.

' What the picture is showing: {channel, slot, position (seconds into the slot), live, next (what the slot rolls into)}.
function watchInfo(at = -1 as Double) as Dynamic
    if at < 0 then at = Time_now()
    pb = m.playback
    if pb = invalid then return invalid
    ch = findChannel(pb.channelID)
    if ch = invalid then
        list = visibleChannels()
        if list.Count() = 0 then return invalid
        ch = list[0]
    end if
    ' The slot tune() kept, unless its channel is gone: a library refresh reshuffles every lineup and the program must not
    ' change under the viewer. Live rolls into the current schedule once the kept slot ends.
    kept = invalid
    if ch.id = pb.channelID then kept = pb.slot
    if pb.mode = "start" then
        s = kept
        if s = invalid then s = slotStarting(ch, pb.programStart)
        if s = invalid then s = slotOnAir(ch, at)
        if s = invalid then return invalid
        posn = pb.offset
        if not pb.paused then posn = posn + at - pb.startedAt
        ' Caught up: a started-over program that has ended is live again as soon as the clock is past its end too
        ' (`watchTick` makes it the playback, and says so, once a program is on). So its break is the channel's own: it
        ' ends with the slot and the next program starts on time, however long a pause held this one. Further behind
        ' than the break is long, there is none left: it joins what is on. One started before it aired is ahead of the
        ' clock: its break runs as long as the slot's first, unless the clock gets to the program's end sooner. A pause
        ' holds everything, a break too.
        dur = s.finish - s.start
        if pb.paused or posn < minD(s.item.runtime, dur) or (at < Slot_itemEnd(s) and posn < dur) then
            return {channel: ch, slot: s, position: posn, live: false, next: slotOnAir(ch, s.finish)}
        end if
    end if
    ' On air: a kept slot that has not begun (one watched before it aired, live again since) waits its turn.
    s = invalid
    if kept <> invalid and kept.start <= at and at < kept.finish then s = kept
    if s = invalid then s = slotOnAir(ch, at)
    if s = invalid then return invalid
    return {channel: ch, slot: s, position: at - s.start, live: true, next: slotOnAir(ch, s.finish)}
end function

function WatchInfo_isBreak(info as Object) as Boolean
    return info.position >= info.slot.item.runtime
end function

' The progress bar: {elapsed: "1:02:15", ends: "Ends 9:41 PM", progress}. A break keeps the slot's clock times.
function WatchInfo_bar(info as Object, at as Double) as Object
    runtime = info.slot.item.runtime
    posn = info.position
    if WatchInfo_isBreak(info) or runtime <= 0 then
        p = posn / (info.slot.finish - info.slot.start)
        if p > 1 then p = 1
        if p < 0 then p = 0
        return {elapsed: Clock_time(info.slot.start), ends: Clock_time(info.slot.finish), progress: p}
    end if
    s = Int(posn)
    if s >= 3600 then
        elapsed = iStr(s \ 3600) + ":" + zeroPad((s \ 60) mod 60, 2) + ":" + zeroPad(s mod 60, 2)
    else
        elapsed = iStr(s \ 60) + ":" + zeroPad(s mod 60, 2)
    end if
    ends = at + runtime - posn
    p = posn / runtime
    if p < 0 then p = 0
    return {elapsed: elapsed, ends: "Ends " + Clock_full(ends), progress: p}
end function

sub pressWatch(cmd as String)
    pb = m.playback
    if pb = invalid then return
    if cmd = "options" then cmd = "select"   ' the * button: the banner's buttons, as OK
    if cmd = "up" then
        ' From the banner's buttons Up goes to its progress bar, and Down comes back; otherwise they change channels.
        if m.bannerVisible and m.bannerFocus >= 0 then
            m.barFocused = true
            bannerLater()
        else
            flip(1)
        end if
    else if cmd = "down" then
        if m.bannerVisible and m.bannerFocus >= 0 and m.barFocused then
            m.barFocused = false
            bannerLater()
        else
            flip(-1)
        end if
    else if cmd = "back" then   ' Back hides the banner first, then goes to the guide
        if m.bannerVisible then hideBanner() else toGuide(pb.channelID)
    else if cmd = "play" then
        ' In a break Play/Pause is "watch it again": pausing a break holds nothing. A break that is paused all the same
        ' (the sleep timer) goes back to live (togglePause).
        info = watchInfo()
        if not pb.paused and info <> invalid and WatchInfo_isBreak(info) then restartFromBreak() else togglePause()
    else if cmd = "left" or cmd = "right" or cmd = "select" then
        if m.bannerVisible and m.bannerFocus >= 0 and m.barFocused then   ' the progress bar: Left / Right skip, OK is Play/Pause
            if cmd = "left" then
                skip(-10)
            else if cmd = "right" then
                skip(10)
            else
                info = watchInfo()
                if info <> invalid and not WatchInfo_isBreak(info) then togglePause()
            end if
            bannerLater()
            return
        end if
        if m.bannerVisible and m.bannerFocus >= 0 then
            acts = watchActions()
            if acts.Count() = 0 then   ' no watchInfo (channels gone mid-program)
                hideBanner()
                return
            end if
            if cmd = "left" then
                if m.bannerFocus > 0 then m.bannerFocus = m.bannerFocus - 1
            else if cmd = "right" then
                if m.bannerFocus < acts.Count() - 1 then m.bannerFocus = m.bannerFocus + 1
            else
                i = m.bannerFocus
                if i > acts.Count() - 1 then i = acts.Count() - 1
                runWatchAction(acts[i].act)
            end if
            bannerLater()
            return
        end if
        info = watchInfo()
        if cmd = "select" and info <> invalid and WatchInfo_isBreak(info) and info.next <> invalid then   ' the break card's OK
            startNextFromBreak()
            return
        end if
        if cmd = "left" then
            skip(-10)
            return
        end if
        if cmd = "right" then
            skip(10)
            return
        end if
        m.bannerVisible = true
        m.bannerFocus = 0
        m.barFocused = false
        bannerLater()
    end if
end sub

' In a break, for its card: the viewer saw this program end, so it "just ended" whatever the clock says; otherwise the
' card gives the clock time it ended at. A break after a program watched behind the clock reads live (`watchInfo`), but
' its playback is still the started-over one, on this slot, until the next program (`watchTick`): that tells it from a
' break joined on the air, and from another program's break it ran into.
function justEnded(info as Object) as Boolean
    if not info.live then return true
    pb = m.playback
    if pb = invalid then return false
    if pb.mode <> "start" or pb.slot = invalid then return false
    return Slot_id(pb.slot) = Slot_id(info.slot)
end function

' In a break: the program that just ended, from its beginning (Play/Pause, or the break card).
sub restartFromBreak()
    info = watchInfo()
    if info <> invalid then tune(info.channel.id, "start", info.slot.start)
end sub

' In a break: the next program, from its beginning, without waiting for its slot (OK).
sub startNextFromBreak()
    info = watchInfo()
    if info <> invalid and info.next <> invalid then tune(info.channel.id, "start", info.next.start)
end sub

' Hide the banner 6 s from now.
sub bannerLater()
    later("banner", 6, bannerTimeout)
end sub

sub bannerTimeout()
    if m.overlay = invalid then
        m.bannerVisible = false
        m.bannerFocus = -1
    end if
end sub

sub hideBanner()
    cancelTimer("banner")
    m.bannerVisible = false
    m.bannerFocus = -1
end sub

' Channel up (+1) / down (-1) through the visible channels, wrapping.
sub flip(d as Integer)
    list = visibleChannels()
    pb = m.playback
    if list.Count() = 0 or pb = invalid then return
    n = list.Count()
    for i = 0 to n - 1
        if list[i].id = pb.channelID then
            if n > 1 then tune(list[((i + d) mod n + n) mod n].id, "live")   ' the only one: nothing to reload
            return
        end if
    end for
    ' From a channel outside the list (searched, or Last channel under the Favorites guide): the next one on the dial.
    num = 0
    ch = findChannel(pb.channelID)
    if ch <> invalid then num = ch.number
    target = invalid
    if d > 0 then
        for each c in list
            if c.number > num then
                target = c
                exit for
            end if
        end for
        if target = invalid then target = list[0]
    else
        for each c in list
            if c.number < num then target = c
        end for
        if target = invalid then target = list[n - 1]
    end if
    tune(target.id, "live")
end sub

sub goLast()
    c = lastChannel()
    if c <> invalid then tune(c.id, "live") else toast("No last channel yet. Change channels first.")
end sub

' Left / Right while watching: 10 s back or ahead per press. The player moves the picture as far inside the stream it
' has (m.seek); a stream that does not reach is loaded again from the new spot. Rewinding a live program time-shifts
' it; fast-forwarding a shifted one can catch up to live.
sub skip(seconds as Integer)
    pb = m.playback
    if pb = invalid then return
    info = watchInfo()
    if info = invalid then return
    m.bannerVisible = true
    bannerLater()
    runtime = info.slot.item.runtime
    sinceStart = Time_now() - info.slot.start
    if info.position >= runtime then return   ' a trailer break: nothing to scrub
    ' A program ahead of the clock (started before it aired) has no live point to catch up to: it stays time-shifted,
    ' also once its slot is on the air, and a skip moves it 10 s, not back to the clock.
    liveEdge = 1.0e30#
    if sinceStart > 0 and info.position < sinceStart + 1 then liveEdge = sinceStart
    target = info.position + seconds
    if runtime - 1 < target then target = runtime - 1
    if liveEdge < target then target = liveEdge
    if target < 0 then target = 0
    fromStart = pb.fromStart and pb.slot <> invalid and Slot_id(info.slot) = Slot_id(pb.slot)
    ' Paused, startedAt says how fresh the stream is (togglePause, programLoaded): a skip keeps that, and past
    ' stalePause() the player is told to ask for a new stream instead of seeking in one the server has dropped.
    fresh = Time_now()
    stale = false
    if pb.paused then
        fresh = pb.startedAt
        stale = Time_now() - pb.startedAt > stalePause()
    end if
    ' Ahead to within 5 s of live is live: every seek on the way back and forth put the clock back by as long as its
    ' picture stood still (seekLanded), and back 10 then ahead 10 means live.
    ' ponytail: 5 s covers a few seeks. Keep the sum of those corrections in the playback if a slow server leaves viewers short of live.
    near = 1
    if seconds > 0 then near = 5
    moved = target - info.position
    if target >= liveEdge - near and not pb.paused then   ' caught up, or never left live; a paused one stays paused, at the live point at most
        if info.live then return   ' not the mode: a program that has caught up reads live before the tick says so
        m.playback = Playback_new(pb.channelID, "live", info.slot.start, {slot: info.slot, fromStart: fromStart})
        moved = sinceStart - info.position
    else
        m.playback = Playback_new(pb.channelID, "start", info.slot.start, {offset: target, startedAt: fresh, paused: pb.paused, slot: info.slot, fromStart: fromStart})
    end if
    followEndOfProgram()
    if seconds < 0 then m.skipCue = -1 else m.skipCue = 1
    later("skip-cue", 1, clearSkipCue)
    m.seek = {n: m.seek.n + 1, moved: m.seek.moved + moved, stale: stale}
end sub

' A skip's seek left the picture `behind` seconds further behind the program's clock than it was (the player says so
' once it plays again): the clock ran on while the picture stood still. The clock follows the picture, by a minute at
' most and never to before the program's start. Left alone, every skip moved the two further apart, and the break cut
' that much off the program's ending. A live program stays on the clock.
sub seekLanded(behind as Double)
    pb = m.playback
    if pb = invalid or pb.mode <> "start" or pb.paused then return
    if behind > 60 then behind = 60
    if behind < -60 then behind = -60
    startedAt = pb.startedAt + behind
    if startedAt > Time_now() + pb.offset then startedAt = Time_now() + pb.offset
    pb.startedAt = startedAt
    followEndOfProgram()
end sub

sub clearSkipCue()
    m.skipCue = 0
end sub

' The stream on screen could not follow a skip (WatchView): the player loads again at the new spot, as after a tune.
sub reloadPlayer()
    m.tunes = m.tunes + 1
end sub

' Play/Pause: live becomes time-shifted and paused; paused resumes; playing pauses. `at` is the tick's own time when
' the sleep timer pauses: read a moment later, a program in its last second could be over, and the pause would land
' on what live has moved on to.
sub togglePause(at = -1 as Double)
    pb = m.playback
    if pb = invalid then return
    t = at
    if t < 0 then t = Time_now()
    info = watchInfo(t)
    if info = invalid then return
    ' A paused break (the sleep timer) held nothing: Play goes back to the clock, where the break carries on into the
    ' next program or is long over.
    if pb.mode <> "live" and pb.paused and WatchInfo_isBreak(info) then
        tune(info.channel.id, "live", -1, true)
        return
    end if
    if pb.mode <> "live" and pb.paused and t - pb.startedAt > stalePause() then m.tunes = m.tunes + 1   ' the server has likely dropped the stream
    ' `info.live`, not the mode: a started-over program that has caught up reads live before the tick says so, all
    ' through its break.
    if info.live then
        fromStart = pb.fromStart and pb.slot <> invalid and Slot_id(info.slot) = Slot_id(pb.slot)
        m.playback = Playback_new(pb.channelID, "start", info.slot.start, {offset: info.position, paused: true, slot: info.slot, fromStart: fromStart})
        m.playback.markDue = pb.markDue and fromStart   ' a mark still owed for the same slot: the paused break reports it
    else if pb.paused then
        pb.startedAt = t
        pb.paused = false
    else
        pb.offset = info.position
        pb.startedAt = t
        pb.paused = true
    end if
    followEndOfProgram()
    m.bannerVisible = true
    bannerLater()
end sub

' Play after a pause longer than this reloads the stream at that spot (Jellyfin kills an idle HLS job at 60 s).
function stalePause() as Integer
    return 60
end function

' The player loaded a stream (any reload too), or `failed`. Paused, the pause counts from here: the server holds a fresh
' stream. A failed load counts as stale, so Play tries again.
sub programLoaded(failed = false as Boolean)
    if m.playback <> invalid and m.playback.paused then
        if failed then m.playback.startedAt = 0 else m.playback.startedAt = Time_now()
    end if
end sub

' The Sleep chip's choices after Off, in minutes; 0 is End of program.
function sleepSteps() as Object
    return [0, 30, 60, 90]
end function

function sleepLabel(minutes as Dynamic) as String
    if minutes = invalid then return "Off"
    if minutes = 0 then return "End of program"
    return iStr(minutes) + " min"
end function

sub cycleSleep()
    steps = sleepSteps()
    i = -1
    if m.sleep <> invalid then i = indexOf(steps, m.sleep.minutes)
    if i + 1 < steps.Count() then setSleep(steps[i + 1]) else setSleep(invalid)
end sub

' Arm (0 = when the program on screen ends, in a break when the next one ends) or clear (invalid). A whole second, the
' tick's. End of program is the last whole second inside the program, never the break's first; a packed short ends
' with its slot.
sub setSleep(minutes as Dynamic)
    info = watchInfo()
    if minutes = invalid or info = invalid then
        m.sleep = invalid
        return
    end if
    t = Time_now()
    dur = info.slot.finish - info.slot.start
    finish = t + minD(info.slot.item.runtime, dur) - info.position
    if WatchInfo_isBreak(info) then
        ' A time-shifted break doesn't roll into `next`: when it runs out, live picks up what is on air then, or the
        ' program after that if it is already in its own break.
        handover = t + dur - info.position
        if info.live then nxt = info.next else nxt = slotOnAir(info.channel, handover)
        if not info.live and nxt <> invalid then
            if Slot_itemEnd(nxt) <= handover then nxt = slotOnAir(info.channel, nxt.finish)
        end if
        if nxt <> invalid then finish = Slot_itemEnd(nxt) else finish = info.slot.finish
    end if
    if minutes > 0 then
        at = ceil(t + minutes * 60)
    else
        at = maxD(ceil(t) + 1, ceil(finish) - 1)
    end if
    ' A re-arm (a pause or Play) a moment after the one-minute toast keeps it gone: the rounding can put the new deadline
    ' a fraction over the minute.
    prev = m.sleep
    warned = at - t <= sleepWarning()
    if not warned and prev <> invalid then
        if prev.minutes = 0 and prev.warned and at - t <= sleepWarning() + 1 then warned = true
    end if
    m.sleep = {at: at, minutes: minutes, warned: warned}
end sub

' The toast comes this long before the pause; also the grace for a deadline passed while the player wasn't ticking.
function sleepWarning() as Integer
    return 60
end function

' End of program follows the program on screen: re-read after anything that moves it against the clock.
sub followEndOfProgram()
    if m.sleep <> invalid then
        if m.sleep.minutes = 0 then setSleep(0)
    end if
end sub

' When the timer goes off: its whole second, except that End of program waits while its program is paused.
function sleepAt(at as Double) as Dynamic
    s = m.sleep
    if s = invalid then return invalid
    if s.minutes = 0 and m.playback <> invalid and m.playback.paused then
        info = watchInfo(at)
        if info <> invalid and not WatchInfo_isBreak(info) then
            rest = minD(info.slot.item.runtime, info.slot.finish - info.slot.start) - info.position
            return at + maxD(1, rest)
        end if
    end if
    return s.at
end function

' "Sleep in 38 min" (the banner's status line). Minutes rounded up.
function sleepText(at as Double) as Dynamic
    due = sleepAt(at)
    if due = invalid then return invalid
    mins = Int(ceil((due - at) / 60))
    if mins < 1 then mins = 1
    return "Sleep in " + iStr(mins) + " min"
end function

' Banner buttons: [Pause | Play] (not in a break), [Start over | Back to live], Program info, Last channel · N, Sleep · Off.
' [{label, act}], run by runWatchAction.
function watchActions() as Object
    info = watchInfo()
    if info = invalid then return []
    a = []
    if not WatchInfo_isBreak(info) then
        if m.playback <> invalid and m.playback.paused then a.Push({label: "Play", act: "pause"}) else a.Push({label: "Pause", act: "pause"})
    end if
    if info.live then a.Push({label: "Start over", act: "startOver"}) else a.Push({label: "Back to live", act: "live"})
    a.Push({label: "Program info", act: "info"})
    last = lastChannel()
    if last <> invalid then a.Push({label: "Last channel · " + iStr(last.number), act: "last"})
    minutes = invalid
    if m.sleep <> invalid then minutes = m.sleep.minutes
    a.Push({label: "Sleep · " + sleepLabel(minutes), act: "sleep"})
    return a
end function

sub runWatchAction(act as String)
    info = watchInfo()
    if info = invalid then return
    if act = "pause" then
        togglePause()
    else if act = "startOver" then
        tune(info.channel.id, "start", info.slot.start)
    else if act = "live" then
        tune(info.channel.id, "live", -1, true)
    else if act = "info" then
        openInfo(makeKey(info.channel, info.slot))
    else if act = "last" then
        goLast()
    else if act = "sleep" then
        cycleSleep()
    end if
end sub

' The once-a-second tick while watching: the sleep timer, marking a program started from its beginning watched at 90%,
' and a started-over program that has caught up (`watchInfo`) going back to live.
sub watchTick(at as Double)
    pb = m.playback
    if pb = invalid or m.screen <> "watch" then return
    info = watchInfo(at)
    if info = invalid then return
    s = m.sleep
    if s <> invalid then
        due = sleepAt(at)
        if due = invalid then due = s.at
        remaining = due - at
        if remaining > 0 then
            if remaining <= sleepWarning() and not s.warned then
                s.warned = true
                toast("Sleep timer. One minute left.")
            end if
        else
            m.sleep = invalid   ' first, so no tick fires it twice
            if remaining > -sleepWarning() then   ' passed while not ticking: a minute late is still honest, later is dropped
                ' Paused by hand already: the pause stands. Late for a started-over program that is over, live on
                ' another program by now (End of program armed in its last second, or a tick after it, as this
                ' free-running tick often is): its own break holds, not the program live has moved on to. Only for one
                ' that ended with the deadline, within 2 s: ended long before, it is not what the viewer has been
                ' looking at. In a break the pause is the ordinary one, and that break holds.
                if not pb.paused then
                    own = false
                    if pb.mode = "start" and info.live and not WatchInfo_isBreak(info) and pb.slot <> invalid then
                        own = due - pb.startedAt <= minD(pb.slot.item.runtime, pb.slot.finish - pb.slot.start) - pb.offset + 2
                    end if
                    if own then
                        pb.offset = pb.offset + at - pb.startedAt
                        pb.startedAt = at
                        pb.paused = true
                    else
                        togglePause(at)
                    end if
                end if
                if m.overlay <> invalid then hideBanner()
                toast("Sleep timer. Good night.")
                return
            end if
        end if
    end if
    ' Caught up (`watchInfo`) and a program is on: live from here, joined as a tune to what is on would (a kept slot
    ' left behind must not come back when the clock gets to it), before the mark below reads the playback. A break is
    ' left as it is: it reads live already, a mark still owed is reported in it, and the toast comes with the next
    ' program. A kept slot with no break to speak of (a packed short started before it aired: none, or under the
    ' second a tick takes to see one) is its own program again at another place under the same load key: the stream
    ' is asked to move. Everywhere else the key changes by itself, and a second change here would ask for the stream
    ' twice.
    if pb.mode = "start" and info.live and not WatchInfo_isBreak(info) then
        kept = false
        if pb.slot <> invalid then kept = Slot_id(info.slot) = Slot_id(pb.slot)
        if kept and info.slot.finish - info.slot.start - info.slot.item.runtime < 1 then m.tunes = m.tunes + 1
        pb = Playback_new(pb.channelID, "live", info.slot.start, {slot: info.slot})
        m.playback = pb
        toast("Caught up. Back to live.")
    end if
    ' Only the program tuned counts, not its break nor channel 99. Once per playback; the library keeps its own flag
    ' until the next refresh, so the Unwatched channel doesn't change under the viewer.
    if pb.fromStart and pb.slot <> invalid and Slot_id(info.slot) = Slot_id(pb.slot) and (not WatchInfo_isBreak(info) or pb.markDue) and not info.channel.isScrambled and info.position >= 0.9 * info.slot.item.runtime then
        if m.server = invalid then
            pb.markDue = true
        else
            pb.fromStart = false
            markWatched(info.slot.item)
        end if
    end if
end sub
