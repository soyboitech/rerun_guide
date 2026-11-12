' Port of web/src/app/WatchScreen.tsx (Late Show): the full-screen player, the break's station card, the Paused and
' Buffering chips and the banner (channel, title, next, progress, then its buttons or "Tonight on"). The player reloads
' when what should play changes (the load key: channel, slot, break, and m.tunes for a Start over or a skip the stream
' could not follow); Pause and Play only pause, and a skip seeks inside the stream.
' Not on Roku yet: trailers in the breaks (the station card always shows), the station ident and sting, the VHS rewind,
' the static between channels, channel 99's scramble, subtitles drawn by the app, and the paused program's art.

sub WatchView_build(parent as Object)
    t = m.t
    ' seekSeen: the model's skips (m.seek) the picture has in it, invalid while nothing on screen follows them.
    ' seekAsked: the last press a reload was asked for. sought: where the last seek (a skip's, or the load's own start)
    ' sent the picture, kept until `position` says so again (or 2 s after the seek is over); -1 when none. seeking: that
    ' seek is still on its way. seekBegan: since when (Time_now) the model's clock has run with it on its way, 0 when not.
    ' stallSince: since when (Time_now) the picture has been up but waiting, 0 when it is not.
    g = {loadKey: "", loadedKey: "", seekAsked: 0, sought: -1, seeking: false, seekBegan: 0, stallSince: 0}
    g.root = UI_group(parent)
    UI_rect(g.root, 0, 0, 1920, 1080, t.black)
    g.hue = UI_poster(g.root, 0, 0, 1920, 1080, "pkg:/images/picture.png")
    g.art = UI_poster(g.root, 0, 0, 1920, 1080, "")
    g.art.loadDisplayMode = "scaleToZoom"
    g.video = g.root.CreateChild("Video")
    g.video.width = 1920
    g.video.height = 1080
    g.video.enableUI = false
    g.video.visible = false
    g.video.ObserveField("state", "onWatchState")
    ' The stand-in while no stream is attached.
    g.standIn = UI_group(g.root)
    g.standKicker = UI_label(g.standIn, 160, 430, "", UI_body(24, 600), "0xFFFFFFC7", 1600, "center")
    g.standTitle = UI_label(g.standIn, 360, 480, "", UI_heading(56, 600), t.white, 1200, "center", 2)
    g.standError = UI_label(g.standIn, 360, 640, "", UI_body(28), t.accent, 1200, "center", 2)
    ' The station card: what just ended and what's next, so a channel between programs doesn't look broken.
    g.station = UI_group(g.root)
    UI_rect(g.station, 0, 0, 1920, 1080, t.bg)
    g.stNumber = UI_label(g.station, 0, 150, "", UI_heading(220), t.accent, 1920, "center")
    g.stName = UI_label(g.station, 160, 420, "", UI_heading(80), t.ink, 1600, "center")
    g.stEnded = UI_label(g.station, 260, 560, "", UI_body(36), t.ink, 1400, "center")
    g.stNext = UI_label(g.station, 260, 616, "", UI_body(36), t.mute, 1400, "center")
    g.stHints = []
    for each glyph in ["glyph-ok.png", "glyph-play.png"]
        cap = UI_rect(g.station, 0, 0, 48, 34, t.line, 8)
        inner = UI_rect(g.station, 0, 0, 44, 30, t.bg, 6)
        sym = UI_poster(g.station, 0, 0, 30, 20, "pkg:/images/" + glyph, t.dim)
        l = UI_label(g.station, 0, 0, "", UI_body(26, 500), t.mute)
        g.stHints.Push({cap: cap, inner: inner, sym: sym, label: l})
    end for
    ' Paused: a chip top left.
    g.paused = UI_group(g.root, 80, 64)
    UI_rect(g.paused, 0, 0, 236, 72, "0x00000099", 24)
    UI_rect(g.paused, 28, 18, 10, 36, t.white)
    UI_rect(g.paused, 46, 18, 10, 36, t.white)
    UI_label(g.paused, 78, 15, "Paused", UI_body(32, 600), t.white)
    ' Buffering: a chip in the middle while the picture is up but waiting (the Video node's own bar is off with its UI).
    g.buffering = UI_group(g.root, 810, 504)
    UI_rect(g.buffering, 0, 0, 300, 72, "0x00000099", 24)
    UI_label(g.buffering, 0, 15, "Buffering…", UI_body(32, 600), t.white, 300, "center")
    g.buffering.visible = false
    ' The banner: 72 from the sides, 56 from the bottom.
    b = UI_group(g.root, 72, 626)
    g.banner = b
    UI_rect(b, 0, 0, 1776, 398, "0x14110FEB", 30)
    g.bPill = UI_pill(b, 44, 36, "", UI_body(28, 700), t.accentInk, t.accent, 16, 3)
    g.bName = UI_label(b, 0, 39, "", UI_body(28, 600), t.ink)
    g.bTag = UI_label(b, 0, 39, "", UI_body(28), t.mute)
    g.bTitle = UI_label(b, 44, 86, "", UI_heading(72, 700), t.ink, 1180)
    g.bSub = UI_label(b, 44, 182, "", UI_body(32), t.mute, 1180)
    g.bUpNext = UI_label(b, 1272, 108, "", UI_body(24, 600), t.dim, 460, "right")
    g.bNext = UI_label(b, 1272, 142, "", UI_body(34, 600), t.ink, 460, "right")
    g.bElapsed = UI_label(b, 44, 248, "", UI_body(26, 600), t.ink)
    g.bBarTrack = UI_rect(b, 0, 261, 100, 8, t.line, 4)
    g.bBarFill = UI_rect(b, 0, 261, 8, 8, t.accent, 4)
    g.bBarRing = UI_rect(b, 0, 255, 100, 20, "0xF3EBE040", 8)
    g.bEnds = UI_label(b, 0, 248, "", UI_body(26, 600), t.ink)
    g.bStatus = UI_label(b, 1392, 248, "", UI_body(26, 600), t.ink, 340, "right")
    g.bChips = []
    g.bTonight = UI_group(b, 44, 304)
    g.bTonightHead = UI_label(g.bTonight, 0, 19, "", UI_body(22, 600), t.dim)
    g.bTonightRows = []
    for i = 0 to 3
        row = {}
        row.bg = UI_rect(g.bTonight, 0, 0, 100, 62, t.panel2, 999)
        row.dot = UI_rect(g.bTonight, 0, 27, 8, 8, t.accent, 999)
        row.time = UI_label(g.bTonight, 0, 15, "", UI_body(24, 600), t.accent)
        row.title = UI_label(g.bTonight, 0, 13, "", UI_body(26), t.ink, 300)
        g.bTonightRows.Push(row)
    end for
    m.watch = g
end sub

sub WatchView_update()
    g = m.watch
    t = m.t
    ' A seek that ended with no change of state (the simulator's player stays "playing" through one, or "paused"):
    ' `position` at the spot says so. Before the clock is read, which this moves, and before a new seek is sent, which
    ' it must not judge.
    if g.seeking and (g.video.state = "playing" or g.video.state = "paused") and Abs(g.video.position - g.sought) < 3 then seekOver(g)
    ' Once `position` says the spot or what has played since, it takes over at once: the spot stands still, and each
    ' further press worked out from it would lose what the picture played meanwhile.
    if not g.seeking and g.sought >= 0 and g.video.position >= g.sought and g.video.position - g.sought < 3 then g.sought = -1
    now = Time_now()
    info = watchInfo(now)
    if info = invalid then
        WatchView_stop()
        g.station.visible = false
        g.banner.visible = false
        g.paused.visible = false
        g.standIn.visible = true
        g.standKicker.text = ""
        g.standTitle.text = "Nothing on right now"
        g.standError.text = ""
        return
    end if
    ch = info.channel
    item = info.slot.item
    isBreak = WatchInfo_isBreak(info)
    paused = m.playback.paused
    ' The picture behind the stream: the channel's hue, then the program's art.
    g.hue.blendColor = UI_channelColor(ChannelDefinition_hue(ch.definition), 0.5, 0.1)
    art = ""
    if not isBreak then art = backdropURL(item)
    if g.art.uri <> art then g.art.uri = art
    ' Load what should play now.
    key = ch.id + "|" + Slot_id(info.slot) + "|" + boolStr(isBreak) + "|" + iStr(m.tunes)
    if key <> g.loadKey then
        g.loadKey = key
        g.error = invalid
        WatchView_stop()
        cancelTimer("seek")   ' this load has every skip in it: a reload still owed to one would be a second
        if not isBreak and not ch.isScrambled then
            offset = info.position
            if offset < 0 then offset = 0
            if offset > item.runtime then offset = item.runtime
            playbackSource(item, offset, "watch", onWatchSource, {key: key, offset: offset, seek: m.seek})
        end if
    end if
    ' Skips (skip() in WatchModel) the picture does not have yet: it moves as far as the program did, inside the stream
    ' on screen, from where the picture is and not from the model's clock, which a slow start leaves ahead of it. Not
    ' before the first picture, nor in a stream paused so long that the server has likely dropped it: then the stream
    ' is loaded again from the new spot 0.6 s after the last such press, as every skip used to be.
    ' ponytail: not run on a Roku. `position` is trusted to say where the picture is (it is reported every half second,
    ' so the spot a seek was sent to stands in until `position` says it, 2 s after it lands at most, and for as long as
    ' a pause lasts), a seek is taken to be over at the node's next "playing" or with `position` at the spot, the
    ' clock follows only how long the picture stood still, not where the seek landed, and a seek that never lands is
    ' left to the Video node's own error. Check these on a device.
    if g.seekSeen <> invalid and m.seek.n <> g.seekSeen.n then
        reaches = false
        if g.video.visible and not m.seek.stale and g.video.duration > 0 and g.video.state <> "finished" then   ' nor in one that has played out
            at = g.video.position
            if g.sought >= 0 then at = g.sought
            at = at + m.seek.moved - g.seekSeen.moved
            if at < 0 then at = 0
            reaches = at < g.video.duration
            if reaches then
                g.seekSeen = m.seek
                g.sought = at
                g.seeking = true
                g.video.seek = at
                cancelTimer("seek")
            end if
        end if
        if not reaches and g.seekAsked <> m.seek.n then
            g.seekAsked = m.seek.n
            later("seek", 0.6, reloadPlayer)
        end if
    end if
    if g.video.content <> invalid then
        if paused and g.video.state = "playing" then g.video.control = "pause"
        if not paused and g.video.state = "paused" then g.video.control = "resume"
    end if
    if paused then
        g.seekBegan = 0
    else if g.seeking and g.seekBegan = 0 then
        g.seekBegan = Time_now()   ' not UpTime: a Float, it steps by a quarter second after a month up
    end if
    ' Buffering, once the picture has waited a second (a stall, or a seek on its way): the other ports' loader. By the
    ' Video node's own state, which ends it too, and seen at the once-a-second update, so up to a second later than that.
    if g.video.visible and not paused and g.video.state = "buffering" then
        if g.stallSince = 0 then g.stallSince = now
    else
        g.stallSince = 0
    end if
    g.buffering.visible = g.stallSince > 0 and now - g.stallSince >= 1
    ' The stand-in while no stream is attached (never over live video).
    g.standIn.visible = not g.video.visible and not isBreak
    if g.standIn.visible then
        g.standKicker.text = UCase("Playing from " + m.server.serverName)
        title = MediaItem_displayTitle(item)
        if item.kind = "movie" then
            if item.year <> invalid then title = title + " (" + iStr(item.year) + ")"
        else
            title = title + ": “" + item.title + "”"
        end if
        g.standTitle.text = title
        if g.error <> invalid then g.standError.text = g.error else g.standError.text = ""
    end if
    ' The break: the station card.
    g.station.visible = isBreak
    if isBreak then WatchView_station(info)
    g.paused.visible = paused
    g.banner.visible = m.bannerVisible
    if m.bannerVisible then WatchView_banner(info, now)
end sub

sub WatchView_stop()
    g = m.watch
    if g = invalid then return
    if g.video.content <> invalid then g.video.control = "stop"
    g.video.visible = false
    g.seekSeen = invalid   ' nothing on screen follows a skip until the next stream is attached
    g.sought = -1
    g.seeking = false
    g.seekBegan = 0
    g.stallSince = 0
    g.buffering.visible = false
end sub

sub onWatchSource(r as Object, ctx as Object)
    g = m.watch
    if g = invalid or m.screen <> "watch" or ctx.key <> g.loadKey then return
    ' A skip while the stream was being fetched: it would start where the program was before it. Once more, from where it is.
    if ctx.seek.n <> m.seek.n then
        g.loadKey = ""
        render()
        return
    end if
    g.seekSeen = ctx.seek   ' a failed one too: a later skip asks for the stream again
    if not r.ok then
        msg = "Couldn’t play this stream: " + r.error
        g.error = msg
        toast(msg)
        programLoaded(true)
        return
    end if
    if r.value.loop = true then g.seekSeen = invalid   ' the looped sample has nowhere to skip to
    c = CreateObject("roSGNode", "ContentNode")
    c.url = r.value.url
    c.streamFormat = r.value.format
    g.pendingSeek = invalid
    if not r.value.startsAtOffset then
        c.PlayStart = Int(ctx.offset)
        g.pendingSeek = ctx.offset
    end if
    g.video.content = c
    g.video.loop = r.value.loop = true
    g.video.control = "play"
    g.loadedKey = ctx.key
end sub

sub onWatchState()
    g = m.watch
    if g = invalid then return
    st = g.video.state
    if st = "playing" then
        ' The load's own start: a player that had to be sent there (startedAtOffset: `position` does not say the spot)
        ' is on its way like a skip's seek, and the spot stands in for `position` until that is over.
        start = g.pendingSeek
        sent = startedAtOffset(g)
        g.video.visible = true
        if g.seeking then seekOver(g)
        if sent then
            g.sought = start
            g.seeking = true
        end if
        if m.playback <> invalid and m.playback.paused then g.video.control = "pause"
        programLoaded(false)
    else if st = "error" then
        g.video.visible = false
        msg = "Couldn’t play this stream: " + g.video.errorMsg
        g.error = msg
        toast(msg)
        programLoaded(true)
    end if
    render()
end sub

sub WatchView_station(info as Object)
    g = m.watch
    ch = info.channel
    item = info.slot.item
    nxt = info.next
    g.stNumber.text = iStr(ch.number)
    g.stName.text = ch.name
    what = MediaItem_displayTitle(item)
    if item.kind <> "movie" then what = what + ": “" + item.title + "”"
    if justEnded(info) then
        what = what + " just ended"
    else
        what = what + " ended at " + Clock_time(info.slot.start + item.runtime)
    end if
    g.stEnded.text = what
    if nxt <> invalid then
        g.stNext.text = "Next: " + MediaItem_displayTitle(nxt.item) + " at " + Clock_time(nxt.start)
    else
        g.stNext.text = "More after this"
    end if
    labels = []
    glyphs = []
    if nxt <> invalid then
        labels.Push("Watch " + MediaItem_displayTitle(nxt.item) + " now")
        glyphs.Push("pkg:/images/glyph-ok.png")
    end if
    if m.playback <> invalid and m.playback.paused then   ' a paused break: Play goes back to live (togglePause)
        labels.Push("Play")
    else
        labels.Push("Watch " + MediaItem_displayTitle(item) + " again")
    end if
    glyphs.Push("pkg:/images/glyph-play.png")
    ' Centered: the hints in one row, 48 apart.
    widths = []
    total = 0
    for i = 0 to 1
        h = g.stHints[i]
        show = i < labels.Count()
        h.cap.visible = show
        h.inner.visible = show
        h.sym.visible = show
        h.label.visible = show
        if show then
            h.label.text = labels[i]
            h.sym.uri = glyphs[i]
            w = 60 + UI_width(h.label)
            widths.Push(w)
            total = total + w
        end if
    end for
    total = total + 48 * (widths.Count() - 1)
    x = (1920 - total) / 2
    for i = 0 to widths.Count() - 1
        h = g.stHints[i]
        h.cap.translation = [x, 714]
        h.inner.translation = [x + 2, 716]
        h.sym.translation = [x + 9, 721]
        h.label.translation = [x + 60, 713]
        x = x + widths[i] + 48
    end for
end sub

' The banner (BannerData + Late in the web).
sub WatchView_banner(info as Object, now as Double)
    g = m.watch
    t = m.t
    ch = info.channel
    s = info.slot
    item = s.item
    paused = m.playback.paused
    isBreak = WatchInfo_isBreak(info)
    UI_repill(g.bPill, iStr(ch.number), 16, 3)
    g.bName.text = ch.name
    g.bName.translation = [44 + g.bPill.w + 14, 39]
    g.bTag.text = "· " + ch.tag
    g.bTag.translation = [44 + g.bPill.w + 14 + UI_width(g.bName) + 14, 39]
    g.bTitle.text = MediaItem_displayTitle(item)
    g.bSub.text = bannerSub(item)
    nxt = info.next
    if nxt <> invalid then
        g.bUpNext.text = UCase("Up next · " + Clock_full(nxt.start))
        g.bNext.text = MediaItem_displayTitle(nxt.item)
    else
        g.bUpNext.text = "UP NEXT"
        g.bNext.text = "More after this"
    end if
    ' The progress row: elapsed, the bar, the end time, the status.
    bar = WatchInfo_bar(info, now)
    g.bElapsed.text = bar.elapsed
    g.bEnds.text = bar.ends
    behind = 0
    if not info.live and now >= s.start and now < s.finish then behind = now - s.start - info.position
    if paused then
        status = "Paused"
    else if info.live then
        if isBreak then status = "Station break · back at " + Clock_time(s.finish) else status = "Live"
    else if behind >= 60 then
        status = iStr(Int(behind / 60 + 0.5)) + " min behind live"
    else if behind >= 3 then
        status = iStr(Int(behind + 0.5)) + " s behind live"
    else
        status = "From the beginning"
    end if
    sleepNote = sleepText(now)
    if sleepNote <> invalid then status = status + " · " + sleepNote
    g.bStatus.text = status
    if not paused and info.live and not isBreak then g.bStatus.color = t.accent else g.bStatus.color = t.mute
    eW = UI_width(g.bElapsed)
    endsW = UI_width(g.bEnds)
    endsX = 1392 - 24 - endsW
    g.bEnds.translation = [endsX, 248]
    barX = 44 + eW + 24
    barW = endsX - 24 - barX
    if barW < 20 then barW = 20
    g.bBarTrack.translation = [barX, 261]
    UI_size(g.bBarTrack, barW, 8, 4)
    fw = barW * bar.progress
    if fw > barW then fw = barW
    g.bBarFill.visible = fw >= 8
    g.bBarFill.translation = [barX, 261]
    if fw >= 8 then UI_size(g.bBarFill, fw, 8, 4)
    barFocused = m.barFocused and m.bannerFocus >= 0
    g.bBarRing.visible = barFocused
    if barFocused then
        g.bBarRing.translation = [barX - 6, 255]
        UI_size(g.bBarRing, barW + 12, 20, 8)
    end if
    ' The buttons (focused) or "Tonight on".
    acts = watchActions()
    showButtons = m.bannerFocus >= 0
    g.bTonight.visible = not showButtons
    while g.bChips.Count() < acts.Count()
        g.bChips.Push(UI_pill(g.banner, 0, 304, "", UI_body(28, 600), t.ink, t.panel2, 30, 14))
    end while
    x = 44
    for i = 0 to g.bChips.Count() - 1
        c = g.bChips[i]
        show = showButtons and i < acts.Count()
        c.box.visible = show
        c.label.visible = show
        if show then
            f = i = m.bannerFocus and not barFocused
            UI_repill(c, acts[i].label, 30, 14)
            c.box.translation = [x, 304]
            c.label.translation = [x + 30, 318]
            if f then
                UI_tint(c.box, t.focusBg)
                c.label.color = t.focusInk
            else
                UI_tint(c.box, t.panel2)
                c.label.color = t.ink
            end if
            x = x + c.w + 16
        end if
    end for
    if not showButtons then WatchView_tonight(ch, s)
end sub

' "1987 · PG" for a film, "“Pilot” · S1 E1" for an episode.
function bannerSub(item as Object) as String
    parts = []
    if item.kind = "movie" then
        if item.year <> invalid then parts.Push(iStr(item.year))
        if item.contentRating <> invalid then parts.Push(item.contentRating)
    else
        parts.Push("“" + item.title + "”")
        se = MediaItem_seasonEpisode(item)
        if se <> "" then parts.Push(se)
    end if
    return parts.Join(" · ")
end function

' The lineup strip: this slot plus the next three, "9:30 PM" then "10:00" until the meridiem changes.
sub WatchView_tonight(ch as Object, s as Object)
    g = m.watch
    g.bTonightHead.text = UCase("Tonight on " + ch.name)
    x = UI_width(g.bTonightHead) + 16
    entries = [s]
    for each x2 in slotsIn(ch, s.start, s.start + 4 * 3600)
        if x2.start >= s.finish and entries.Count() < 4 then entries.Push(x2)
    end for
    prevAP = ""
    room = 1688 - x
    for i = 0 to 3
        row = g.bTonightRows[i]
        show = i < entries.Count()
        row.bg.visible = show and i = 0
        row.dot.visible = show and i = 0
        row.time.visible = show
        row.title.visible = show
        if show then
            e = entries[i]
            ap = Clock_ap(e.start)
            tm = Clock_time(e.start)
            if ap <> prevAP then tm = tm + " " + ap
            prevAP = ap
            row.time.text = tm
            row.title.text = MediaItem_displayTitle(e.item)
            pad = 0
            if i = 0 then pad = 20
            rx = x
            if i = 0 then
                row.dot.translation = [rx + pad, 27]
                rx = rx + pad + 18
            end if
            row.time.translation = [rx, 15]
            rx = rx + UI_width(row.time) + 10
            tw = UI_width(row.title)
            maxW = room / entries.Count() - (rx - x) - pad - 16
            if maxW < 80 then maxW = 80
            if tw > maxW then tw = maxW
            row.title.width = tw
            row.title.translation = [rx, 13]
            rx = rx + tw + pad
            if i = 0 then
                row.bg.translation = [x, 0]
                UI_size(row.bg, rx - x, 62, 999)
            end if
            x = rx + 16
        end if
    end for
end sub

' A seek (a skip's, or the load's own start) is over: the clock goes back by as long as the picture stood still.
sub seekOver(g as Object)
    g.seeking = false
    if g.seekBegan > 0 then seekLanded(Time_now() - g.seekBegan)
    g.seekBegan = 0
    later("sought", 2, clearSought)
end sub

' Two seconds after a seek landed: `position` says the new spot by now. Not in a pause: nothing may report it then,
' and the spot is exact for as long as the pause lasts.
sub clearSought()
    g = m.watch
    if g = invalid or g.seeking then return
    if m.playback <> invalid and m.playback.paused then
        later("sought", 2, clearSought)
        return
    end if
    g.sought = -1
end sub

' The first frame of a load that starts at an offset: a player that ignored PlayStart (some streams, the simulator) is
' sent there now; true when it was. Shared by the guide's tube and the player.
function startedAtOffset(g as Object) as Boolean
    if g.pendingSeek = invalid then return false
    sent = Abs(g.video.position - g.pendingSeek) > 5
    if sent then g.video.seek = g.pendingSeek
    g.pendingSeek = invalid
    return sent
end function
