' Port of web/src/app/GuideScreen.tsx (Late Show): the preview tube (top left), the info panel (top right), the time
' header and the listings grid, absolute on the 1920x1080 stage. GuideView_build makes the nodes when the guide comes on
' screen; GuideView_update refreshes them from the model after every change. The grid keeps six rows and recycles them:
' drifting, each row's slide up is an Animation, and at its end the rows shift one channel and the track jumps back.
' ponytail: Up/Down move the held grid a row at once (the web glides 0.2 s); add an Animation per press if it reads jumpy.

function GuideView_rowCount() as Integer
    return 6
end function

sub GuideView_build(parent as Object)
    t = m.t
    g = {rowSig: "", infoSig: "", previewKey: "", headerSig: ""}
    g.root = UI_group(parent)
    UI_poster(g.root, 0, 0, 1080, 748, "pkg:/images/glow.png")

    ' -- The preview tube: hue gradient, art, the muted live picture, scrim, CRT lines, corners painted over the video.
    tube = UI_group(g.root, 80, 72)
    g.tube = tube
    UI_rect(tube, -2, -2, 604, 454, t.ring, 44)
    UI_rect(tube, 0, 0, 600, 450, t.black, 44)
    g.tubeHue = UI_poster(tube, 0, 0, 600, 450, "pkg:/images/tube.png")
    g.tubeArt = UI_poster(tube, 0, 0, 600, 450, "")
    g.tubeArt.loadDisplayMode = "scaleToZoom"
    g.video = tube.CreateChild("Video")
    g.video.translation = [0, 0]
    g.video.width = 600
    g.video.height = 450
    g.video.enableUI = false
    g.video.mute = true
    g.video.visible = false
    g.video.ObserveField("state", "onPreviewState")
    g.scrim = UI_poster(tube, 0, 0, 600, 450, "pkg:/images/scrim.png")
    g.crt = UI_poster(tube, 0, 0, 600, 450, "pkg:/images/crt.png")
    g.corners = UI_poster(tube, 0, 0, 600, 450, "pkg:/images/corners.png")
    g.pvPill = UI_pill(tube, 28, 26, "LIVE", UI_body(24, 700), t.accentInk, t.accent, 14, 6)
    g.pvKicker = UI_label(tube, 36, 0, "", UI_body(24, 600), t.pvText, 528)
    g.pvTitle = UI_label(tube, 36, 0, "", UI_heading(60), t.ink, 528, "left", 2)
    g.pvSub = UI_label(tube, 36, 0, "", UI_body(26), t.pvText, 528, "left", 2)

    ' -- The info panel: 744, 64, 1096 x 470; its content sits on the bottom (the web's spacer above it).
    info = UI_group(g.root, 744, 64)
    g.info = info
    UI_rect(info, 0, 12, 14, 14, t.accent, 999)
    g.brand = UI_label(info, 26, 0, "Rerun Guide", UI_heading(30, 600), t.ink)
    g.clockAP = UI_label(info, 0, 0, "PM", UI_heading(30, 500), t.dim)
    g.clockTime = UI_label(info, 0, 0, "", UI_heading(30, 500), t.ink)
    g.profileName = UI_label(info, 0, 3, "", UI_body(26), t.mute)
    g.profileDot = UI_rect(info, 0, 0, 38, 38, t.accent, 999)
    g.profileInitial = UI_label(info, 0, 6, "", UI_body(20, 700), t.accentInk, 38, "center")
    g.chPill = UI_pill(info, 0, 0, "", UI_body(28, 700), t.accentInk, t.accent, 14, 3)
    g.chName = UI_label(info, 0, 0, "", UI_body(28, 600), t.ink)
    g.chStar = UI_poster(info, 0, 0, 22, 22, "pkg:/images/star.png", t.accent)
    g.chTag = UI_label(info, 0, 0, "", UI_body(28), t.mute)
    g.title = UI_label(info, 0, 0, "", UI_heading(92), t.ink, 1096, "left", 2)
    g.infoLine = UI_label(info, 0, 0, "", UI_body(32), t.mute, 1096)
    g.barTrack = UI_rect(info, 0, 0, 300, 6, t.line, 999)
    g.barFill = UI_rect(info, 0, 0, 6, 6, t.accent, 999)
    g.timeRange = UI_label(info, 320, 0, "", UI_body(26, 600), t.ink)
    g.status = UI_label(info, 0, 0, "", UI_body(26), t.dim)
    g.desc = UI_label(info, 0, 0, "", UI_body(29), t.mute, 1020, "left", 2)
    g.desc.lineSpacing = 6
    g.hints = []
    for each glyph in ["glyph-ok.png", "glyph-play.png", "glyph-left.png"]
        cap = UI_rect(info, 0, 0, 48, 34, t.line, 8)
        inner = UI_rect(info, 0, 0, 44, 30, t.bg, 6)
        sym = UI_poster(info, 0, 0, 30, 20, "pkg:/images/" + glyph, t.dim)
        l = UI_label(info, 0, 0, "", UI_body(26, 500), t.mute)
        g.hints.Push({cap: cap, inner: inner, sym: sym, label: l})
    end for

    ' -- The time header: three half-hour labels over the 1420-wide track, the now pill and line.
    g.header = UI_group(g.root, 420, 566)
    g.headerLabels = []
    for i = 0 to 2
        g.headerLabels.Push(UI_label(g.header, i * 1420 / 3 + 6, 4, "", UI_body(26, 600), t.dim))
    end for
    g.nowLine = UI_poster(g.root, 0, 612, 2, 428, "pkg:/images/nowline.png", t.accent)
    g.nowPill = UI_pill(g.header, 0, 0, "", UI_body(24, 700), t.accentInk, t.accent, 14, 5)

    ' -- The grid: 80, 616, 1760 x 424, clipped; the track holds the rows and slides.
    g.grid = UI_group(g.root, 80, 616)
    g.grid.clippingRect = [0, 0, 1760, 424]
    g.track = UI_group(g.grid)
    g.rows = []
    for i = 0 to GuideView_rowCount() - 1
        g.rows.Push(GuideView_makeRow(g.track, i * rowPitch()))
    end for
    UI_poster(g.grid, 0, 0, 1760, 424, "pkg:/images/fade.png")
    g.empty = UI_label(g.root, 360, 470, "", UI_body(32), t.dim, 1200, "center", 3)
    g.emptyHint = UI_label(g.root, 360, 560, "", UI_body(26), t.dim, 1200, "center", 2)

    ' The drift: one row's slide per run of the animation (GuideView_stepDone shifts the rows and starts the next).
    g.anim = g.root.CreateChild("Animation")
    g.anim.duration = rowPitch() / 22.0   ' the handoff's 22 pt/s
    g.anim.easeFunction = "linear"
    g.anim.repeat = false
    g.interp = g.anim.CreateChild("Vector2DFieldInterpolator")
    g.interp.key = [0.0, 1.0]
    g.interp.keyValue = [[0, 0], [0, -rowPitch()]]
    g.interp.fieldToInterp = "guideTrack.translation"
    g.track.id = "guideTrack"
    g.anim.ObserveField("state", "onDriftState")
    m.guide = g
    m.driftFrac = 0
    m.driftHoldUntil = 0
    holdForLaunch()
end sub

' One grid row: the channel cell and a pool of program cells.
function GuideView_makeRow(parent as Object, y as Integer) as Object
    t = m.t
    r = {cells: []}
    r.group = UI_group(parent, 0, y)
    r.number = UI_label(r.group, 0, 27, "", UI_body(26, 600), t.accent, 48, "right")
    r.name = UI_label(r.group, 66, 10, "", UI_heading(32, 600), t.ink, 272)
    r.star = UI_poster(r.group, 66, 56, 18, 18, "pkg:/images/star.png", t.accent)
    r.tag = UI_label(r.group, 66, 50, "", UI_body(24), t.dim, 272)
    r.cellLayer = UI_group(r.group, 340, 0)
    return r
end function

function GuideView_makeCell(parent as Object) as Object
    t = m.t
    c = {}
    c.group = UI_group(parent)
    c.bg = UI_rect(c.group, 0, 0, 100, 88, t.panel, 16)
    c.clip = UI_group(c.group)
    c.fill = UI_rect(c.clip, 0, 0, 100, 88, t.line, 16)
    c.title = UI_label(c.group, 24, 10, "", UI_body(30, 600), t.ink, 60)
    c.sub = UI_label(c.group, 24, 50, "", UI_body(24, 500), t.dim, 60)
    c.left = UI_poster(c.group, 16, 35, 12, 18, "pkg:/images/tri-left.png", t.dim)
    c.right = UI_poster(c.group, 0, 35, 12, 18, "pkg:/images/tri-right.png", t.dim)
    return c
end function

' The program's guide-cell sub line: "1981 · 115 min" for a film, the episode title for an episode.
function guideCellSub(it as Object) as String
    if it.kind = "movie" then
        parts = []
        if it.year <> invalid then parts.Push(iStr(it.year))
        parts.Push(iStr(Fix(it.runtime / 60)) + " min")
        return parts.Join(" · ")
    end if
    return it.title
end function

' The view model the panel, tube and hints read (the web's GuideInfo), or invalid with nothing to show.
function GuideView_info(at as Double) as Dynamic
    key = guideKey(at)
    pr = programAt(key)
    if pr = invalid then return invalid
    ch = pr.channel
    s = pr.slot
    st = GuideGenerator_status(s, at)
    cur = slotOnAir(ch, at)
    if cur = invalid then cur = s
    brk = GuideGenerator_status(cur, at) = "break"
    gi = {key: key, ch: ch, slot: s, st: st, cur: cur, brk: brk, nxt: slotOnAir(ch, cur.finish), ws: windowStart(at)}
    gi.live = st = "live" or st = "break"
    return gi
end function

sub GuideView_update()
    g = m.guide
    t = m.t
    now = Time_now()
    list = visibleChannels()
    gi = invalid
    if list.Count() > 0 then gi = GuideView_info(now)
    showing = gi <> invalid
    g.tube.visible = showing
    g.info.visible = showing
    g.header.visible = showing
    g.grid.visible = showing
    g.nowLine.visible = showing
    g.empty.visible = not showing
    g.emptyHint.visible = not showing
    if not showing then
        GuideView_stopDrift()
        GuideView_stopPreview()
        g.previewKey = ""
        if m.libraryLoading then
            g.empty.text = "Tuning in…"
            g.emptyHint.text = ""
        else if noFavorites() then
            g.empty.text = "No favorites yet"
            g.emptyHint.text = "Open any program’s info and choose Add to favorites. Press Left for Options › Guide to see every channel."
        else
            if m.libraryError <> invalid then g.empty.text = m.libraryError else g.empty.text = "Nothing to schedule yet"
            g.emptyHint.text = "Open Options › Settings › Rebuild to try again"
        end if
        return
    end if
    GuideView_preview(gi, now)
    GuideView_panel(gi, now)
    GuideView_header(gi, now)
    GuideView_rows(gi, now)
    GuideView_drift()
end sub

' ---- The preview tube ----

sub GuideView_preview(gi as Object, now as Double)
    g = m.guide
    t = m.t
    ch = gi.ch
    g.tubeHue.blendColor = UI_channelColor(ChannelDefinition_hue(ch.definition), 0.5, 0.1)
    art = ""
    if not gi.brk and not ch.isScrambled then art = backdropURL(gi.cur.item)
    if g.tubeArt.uri <> art then g.tubeArt.uri = art
    g.crt.visible = settings().crtLines
    g.scrim.visible = art <> "" or g.video.visible
    if gi.brk then
        UI_repill(g.pvPill, "BREAK", 14, 6)
        UI_tint(g.pvPill.box, t.focusBg)
        kicker = "STATION BREAK"
        title = ch.name
        sub_ = "Channel " + iStr(ch.number)
        if gi.nxt <> invalid then sub_ = sub_ + " · " + MediaItem_displayTitle(gi.nxt.item) + " at " + Clock_time(gi.nxt.start)
    else
        UI_repill(g.pvPill, "LIVE", 14, 6)
        UI_tint(g.pvPill.box, t.accent)
        kicker = "NOW PLAYING"
        title = MediaItem_displayTitle(gi.cur.item)
        if gi.cur.item.kind = "movie" then
            sub_ = ""
            if gi.cur.item.year <> invalid then sub_ = iStr(gi.cur.item.year)
        else
            sub_ = "“" + gi.cur.item.title + "”"
        end if
    end if
    g.pvKicker.text = kicker
    g.pvTitle.font = UI_heading(fitSize(Len(title), 60, 50, 40))
    g.pvTitle.text = title
    g.pvSub.text = sub_
    ' Bottom-left, 34 from the bottom: kicker, title 8 below it, sub 8 below that.
    y = 450 - 34 - g.pvSub.boundingRect().height
    g.pvSub.translation = [36, y]
    y = y - 8 - g.pvTitle.boundingRect().height
    g.pvTitle.translation = [36, y]
    g.pvKicker.translation = [36, y - g.pvKicker.boundingRect().height]
    ' The picture: muted live video after a 1.5 s dwell (each load starts a server transcode). Not in a break or on 99.
    key = ch.id + "|" + Slot_id(gi.cur) + "|" + boolStr(gi.brk) + "|" + iStr(m.foregroundSerial)
    if key <> g.previewKey then
        g.previewKey = key
        GuideView_stopPreview()
        if not gi.brk and not ch.isScrambled then later("previewDwell", 1.5, loadPreview)
    end if
end sub

function fitSize(n as Integer, a as Integer, b as Integer, c as Integer) as Integer
    if n <= 16 then return a
    if n <= 26 then return b
    return c
end function

function boolStr(b as Boolean) as String
    if b then return "1"
    return "0"
end function

sub GuideView_stopPreview()
    g = m.guide
    if g = invalid then return
    cancelTimer("previewDwell")
    if g.video.state <> "none" and g.video.state <> "stopped" then g.video.control = "stop"
    g.video.visible = false
    m.previewLoad = invalid
end sub

sub loadPreview()
    if m.screen <> "guide" or m.guide = invalid then return
    gi = GuideView_info(Time_now())
    if gi = invalid or gi.brk or gi.ch.isScrambled then return
    ' A picture that plays by itself is autoplay: none when the viewer turned autoplay off (Roku's autoplay policy).
    if not CreateObject("roDeviceInfo").IsAutoplayEnabled() then return
    t = Time_now()
    air = slotOnAir(gi.ch, t)
    if air = invalid then return
    offset = minD(t - air.start, air.item.runtime)
    m.previewLoad = m.guide.previewKey
    playbackSource(air.item, offset, "preview", onPreviewSource, {key: m.guide.previewKey, offset: offset})
end sub

sub onPreviewSource(r as Object, ctx as Object)
    g = m.guide
    if g = invalid or m.screen <> "guide" or ctx.key <> g.previewKey or m.previewLoad <> ctx.key then return
    if not r.ok then return   ' the tube keeps its gradient or art
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
end sub

' Shown once it plays (never while it buffers), over the gradient and the art.
sub onPreviewState()
    g = m.guide
    if g = invalid then return
    if g.video.state = "playing" then startedAtOffset(g)
    g.video.visible = g.video.state = "playing" or (g.video.visible and g.video.state = "buffering")
    g.scrim.visible = g.video.visible or g.tubeArt.uri <> ""
end sub

' ---- The info panel ----

sub GuideView_panel(gi as Object, now as Double)
    g = m.guide
    t = m.t
    p = currentProfile()
    brand = "Rerun Guide"
    f = guideFilterTitle(m.persisted.guideFilter)
    if f <> invalid then brand = brand + " · " + f
    g.brand.text = brand
    ' Top right: the profile chip, then the clock.
    g.clockAP.text = Clock_ap(now)
    apW = UI_width(g.clockAP)
    g.clockAP.translation = [1096 - apW, 0]
    g.clockTime.text = Clock_time(now)
    tW = UI_width(g.clockTime)
    g.clockTime.translation = [1096 - apW - 8 - tW, 0]
    g.profileName.text = p.name
    nW = UI_width(g.profileName)
    nx = 1096 - apW - 8 - tW - 28 - nW
    g.profileName.translation = [nx, 3]
    UI_tint(g.profileDot, UI_hex(p.colorHex))
    g.profileDot.translation = [nx - 12 - 38, 0]
    g.profileInitial.text = Left(p.name, 1)
    g.profileInitial.translation = [nx - 12 - 38, 6]
    ' Bottom up from 470: hints, description, progress row, info line, title, channel line.
    s = gi.slot
    item = s.item
    if gi.live then
        selLabel = "Watch live"
    else
        selLabel = "Details"
    end if
    if gi.st = "later" then playLabel = "Watch now" else playLabel = "Start from the beginning"
    if m.remoteHeld then backLabel = "Let it drift" else backLabel = "Options"
    g.hints[2].sym.uri = "pkg:/images/glyph-left.png"
    if m.remoteHeld then g.hints[2].sym.uri = "pkg:/images/glyph-back.png"
    x = 0
    labels = [selLabel, playLabel, backLabel]
    for i = 0 to 2
        h = g.hints[i]
        h.cap.translation = [x, 436]
        h.inner.translation = [x + 2, 438]
        h.sym.translation = [x + 9, 443]
        h.label.text = labels[i]
        h.label.translation = [x + 60, 435]
        x = x + 60 + UI_width(h.label) + 30
    end for
    y = 436 - 22
    g.desc.text = ""
    if item.overview <> invalid then g.desc.text = item.overview
    dh = 0
    if g.desc.text <> "" then dh = g.desc.boundingRect().height
    y = y - dh
    g.desc.translation = [0, y]
    y = y - 16 - 34
    g.barTrack.translation = [0, y + 14]
    progress = 0
    if gi.live then
        progress = (now - s.start) / (s.finish - s.start)
        if progress > 1 then progress = 1
        if progress < 0 then progress = 0
    end if
    fw = 300 * progress
    g.barFill.visible = fw >= 6
    if fw >= 6 then UI_size(g.barFill, fw, 6, 999)
    g.barFill.translation = [0, y + 14]
    g.timeRange.text = Clock_range(s.start, s.finish)
    g.timeRange.translation = [320, y]
    g.status.text = GuideView_statusText(gi, now)
    g.status.translation = [320 + UI_width(g.timeRange) + 20, y]
    y = y - 20
    g.infoLine.text = MediaItem_infoLine(item)
    y = y - g.infoLine.boundingRect().height
    g.infoLine.translation = [0, y]
    title = MediaItem_displayTitle(item)
    g.title.font = UI_heading(fitSize(Len(title), 92, 76, 60))
    g.title.text = title
    y = y - 12 - g.title.boundingRect().height
    g.title.translation = [0, y]
    ' The channel line: number pill, name, star, tag.
    ch = gi.ch
    y = y - 12 - 42
    UI_repill(g.chPill, iStr(ch.number), 14, 3)
    g.chPill.box.translation = [0, y]
    g.chPill.label.translation = [14, y + 3]
    g.chName.text = ch.name
    g.chName.translation = [g.chPill.w + 14, y + 3]
    x = g.chPill.w + 14 + UI_width(g.chName) + 14
    g.chStar.visible = isFavorite(ch.id)
    if g.chStar.visible then
        g.chStar.translation = [x, y + 10]
        x = x + 22 + 14
    end if
    g.chTag.text = "· " + ch.tag
    g.chTag.translation = [x, y + 3]
end sub

function GuideView_statusText(gi as Object, now as Double) as String
    elapsed = now - gi.slot.start
    if gi.st = "live" then return iStr(Fix(elapsed / 60)) + " min in"
    if gi.st = "break" then return "Station break until " + Clock_time(gi.slot.finish)
    if gi.st = "later" then return Clock_startsIn(-elapsed)
    return "Aired earlier"
end function

' ---- The time header ----

sub GuideView_header(gi as Object, now as Double)
    g = m.guide
    ws = gi.ws
    live = m.windowOffset = 0
    nowX = (now - ws) / windowSpan() * 1420
    for i = 0 to 2
        l = g.headerLabels[i]
        l.text = Clock_full(ws + i * 1800)
        x = i * 1420 / 3
        ' A label the now pill would sit on fades out instead of colliding.
        nearNow = live and nowX - x >= -95 and nowX - x < 170
        if nearNow then l.opacity = 0 else l.opacity = 1
    end for
    g.nowPill.box.visible = live
    g.nowPill.label.visible = live
    g.nowLine.visible = live
    if live then
        UI_repill(g.nowPill, Clock_time(now), 14, 5)
        px = nowX - g.nowPill.w / 2
        g.nowPill.box.translation = [px, 0]
        g.nowPill.label.translation = [px + 14, 5]
        g.nowLine.translation = [420 + nowX - 1, 612]
    end if
end sub

' ---- The grid ----

' Which raw row is at the top of the grid: drifting, where the drift is; held, one above the focused row.
function GuideView_top() as Integer
    if m.remoteHeld then return m.guideRow - 1
    return m.guideTop
end function

sub GuideView_rows(gi as Object, now as Double)
    g = m.guide
    top = GuideView_top()
    focusID = ""
    if gi.key <> invalid then focusID = gi.key.channelID + "@" + iStr(gi.key.start)
    ' Redraw when the rows, the window, the focus or the lineup change, and every 10 s for the live fills.
    sig = iStr(top) + "|" + iStr(gi.ws) + "|" + focusID + "|" + iStr(m.channelsVersion) + "|" + iStr(Int(now / 10)) + "|" + boolStr(m.remoteHeld)
    if sig = g.rowSig then return
    g.rowSig = sig
    for i = 0 to GuideView_rowCount() - 1
        GuideView_drawRow(g.rows[i], rowChannel(top + i), gi, now)
    end for
end sub

sub GuideView_drawRow(r as Object, ch as Dynamic, gi as Object, now as Double)
    t = m.t
    if ch = invalid then
        r.group.visible = false
        return
    end if
    r.group.visible = true
    r.number.text = iStr(ch.number)
    r.name.text = ch.name
    fav = isFavorite(ch.id)
    r.star.visible = fav
    if fav then r.tag.translation = [90, 50] else r.tag.translation = [66, 50]
    if fav then r.tag.width = 248 else r.tag.width = 272
    r.tag.text = ch.tag
    ws = gi.ws
    span = windowSpan()
    we = ws + span
    trackW = 1420
    slots = slotsIn(ch, ws, we)
    while r.cells.Count() < slots.Count()
        r.cells.Push(GuideView_makeCell(r.cellLayer))
    end while
    focusedCell = invalid
    for i = 0 to r.cells.Count() - 1
        c = r.cells[i]
        if i >= slots.Count() then
            c.group.visible = false
        else
            s = slots[i]
            l = maxD(s.start, ws)
            rr = minD(s.finish, we)
            cx = (l - ws) / span * trackW
            cw = (rr - l) / span * trackW - 8
            if cw < 1 then cw = 1
            focused = gi.key <> invalid and gi.key.channelID = ch.id and gi.key.start = s.start
            st = GuideGenerator_status(s, now)
            live = st = "live" or st = "break"
            c.group.visible = true
            c.group.translation = [cx + 4, 0]
            UI_size(c.bg, cw, 88, 16)
            if focused then
                UI_tint(c.bg, t.focusBg)
            else if live then
                UI_tint(c.bg, t.liveCell)
            else
                UI_tint(c.bg, t.panel)
            end if
            fill = 0
            if live and rr > l then
                fill = (now - l) / (rr - l)
                if fill > 1 then fill = 1
                if fill < 0 then fill = 0
            end if
            c.clip.visible = fill > 0
            c.clip.clippingRect = [0, 0, cw * fill, 88]
            UI_size(c.fill, cw, 88, 16)
            if focused then UI_tint(c.fill, t.focusFill) else UI_tint(c.fill, t.line)
            contL = s.start < ws
            contR = s.finish > we
            padL = 24
            if contL then padL = 44
            padR = 24
            if contR then padR = 44
            tw = cw - padL - padR
            if tw < 1 then tw = 1
            c.title.text = MediaItem_displayTitle(s.item)
            c.title.translation = [padL, 9]
            c.title.width = tw
            c.sub.text = guideCellSub(s.item)
            c.sub.translation = [padL, 49]
            c.sub.width = tw
            if focused then
                c.title.color = t.focusInk
                c.sub.color = t.focusDim
                UI_tint(c.left, t.focusDim)
                UI_tint(c.right, t.focusDim)
            else
                c.title.color = t.ink
                c.sub.color = t.dim
                UI_tint(c.left, t.dim)
                UI_tint(c.right, t.dim)
            end if
            c.left.visible = contL
            c.right.visible = contR
            c.right.translation = [cw - 28, 35]
            c.group.scaleRotateCenter = [cw / 2, 44]
            if focused then
                c.group.scale = [1.04, 1.04]
                focusedCell = c
            else
                c.group.scale = [1, 1]
            end if
        end if
    end for
    ' The focused cell over its neighbors (its 4% lift reaches into them).
    if focusedCell <> invalid then r.cellLayer.AppendChild(focusedCell.group)
end sub

' ---- The drift ----

' Drifting (not held, auto-scroll on, nothing over the guide): slide a row at a time. Otherwise stand still.
sub GuideView_drift()
    g = m.guide
    drifting = not m.remoteHeld and settings().autoScroll and m.overlay = invalid and m.screen = "guide" and visibleChannels().Count() > 0
    if not drifting then
        GuideView_stopDrift()
        return
    end if
    if g.anim.state = "running" then return
    wait = m.driftHoldUntil - UpTime(0)
    if wait > 0 then
        later("driftHold", wait, startDriftStep)
        return
    end if
    startDriftStep()
end sub

sub startDriftStep()
    g = m.guide
    if g = invalid or m.remoteHeld or m.screen <> "guide" or m.overlay <> invalid then return
    if g.anim.state = "running" then return
    g.track.translation = [0, 0]
    m.driftStarted = UpTime(0)
    g.anim.control = "start"
end sub

sub GuideView_stopDrift()
    g = m.guide
    cancelTimer("driftHold")
    if g.anim.state = "running" then
        m.driftFrac = (UpTime(0) - m.driftStarted) / g.anim.duration
        m.stoppingDrift = true
        g.anim.control = "stop"
    end if
    g.track.translation = [0, 0]
end sub

' A row's slide ended: the next channel moves up (rows shift, the track jumps back), and the next slide starts.
sub onDriftState()
    g = m.guide
    if g = invalid or g.anim.state <> "stopped" then return
    if m.stoppingDrift = true then
        m.stoppingDrift = false
        return
    end if
    m.driftFrac = 0
    m.guideTop = m.guideTop + 1
    g.track.translation = [0, 0]
    render()
    startDriftStep()
end sub
