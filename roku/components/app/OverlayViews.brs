' Port of web/src/app/Overlays.tsx (Late Show): the Options menu (a panel from the left), Program info (a sheet in the
' middle) and the toast (top right). An overlay's nodes are made when it opens and dropped when it closes.

' The scrim every overlay dims the stage with.
function scrimColor() as String
    return "0x0A0807B8"
end function

sub OptionsView_build(parent as Object)
    t = m.t
    g = {rows: []}
    g.root = UI_group(parent)
    UI_rect(g.root, 0, 0, 1920, 1080, scrimColor())
    UI_rect(g.root, 0, 0, 620, 1080, t.panel)
    UI_rect(g.root, 72, 85, 14, 14, t.accent, 999)
    UI_label(g.root, 100, 72, "Rerun Guide", UI_heading(32, 600), t.ink)
    y = 140
    for each row in optionRows()
        if row = "guide" then y = y + 24
        r = {name: row}
        r.bg = UI_rect(g.root, 48, y, 524, 72, t.panel, 24)
        if row = "profile" then
            r.avatar = UI_rect(g.root, 72, y + 8, 56, 56, t.accent, 999)
            r.initial = UI_label(g.root, 72, y + 18, "", UI_body(28, 700), t.accentInk, 56, "center")
            r.label = UI_label(g.root, 148, y + 4, "", UI_body(34, 600), t.ink, 400)
            r.sub = UI_label(g.root, 148, y + 44, "Switch profile", UI_body(24), t.dim)
            UI_size(r.bg, 524, 88, 24)
            y = y + 16
        else
            r.label = UI_label(g.root, 72, y + 14, optionLabel(row), UI_body(34, 600), t.ink, 476)
        end if
        g.rows.Push(r)
        y = y + 72 + 10
    end for
    g.footer = UI_label(g.root, 72, 990, "", UI_body(24), t.dim, 476)
    m.optionsView = g
end sub

sub OptionsView_update()
    g = m.optionsView
    t = m.t
    p = currentProfile()
    f = m.persisted.guideFilter
    for i = 0 to g.rows.Count() - 1
        r = g.rows[i]
        focused = i = m.focusIndex
        if focused then UI_tint(r.bg, t.focusBg) else UI_tint(r.bg, t.panel)
        ' The guide row matching the current filter is tinted, so you can see which guide you're on.
        active = (r.name = "guide" and f = "all") or (r.name = "movies" and f = "movies") or (r.name = "tv" and f = "tv") or (r.name = "favorites" and f = "favorites")
        if focused then
            r.label.color = t.focusInk
        else if active then
            r.label.color = t.accent
        else
            r.label.color = t.ink
        end if
        if r.name = "profile" then
            r.label.text = p.name
            UI_tint(r.avatar, UI_hex(p.colorHex))
            r.initial.text = Left(p.name, 1)
            if focused then r.sub.color = t.focusDim else r.sub.color = t.dim
        end if
    end for
    g.footer.text = serverLabel() + " · connected"
end sub

' ---- Program info ----

sub InfoView_build(parent as Object)
    t = m.t
    g = {pills: []}
    g.root = UI_group(parent)
    UI_rect(g.root, 0, 0, 1920, 1080, scrimColor())
    sheet = UI_group(g.root, 220, 235)
    g.sheet = sheet
    g.bg = UI_rect(sheet, 0, 0, 1480, 610, t.panel, 24)
    g.artHue = UI_poster(sheet, 56, 56, 520, 390, "pkg:/images/sheet-art.png")
    g.art = UI_poster(sheet, 56, 56, 520, 390, "")
    g.art.loadDisplayMode = "scaleToZoom"
    g.kind = UI_pill(sheet, 80, 78, "", UI_body(24, 700), t.accentInk, t.accent, 14, 6)
    g.artTitle = UI_label(sheet, 84, 0, "", UI_heading(46), t.white, 464, "left", 3)
    x = 56 + 520 + 56
    g.kicker = UI_label(sheet, x, 56, "", UI_body(26, 600), t.accent, 792)
    g.title = UI_label(sheet, x, 96, "", UI_heading(76), t.ink, 792, "left", 2)
    g.infoLine = UI_label(sheet, x, 0, "", UI_body(32), t.mute, 792)
    g.when = UI_label(sheet, x, 0, "", UI_body(28), t.dim, 792)
    g.overview = UI_label(sheet, x, 0, "", UI_body(30), t.mute, 792, "left", 4)
    g.overview.lineSpacing = 8
    m.infoView = g
end sub

sub InfoView_update()
    g = m.infoView
    t = m.t
    o = m.overlay
    pr = programAt(o.key)
    if pr = invalid then
        closeOverlay()
        return
    end if
    ch = pr.channel
    s = pr.slot
    item = s.item
    now = Time_now()
    st = GuideGenerator_status(s, now)
    if st = "live" or st = "break" then
        kind = "ON NOW"
    else if st = "later" then
        kind = "LATER"
    else
        kind = "EARLIER"
    end if
    g.artHue.blendColor = UI_channelColor(ChannelDefinition_hue(ch.definition), 0.5, 0.1)
    art = backdropURL(item)
    if g.art.uri <> art then g.art.uri = art
    UI_repill(g.kind, kind, 14, 6)
    g.artTitle.text = MediaItem_displayTitle(item)
    g.artTitle.translation = [84, 56 + 390 - 26 - g.artTitle.boundingRect().height]
    g.kicker.text = UCase("Channel " + iStr(ch.number) + " · " + ch.name)
    g.title.text = MediaItem_displayTitle(item)
    y = 96 + g.title.boundingRect().height + 14
    g.infoLine.text = MediaItem_infoLine(item)
    g.infoLine.translation = [56 + 520 + 56, y]
    y = y + g.infoLine.boundingRect().height + 14
    g.when.text = Clock_range(s.start, s.finish) + " · " + infoStatusText(s, st, now)
    g.when.translation = [56 + 520 + 56, y]
    y = y + g.when.boundingRect().height + 14
    g.overview.text = ""
    if item.overview <> invalid then g.overview.text = item.overview
    g.overview.translation = [56 + 520 + 56, y]
    ' The buttons line the bottom of the sheet, the focused one lifted: one row, a size smaller when they don't fit.
    acts = infoActions(o.key)
    sizes = [{size: 30, pad: 34, vpad: 18, gap: 18}, {size: 26, pad: 24, vpad: 21, gap: 14}, {size: 24, pad: 22, vpad: 22, gap: 12}]
    while g.pills.Count() < acts.Count()
        g.pills.Push(UI_pill(g.sheet, 0, 0, "", UI_body(30, 600), t.ink, t.panel2, 34, 18))
    end while
    pick = sizes[sizes.Count() - 1]
    for each sz in sizes
        total = 0
        for i = 0 to acts.Count() - 1
            p = g.pills[i]
            p.label.font = UI_body(sz.size, 600)
            label = acts[i].label
            if acts[i].widest <> invalid then label = acts[i].widest
            p.label.text = label
            total = total + UI_width(p.label) + sz.pad * 2 + sz.gap
        end for
        if total - sz.gap <= 1480 - 112 then
            pick = sz
            exit for
        end if
    end for
    ' Under the taller of the art and the text column.
    textBottom = y + g.overview.boundingRect().height
    rowY = 56 + 390
    if textBottom > rowY then rowY = textBottom
    rowY = rowY + 36
    x = 56
    sheetH = rowY + 56
    for i = 0 to g.pills.Count() - 1
        p = g.pills[i]
        show = i < acts.Count()
        p.box.visible = show
        p.label.visible = show
        if show then
            p.label.font = UI_body(pick.size, 600)
            label = acts[i].label
            if acts[i].widest <> invalid then label = acts[i].widest
            p.label.text = label
            w = UI_width(p.label) + pick.pad * 2
            p.label.text = acts[i].label
            r = p.label.boundingRect()
            h = r.height + pick.vpad * 2
            p.box.translation = [x, rowY]
            UI_size(p.box, w, h, 999)
            p.label.translation = [x + (w - r.width) / 2, rowY + pick.vpad]
            focused = i = m.focusIndex
            if focused then
                UI_tint(p.box, t.focusBg)
                p.label.color = t.focusInk
            else
                UI_tint(p.box, t.panel2)
                p.label.color = t.ink
            end if
            x = x + w + pick.gap
            sheetH = rowY + h + 56
        end if
    end for
    UI_size(g.bg, 1480, sheetH, 24)
    g.sheet.translation = [220, (1080 - sheetH) / 2]
end sub

function infoStatusText(s as Object, st as String, now as Double) as String
    if st = "live" then return iStr(Fix((now - s.start) / 60)) + " min in"
    if st = "break" then return "Station break until " + Clock_time(s.finish)
    if st = "later" then return Clock_startsIn(s.start - now)
    return "Aired earlier"
end function

' ---- The toast ----

sub ToastView_build(parent as Object)
    t = m.t
    g = {n: -1}
    g.root = UI_group(parent)
    g.bg = UI_rect(g.root, 0, 0, 100, 80, t.panel2, 24)
    g.label = UI_label(g.root, 0, 0, "", UI_body(28, 600), t.ink, 0, "left", 3)
    g.root.visible = false
    m.toastView = g
end sub

sub ToastView_update()
    g = m.toastView
    tst = m.currentToast
    g.root.visible = tst <> invalid
    if tst = invalid or tst.n = g.n then return
    g.n = tst.n
    g.label.width = 0
    g.label.wrap = false
    g.label.text = tst.message
    w = UI_width(g.label)
    if w > 760 then
        g.label.width = 760
        g.label.wrap = true
        w = 760
    end if
    h = g.label.boundingRect().height
    x = 1920 - 72 - (w + 60)
    g.bg.translation = [x, 56]
    UI_size(g.bg, w + 60, h + 40, 24)
    g.label.translation = [x + 30, 76]
end sub
