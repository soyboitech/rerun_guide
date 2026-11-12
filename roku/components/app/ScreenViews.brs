' Ports of web/src/app/SettingsScreens.tsx (Settings, Channels, Profiles) and SearchScreen.tsx (Late Show). Lists keep a
' pool of row nodes and scroll to keep the focused row in view.

' ---- Settings ----

sub SettingsView_build(parent as Object)
    t = m.t
    g = {rows: []}
    g.root = UI_group(parent)
    UI_label(g.root, 96, 80, "Settings", UI_heading(84), t.ink)
    g.dot = UI_rect(g.root, 96, 204, 40, 40, t.accent, 999)
    g.initial = UI_label(g.root, 96, 211, "", UI_body(22, 700), t.accentInk, 40, "center")
    g.watching = UI_label(g.root, 150, 206, "", UI_body(28), t.mute, 566)
    g.label = UI_label(g.root, 96, 388, "", UI_heading(46, 600), t.ink, 620, "left", 2)
    g.desc = UI_label(g.root, 96, 460, "", UI_body(30), t.mute, 620, "left", 12)
    g.desc.lineSpacing = 6
    g.list = UI_group(g.root, 800, 88)
    g.list.clippingRect = [0, 0, 1024, 904]
    g.track = UI_group(g.list)
    m.settingsView = g
end sub

sub SettingsView_update()
    g = m.settingsView
    t = m.t
    p = currentProfile()
    UI_tint(g.dot, UI_hex(p.colorHex))
    g.initial.text = Left(p.name, 1)
    g.watching.text = "Watching as " + p.name
    rows = settingsRows()
    while g.rows.Count() < rows.Count()
        r = {}
        r.bg = UI_rect(g.track, 0, 0, 1024, 84, t.panel, 24)
        r.label = UI_label(g.track, 0, 0, "", UI_body(32, 600), t.ink, 640)
        r.value = UI_label(g.track, 0, 0, "", UI_body(30), t.dim, 420, "right")
        g.rows.Push(r)
    end while
    y = 0
    k = 0
    focusY = 0
    for i = 0 to g.rows.Count() - 1
        r = g.rows[i]
        if i >= rows.Count() then
            r.bg.visible = false
            r.label.visible = false
            r.value.visible = false
        else
            row = rows[i]
            r.label.visible = true
            if row.key = invalid then   ' a section header
                r.bg.visible = false
                r.value.visible = false
                r.label.font = UI_body(24, 700)
                r.label.color = t.dim
                r.label.text = UCase(row.label)
                r.label.translation = [28, y + 30]
                y = y + 72
            else
                focused = k = m.focusIndex
                r.bg.visible = true
                r.value.visible = true
                r.bg.translation = [0, y]
                r.label.font = UI_body(32, 600)
                r.label.text = row.label
                r.label.translation = [32, y + 22]
                r.value.text = row.value
                r.value.translation = [1024 - 32 - 420, y + 24]
                if focused then
                    UI_tint(r.bg, t.focusBg)
                    r.label.color = t.focusInk
                    r.value.color = t.focusDim
                    focusY = y
                    g.label.text = row.label
                    g.desc.text = row.desc
                else
                    UI_tint(r.bg, t.panel)
                    r.label.color = t.ink
                    r.value.color = t.dim
                end if
                y = y + 92
                k = k + 1
            end if
        end if
    end for
    ' Keep the focused row in view, a row of air above and below.
    ty = focusY - 904 / 2 + 42
    if ty > y - 904 then ty = y - 904
    if ty < 0 then ty = 0
    g.track.translation = [0, -ty]
end sub

' ---- Channels ----

sub ChannelsView_build(parent as Object)
    t = m.t
    g = {rows: [], fields: [], chips: []}
    g.root = UI_group(parent)
    UI_label(g.root, 96, 80, "Channels", UI_heading(84), t.ink)
    UI_label(g.root, 96, 186, "Drawn from your library. Rename, renumber, reorder or hide them.", UI_body(30), t.mute, 1100)
    g.count = UI_label(g.root, 1324, 157, "", UI_body(26), t.dim, 500, "right")
    g.list = UI_group(g.root, 96, 252)
    g.list.clippingRect = [0, 0, 760, 784]
    g.track = UI_group(g.list)
    d = UI_group(g.root, 920, 252)
    g.detail = d
    g.dNumber = UI_label(d, 0, 0, "", UI_heading(96), t.accent)
    g.dName = UI_label(d, 0, 18, "", UI_heading(72), t.ink, 760)
    g.dWhat = UI_label(d, 0, 176, "", UI_body(26), t.dim, 904)
    g.dNow = UI_label(d, 0, 216, "", UI_body(28), t.mute, 904)
    for i = 0 to channelFields().Count() - 1
        f = {}
        f.bg = UI_rect(d, 0, 276 + i * 84, 904, 76, t.panel, 24)
        f.label = UI_label(d, 28, 276 + i * 84 + 18, "", UI_body(30, 600), t.ink, 420)
        f.value = UI_label(d, 452, 276 + i * 84 + 20, "", UI_body(30, 500), t.dim, 424, "right")
        g.fields.Push(f)
    end for
    g.dChips = UI_group(d, 0, 124)
    m.channelsView = g
end sub

sub ChannelsView_update()
    g = m.channelsView
    t = m.t
    list = m.channels
    shown = 0
    for each c in list
        if not isHidden(c.id) then shown = shown + 1
    end for
    g.count.text = iStr(list.Count()) + " channels · " + iStr(shown) + " in the guide"
    if list.Count() = 0 then
        g.detail.visible = false
        return
    end if
    g.detail.visible = true
    if m.channelSelection = invalid then m.channelSelection = list[0].id
    idx = channelIndex()
    while g.rows.Count() < list.Count()
        r = {}
        y = g.rows.Count() * 96
        r.bg = UI_rect(g.track, 0, y, 760, 88, t.panel, 24)
        r.number = UI_label(g.track, 0, y + 24, "", UI_body(34, 700), t.accent, 64, "right")
        r.name = UI_label(g.track, 88, y + 10, "", UI_body(32, 600), t.ink, 480)
        r.tag = UI_label(g.track, 88, y + 52, "", UI_body(24), t.dim, 480)
        r.badge = UI_label(g.track, 560, y + 30, "", UI_body(24, 600), t.dim, 176, "right")
        g.rows.Push(r)
    end while
    for i = 0 to g.rows.Count() - 1
        r = g.rows[i]
        show = i < list.Count()
        r.bg.visible = show
        r.number.visible = show
        r.name.visible = show
        r.tag.visible = show
        r.badge.visible = show
        if show then
            c = list[i]
            r.number.text = iStr(c.number)
            r.name.text = c.name
            r.tag.text = c.tag
            badge = ""
            if isHidden(c.id) then
                badge = "Hidden"
            else if c.isCustom then
                badge = "Custom"
            else if m.persisted.channelEdits[c.id] <> invalid then
                badge = "Edited"
            end if
            r.badge.text = badge
            sel = i = idx
            if sel and m.channelColumn = 0 then
                UI_tint(r.bg, t.focusBg)
                r.name.color = t.focusInk
                r.tag.color = t.focusDim
                r.badge.color = t.focusDim
                r.number.color = t.focusInk
            else
                if sel then UI_tint(r.bg, t.panel2) else UI_tint(r.bg, t.panel)
                r.name.color = t.ink
                r.tag.color = t.dim
                r.badge.color = t.dim
                r.number.color = t.accent
            end if
        end if
    end for
    ty = idx * 96 - 784 / 2 + 44
    if ty > list.Count() * 96 - 784 then ty = list.Count() * 96 - 784
    if ty < 0 then ty = 0
    g.track.translation = [0, -ty]
    ' The detail column.
    ch = selectedChannel()
    if ch = invalid then return
    g.dNumber.text = iStr(ch.number)
    g.dName.translation = [UI_width(g.dNumber) + 24, 18]
    g.dName.width = 904 - UI_width(g.dNumber) - 24
    g.dName.text = ch.name
    ' The rule as chips.
    for each c in g.chips
        g.dChips.RemoveChild(c.box)
        g.dChips.RemoveChild(c.label)
    end for
    g.chips = []
    x = 0
    for each chip in ch.definition.rule
        if x < 860 then
            p = UI_pill(g.dChips, x, 0, RuleChip_label(chip), UI_body(24, 600), t.mute, t.panel2, 16, 6)
            g.chips.Push(p)
            x = x + p.w + 10
        end if
    end for
    films = 0
    for each it in ch.items
        if it.kind = "movie" then films = films + 1
    end for
    eps = ch.items.Count() - films
    what = orderLabel(ch) + " · "
    if films > 0 then what = what + iStr(films) + " films"
    if films > 0 and eps > 0 then what = what + ", "
    if eps > 0 then what = what + iStr(eps) + " episodes"
    g.dWhat.text = what
    cur = slotOnAir(ch, Time_now())
    if cur <> invalid then g.dNow.text = "On now: " + MediaItem_displayTitle(cur.item) else g.dNow.text = ""
    fields = channelFields()
    for i = 0 to fields.Count() - 1
        f = g.fields[i]
        name = fields[i]
        if name = "title" then
            f.label.text = "Name"
            f.value.text = ch.name
        else if name = "number" then
            f.label.text = "Number"
            f.value.text = iStr(ch.number)
        else if name = "order" then
            f.label.text = "Order"
            f.value.text = orderLabel(ch)
        else if name = "tune" then
            f.label.text = "When you tune in"
            f.value.text = tuneLabel(ch.definition.tuneMode, settings().tuneMode)
        else if name = "show" then
            f.label.text = "In the guide"
            if isHidden(ch.id) then f.value.text = "Hidden" else f.value.text = "Shown"
        else if name = "delete" then
            if ch.isCustom then f.label.text = "Delete channel" else f.label.text = "Reset to automatic"
            f.value.text = ""
        end if
        focused = m.channelColumn = 1 and i = m.channelFieldIndex
        if focused then
            UI_tint(f.bg, t.focusBg)
            f.label.color = t.focusInk
            f.value.color = t.focusDim
        else
            UI_tint(f.bg, t.panel)
            f.label.color = t.ink
            f.value.color = t.dim
        end if
    end for
end sub

' ---- Profiles ----

sub ProfilesView_build(parent as Object)
    t = m.t
    g = {tiles: []}
    g.root = UI_group(parent)
    UI_label(g.root, 0, 150, "Who’s watching?", UI_heading(96), t.ink, 1920, "center")
    for i = 0 to 4
        tile = {}
        tile.group = UI_group(g.root, 0, 382)
        tile.ring = UI_rect(tile.group, 7, -8, 236, 236, t.ink, 999)
        tile.circle = UI_rect(tile.group, 15, 0, 220, 220, t.accent, 999)
        tile.initial = UI_label(tile.group, 15, 46, "", UI_heading(100, 700), t.accentInk, 220, "center")
        tile.plus = UI_label(tile.group, 15, 40, "+", UI_heading(110, 600), t.ink, 220, "center")
        tile.name = UI_label(tile.group, 0, 244, "", UI_body(38, 600), t.dim, 250, "center")
        tile.sub = UI_label(tile.group, 0, 300, "", UI_body(24), t.dim, 250, "center", 2)
        g.tiles.Push(tile)
    end for
    g.menu = []
    for i = 0 to 1
        g.menu.Push(UI_pill(g.root, 0, 776, "", UI_body(24, 700), t.ink, t.panel2, 16, 8))
    end for
    g.hint = UI_label(g.root, 0, 840, "Press Play/Pause on a profile to rename or delete it.", UI_body(28), t.dim, 1920, "center")
    m.profilesView = g
end sub

sub ProfilesView_update()
    g = m.profilesView
    t = m.t
    profiles = m.persisted.profiles
    count = profiles.Count()
    if count < 5 then count = count + 1
    total = count * 250 + (count - 1) * 40
    x0 = (1920 - total) / 2
    for i = 0 to 4
        tile = g.tiles[i]
        show = i < count
        tile.group.visible = show
        if show then
            tile.group.translation = [x0 + i * 290, 382]
            focused = i = m.focusIndex and m.profileMenu = invalid
            tile.ring.visible = focused
            if i < profiles.Count() then
                p = profiles[i]
                UI_tint(tile.circle, UI_hex(p.colorHex))
                tile.initial.visible = true
                tile.plus.visible = false
                tile.initial.text = Left(p.name, 1)
                tile.name.text = p.name
                if p.id = m.persisted.currentProfileID then tile.sub.text = "Watching now" else tile.sub.text = ""
            else
                UI_tint(tile.circle, t.panel2)
                tile.initial.visible = false
                tile.plus.visible = true
                tile.name.text = "Add profile"
                tile.sub.text = ""
            end if
            if focused or (m.profileMenu <> invalid and m.profileMenu = i) then tile.name.color = t.ink else tile.name.color = t.dim
        end if
    end for
    acts = profileActions()
    for i = 0 to 1
        pill = g.menu[i]
        show = m.profileMenu <> invalid and i < acts.Count()
        pill.box.visible = show
        pill.label.visible = show
        if show then
            UI_repill(pill, acts[i], 16, 8)
            cx = x0 + m.profileMenu * 290 + 125
            w0 = g.menu[0].w
            w1 = 0
            if acts.Count() > 1 then w1 = g.menu[1].w + 12
            start = cx - (w0 + w1) / 2
            if i = 0 then px = start else px = start + w0 + 12
            pill.box.translation = [px, 776]
            pill.label.translation = [px + 16, 784]
            if i = m.profileMenuIndex then
                UI_tint(pill.box, t.focusBg)
                pill.label.color = t.focusInk
            else
                UI_tint(pill.box, t.panel2)
                pill.label.color = t.ink
            end if
        end if
    end for
end sub

' ---- Search ----

sub SearchView_build(parent as Object)
    t = m.t
    g = {rows: []}
    g.root = UI_group(parent)
    UI_label(g.root, 96, 80, "Search", UI_heading(84), t.ink)
    g.fieldBg = UI_rect(g.root, 96, 216, 1728, 96, t.panel, 24)
    g.field = UI_label(g.root, 136, 240, "", UI_body(40, 500), t.ink, 1648)
    g.note = UI_label(g.root, 96, 340, "", UI_body(28), t.dim, 1728)
    for i = 0 to 6
        r = {}
        y = 392 + i * 96
        r.bg = UI_rect(g.root, 96, y, 1728, 88, t.panel, 24)
        r.title = UI_label(g.root, 136, y + 10, "", UI_body(32, 600), t.ink, 960)
        r.sub = UI_label(g.root, 136, y + 52, "", UI_body(24), t.dim, 960)
        r.airs = UI_label(g.root, 1120, y + 28, "", UI_body(26, 500), t.mute, 664, "right")
        g.rows.Push(r)
    end for
    m.searchView = g
end sub

sub SearchView_update()
    g = m.searchView
    t = m.t
    if m.searchQuery = "" then
        g.field.text = "Type a title"
        g.field.color = t.dim
    else
        g.field.text = m.searchQuery
        g.field.color = t.ink
    end if
    if m.searchFocus = 0 then
        UI_tint(g.fieldBg, t.focusBg)
        if m.searchQuery <> "" then g.field.color = t.focusInk else g.field.color = t.focusDim
    else
        UI_tint(g.fieldBg, t.panel)
    end if
    results = m.searchResults
    if m.searchQuery = "" then
        g.note.text = "Films by title and shows by name. Press OK to type."
    else if results.Count() = 0 then
        g.note.text = "Nothing in your library matches “" + m.searchQuery + "”."
    else if results.Count() = 1 then
        g.note.text = "1 match"
    else
        g.note.text = iStr(results.Count()) + " matches"
    end if
    ' Seven rows in view around the focused result.
    first = m.searchFocus - 4
    if first > results.Count() - 7 then first = results.Count() - 7
    if first < 0 then first = 0
    for i = 0 to 6
        r = g.rows[i]
        j = first + i
        show = j < results.Count()
        r.bg.visible = show
        r.title.visible = show
        r.sub.visible = show
        r.airs.visible = show
        if show then
            e = results[j]
            r.title.text = e.title
            parts = []
            if e.year <> invalid then parts.Push(iStr(e.year))
            if e.isShow then parts.Push("TV show") else parts.Push("Film")
            r.sub.text = parts.Join(" · ")
            r.airs.text = airsText(e)
            focused = j + 1 = m.searchFocus
            if focused then
                UI_tint(r.bg, t.focusBg)
                r.title.color = t.focusInk
                r.sub.color = t.focusDim
                r.airs.color = t.focusDim
            else
                UI_tint(r.bg, t.panel)
                r.title.color = t.ink
                r.sub.color = t.dim
                if m.searchAirings[e.id] <> invalid then r.airs.color = t.accent else r.airs.color = t.dim
            end if
        end if
    end for
end sub
