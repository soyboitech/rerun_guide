' Port of web/src/app/AppModelGuide.ts: the guide's remote handling and drift bookkeeping. The web drifts by the pixel
' (a frame loop); Roku drifts a row at a time, each row's slide an Animation (GuideView.brs), so the drift position is
' `m.guideTop`, the raw row at the top of the grid. Held, the focused row `m.guideRow` is drawn second from the top, as
' the web's `pos = (row - 1) * pitch`. Raw rows grow without bound and wrap through the lineup.
' ponytail: no attract mode or screensavers on Roku yet; the guide just keeps drifting.

function rowChannel(row as Integer) as Dynamic
    list = visibleChannels()
    n = list.Count()
    if n = 0 then return invalid
    return list[((row mod n) + n) mod n]
end function

' How long the first guide of a launch holds still before it drifts, so the first channels can be read.
function launchHold() as Float
    return 4
end function

sub pressGuide(cmd as String)
    if cmd = "back" then   ' drifting, Back left the app before it got here (backExitsApp)
        if m.remoteHeld then guideRelease()
        return
    end if
    if cmd = "options" then
        openOptions()
        return
    end if
    if not m.remoteHeld then
        ' Left is the drifting guide's way into Options: Back exits to Home here.
        if cmd = "left" then
            openOptions()
            return
        end if
        if guideGrab() then guideBump()
        return
    end if
    guideBump()
    if cmd = "select" then
        guideSelect()
    else if cmd = "play" then
        startFocused()
    else
        guideNav(cmd)
    end if
end sub

' Play/Pause on a cell: that program from its beginning.
sub startFocused()
    pr = programAt(guideKey())
    if pr <> invalid then tune(pr.channel.id, "start", pr.slot.start)
end sub

' The first press takes the remote: keep the focus if its cell is on screen, else focus the second row at the current time.
function guideGrab() as Boolean
    list = visibleChannels()
    n = list.Count()
    if n <= 0 then return false
    t = Time_now()
    gf = guideKey(t)
    pr = programAt(gf)
    if pr = invalid then return false
    top = m.guideTop
    if m.driftFrac > 0.5 then top = top + 1   ' mid-slide: the row more than half in view
    ws = windowStart(t)
    we = ws + windowSpan()
    r = 0
    for i = 0 to n - 1
        if list[i].id = pr.channel.id then
            r = i
            exit for
        end if
    end for
    ' The raw row of that channel nearest the grid's second row.
    v = r + n * Int((top + 1 - r) / n + 0.5)
    seen = pr.slot.start < we and pr.slot.finish > ws and v >= top and v <= top + 3
    if seen then
        m.focusTime = maxD(pr.slot.start, ws)
    else
        v = top + 1
        ch = rowChannel(v)
        k = invalid
        if ch <> invalid then k = cellAt(ch, maxD(t, ws), ws)
        q = programAt(k)
        if q <> invalid then
            gf = k
            m.focusTime = maxD(q.slot.start, ws)
        end if
    end if
    m.guideRow = v
    m.remoteHeld = true
    m.focused = gf
    return true
end function

sub guideNav(cmd as String)
    t = Time_now()
    if cmd = "up" or cmd = "down" then
        if cmd = "down" then m.guideRow = m.guideRow + 1 else m.guideRow = m.guideRow - 1
        ws = windowStart(t)
        ch = rowChannel(m.guideRow)
        if ch <> invalid then m.focused = cellAt(ch, maxD(m.focusTime, ws), ws)
        return
    end if
    if cmd <> "left" and cmd <> "right" then return
    ' Left still opens Options with nothing to focus.
    k = guideKey(t)
    pr = programAt(k)
    if pr = invalid then
        if cmd = "left" then openOptions()
        return
    end if
    ch = pr.channel
    p = pr.slot
    if cmd = "right" then q = slotOnAir(ch, p.finish) else q = slotOnAir(ch, p.start - 1)
    if q = invalid then
        if cmd = "left" then openOptions()
        return
    end if
    ' Page only as far as it takes to show the program's start (or to the first window: the on-now one brings back now).
    w = m.windowOffset
    if cmd = "right" then
        while q.start >= windowStart(t, w) + windowSpan() and w < maxWindowOffset()
            w = w + 1
        end while
    else
        while q.start < windowStart(t, w) and w > 0
            w = w - 1
        end while
    end if
    ws = windowStart(t, w)
    if q.start >= ws + windowSpan() then return
    if q.finish <= ws then
        if cmd = "left" then
            if m.windowOffset > 0 then   ' paged ahead: back to now first
                m.windowOffset = 0
                m.focusTime = maxD(p.start, windowStart(t, 0))
            else
                openOptions()
            end if
        end if
        return
    end if
    m.focusTime = maxD(q.start, ws)
    m.windowOffset = w
    m.focused = makeKey(ch, q)
end sub

sub guideSelect()
    k = guideKey()
    pr = programAt(k)
    if pr = invalid then return
    st = GuideGenerator_status(pr.slot, Time_now())
    if st = "live" or st = "break" then
        tune(pr.channel.id, "live")
    else
        openInfo(k)
    end if
end sub

' Restart the idle timer; when it fires the guide lets go and drifts again.
sub guideBump()
    later("idle", settings().idleSeconds, guideRelease)
end sub

' Let go of the remote: focus snaps to what's on now on the focused channel, the window resets, the drift resumes here.
sub guideRelease()
    cancelTimer("idle")
    if not m.remoteHeld or m.screen <> "guide" or m.overlay <> invalid then return
    guidePark()
end sub

' The guide came on screen: the first one of a launch with channels holds still a moment.
sub holdForLaunch()
    if m.launchHeld or m.channels.Count() = 0 then return
    m.launchHeld = true
    m.driftHoldUntil = UpTime(0) + launchHold()
end sub
