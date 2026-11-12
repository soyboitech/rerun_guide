' Ports of web/src/app/AppModelOverlays.ts (Options, Program info), AppModelSettings.ts (Profiles, Settings, the channel
' editor) and AppModelSearch.ts (Options > Search). Text fields open the Roku keyboard (Keyboard.brs) instead of the
' web's text-entry panel. The TV copy only: a Roku is always a TV.
' Not on Roku yet: the Theme row (Midnight Movie), New channel and Make a channel, and the Settings rows for features it
' doesn't have (attract mode, screensaver, station idents, trailers, house spots, audio and subtitle languages).

' ---- Options ----

function optionRows() as Object
    return ["profile", "guide", "movies", "tv", "favorites", "search", "channels", "settings"]
end function

function optionLabel(row as String) as String
    labels = {profile: "Switch profile", guide: "Guide", movies: "Movies", tv: "TV Shows", favorites: "Favorites",
              search: "Search", channels: "Channels", settings: "Settings"}
    return labels[row]
end function

sub pressOptions(cmd as String)
    rows = optionRows()
    if stepFocus(cmd, rows.Count()) then return
    if cmd = "back" or cmd = "right" or cmd = "options" then
        closeOverlay()
        return
    end if
    if cmd <> "select" then return
    i = m.focusIndex
    if i > rows.Count() - 1 then i = rows.Count() - 1
    row = rows[i]
    if row = "profile" then
        go("profiles")
        m.focusIndex = currentProfileIndex()
    else if row = "guide" then
        setGuideFilter("all")
    else if row = "movies" then
        setGuideFilter("movies")
    else if row = "tv" then
        setGuideFilter("tv")
    else if row = "favorites" then
        setGuideFilter("favorites")
    else if row = "search" then
        openSearch()
    else if row = "channels" then
        go("channels")
    else if row = "settings" then
        go("settings")
    end if
end sub

function currentProfileIndex() as Integer
    for i = 0 to m.persisted.profiles.Count() - 1
        if m.persisted.profiles[i].id = m.persisted.currentProfileID then return i
    end for
    return 0
end function

' ---- Program info ----

' The sheet's buttons for `key`: [{label, act, widest}] (widest: the longest the label gets, so a button sized for it
' never resizes when pressed).
function infoActions(key as Object) as Object
    pr = programAt(key)
    if pr = invalid then return []
    ch = pr.channel
    st = GuideGenerator_status(pr.slot, Time_now())
    if st = "later" then fromStart = "Watch now" else fromStart = "Start from the beginning"
    if st = "live" or st = "break" then
        acts = [{label: "Watch live", act: "live"}, {label: fromStart, act: "start"}]
    else
        acts = [{label: fromStart, act: "start"}, {label: "Watch channel " + iStr(ch.number) + " now", act: "channel"}]
    end if
    if isFavorite(ch.id) then fav = "Remove from favorites" else fav = "Add to favorites"
    acts.Push({label: fav, act: "favorite", widest: "Remove from favorites"})
    acts.Push({label: "Edit channel", act: "edit"})
    return acts
end function

sub pressInfo(cmd as String)
    o = m.overlay
    acts = infoActions(o.key)
    if stepFocus(cmd, acts.Count(), true) then return
    if cmd = "select" and acts.Count() > 0 then
        i = m.focusIndex
        if i > acts.Count() - 1 then i = acts.Count() - 1
        runInfoAction(o.key, acts[i].act)
    else if cmd = "back" then
        closeOverlay()
        if m.screen = "watch" then bannerLater()
    end if
end sub

sub runInfoAction(key as Object, act as String)
    pr = programAt(key)
    if pr = invalid then return
    ch = pr.channel
    if act = "live" then
        tune(ch.id, "live", -1, true)
    else if act = "start" then
        tune(ch.id, "start", pr.slot.start)
    else if act = "channel" then
        tune(ch.id, "live")
    else if act = "favorite" then
        fav = isFavorite(ch.id)
        setFavorite(ch.id, not fav)
        if fav then
            toast("Channel " + iStr(ch.number) + " is off your favorites.")
        else
            toast("Channel " + iStr(ch.number) + ", " + ch.name + ", is a favorite now.")
        end if
    else if act = "edit" then
        go("channels")
        m.channelSelection = ch.id
        m.channelColumn = 1
        m.channelFieldIndex = 0
    end if
end sub

' No New channel picker on Roku yet; nothing opens these.
sub pressNewChannel(cmd as String)
    if cmd = "back" then closeOverlay()
end sub

sub pressMakeChannel(cmd as String)
    if cmd = "back" then closeOverlay()
end sub

' ---- Profiles ----

' The prototype's seed colors and its "Guest" purple, for new profiles by count.
function profilePalette() as Object
    return ["#f0a33a", "#7d97ff", "#7fd39a", "#c9a0ff", "#ff8a80"]
end function

' The actions in the row Play/Pause opens under a tile: Rename, and Delete while another profile remains.
function profileActions() as Object
    if m.persisted.profiles.Count() > 1 then return ["Rename", "Delete"]
    return ["Rename"]
end function

sub pressProfiles(cmd as String)
    profiles = m.persisted.profiles
    if m.profileMenu <> invalid then
        if cmd = "left" or cmd = "right" then
            i = m.profileMenuIndex
            if cmd = "right" then i = i + 1 else i = i - 1
            if i > profileActions().Count() - 1 then i = profileActions().Count() - 1
            if i < 0 then i = 0
            m.profileMenuIndex = i
        else if cmd = "back" then
            m.profileMenu = invalid
        else if cmd = "select" then
            index = m.profileMenu
            m.profileMenu = invalid
            if m.profileMenuIndex = 0 then
                editText("profileName", profiles[index].name, index)
                return
            end if
            p = profiles[index]
            kept = []
            for j = 0 to profiles.Count() - 1
                if j <> index then kept.Push(profiles[j])
            end for
            m.persisted.profiles = kept
            if p.id = m.persisted.currentProfileID then
                switchProfile(kept[0].id)
                guideReset()
            else
                save()
            end if
            if m.focusIndex > kept.Count() then m.focusIndex = kept.Count()
            toast(p.name + " is gone.")
        end if
        return
    end if
    count = profiles.Count()
    if count < 5 then count = count + 1   ' the Add profile tile
    if stepFocus(cmd, count, true) then return
    if cmd = "back" then
        go("guide")
        return
    end if
    if cmd = "play" and m.focusIndex < profiles.Count() then
        m.profileMenu = m.focusIndex
        m.profileMenuIndex = 0
        return
    end if
    if cmd <> "select" then return
    if m.focusIndex >= profiles.Count() then
        palette = profilePalette()
        name = "Profile " + iStr(profiles.Count() + 1)
        profiles.Push(Profile_new(UCase(CreateObject("roDeviceInfo").GetRandomUUID()), name, palette[profiles.Count() mod palette.Count()]))
        save()
        editText("profileName", name, profiles.Count() - 1)   ' focusIndex already points at the new tile
        return
    end if
    p = profiles[m.focusIndex]
    ' Switching to the profile already in use would do nothing, so Select there offers Rename / Delete.
    if p.id = m.persisted.currentProfileID then
        m.profileMenu = m.focusIndex
        m.profileMenuIndex = 0
        return
    end if
    switchProfile(p.id)
    guideReset()
    go("guide")
    toast("Hi, " + p.name + ".")
end sub

' Commit a rename typed on the Profiles screen; an empty name keeps the old one.
sub commitProfileName(index as Integer, name as String)
    n = name.Trim()
    profiles = m.persisted.profiles
    if index < 0 or index >= profiles.Count() or n = "" then return
    profiles[index].name = n
    save()
end sub

' ---- Settings ----

' The Settings list: [{key (invalid for a section header), label, value, desc}].
function settingsRows() as Object
    s = settings()
    p = currentProfile()
    films = 0
    shows = newMap()
    for each it in m.library
        if it.kind = "movie" then
            films = films + 1
        else
            k = it.seriesID
            if k = invalid then k = it.seriesTitle
            if k = invalid then k = it.title
            shows[k] = true
        end if
    end for
    service = "your server"
    if m.server <> invalid then service = serverKindName(m.server.kind)
    if s.tuneMode = "live" then tuneText = "Join in progress" else tuneText = "Start from the beginning"
    if s.maxBitrateKbps = 0 then quality = "Original" else quality = iStr(s.maxBitrateKbps \ 1000) + " Mbps"
    signOutText = ""
    if m.signOutArmed then signOutText = "Press again to sign out"
    return [
        SettingsRow_head("Appearance"),
        SettingsRow("crt", "Old-TV screen lines", onOff(s.crtLines), "A faint CRT texture over the guide’s preview window. The show itself is never touched."),
        SettingsRow_head("Guide"),
        SettingsRow("auto", "Scroll listings on their own", onOff(s.autoScroll), "When nobody’s touching the remote, the guide drifts through the channels like the old preview channel."),
        SettingsRow("idle", "Start drifting again after", iStr(s.idleSeconds) + " seconds", "How long the guide waits after your last button press before it starts scrolling again."),
        SettingsRow_head("Playback"),
        SettingsRow("tune", "When you tune in", tuneText, "Join in progress keeps everyone on the same schedule. Press Play/Pause on any program to start it over either way."),
        SettingsRow("quality", "Streaming quality", quality, "Caps the stream the server sends. Lower it for remote servers or a slow connection."),
        SettingsRow_head("Profiles"),
        SettingsRow("profile", "Who’s watching", p.name, "Each profile keeps its own lineup of channels."),
        SettingsRow_head("Library"),
        SettingsRow("server", "Server", serverLabel(), "Choose which libraries feed the schedule. " + iStr(films) + " films and " + iStr(shows.Count()) + " shows on the schedule."),
        SettingsRow("rebuild", "Rebuild automatic channels", "", "Reads your library again and refreshes the automatic channels. Your edits and custom channels stay put."),
        SettingsRow("signout", "Sign out", signOutText, "Disconnects this Roku from " + service + ". Your channels are kept for when you sign back in."),
        SettingsRow_head("About"),
        SettingsRow("about", "About Rerun Guide", appVersion(), aboutText())
    ]
end function

function SettingsRow(key as String, label as String, value as String, desc as String) as Object
    return {key: key, label: label, value: value, desc: desc}
end function

function SettingsRow_head(label as String) as Object
    return {key: invalid, label: label, value: "", desc: ""}
end function

function onOff(b as Boolean) as String
    if b then return "On"
    return "Off"
end function

function appVersion() as String
    info = CreateObject("roAppInfo")
    return info.GetVersion()
end function

' Settings > About. The beacon is Soyboi's other project (soyboi.tech).
function aboutText() as String
    return "From Soyboi LLC in San Diego, makers of the beacon: a pocket counter-surveillance device that spots license-plate readers, body cams and drones. soyboi.tech" + Chr(10) + "Rerun Guide talks to your media server, Plex or Emby if you sign in with them, and Apple for the Sample station. No analytics, no tracking, and nothing about you is sent to us." + Chr(10) + "rerunguide.tv/terms · rerunguide.tv/privacy · rerunguide.tv/support"
end function

' The keys of the rows that take focus, in order.
function settingsKeys() as Object
    keys = []
    for each r in settingsRows()
        if r.key <> invalid then keys.Push(r.key)
    end for
    return keys
end function

sub pressSettings(cmd as String)
    keys = settingsKeys()
    if cmd <> "select" then m.signOutArmed = false   ' any focus move (or Back) disarms Sign out
    if stepFocus(cmd, keys.Count()) then return
    if cmd = "back" then
        go("guide")
        return
    end if
    if cmd <> "select" or m.focusIndex < 0 or m.focusIndex >= keys.Count() then return
    key = keys[m.focusIndex]
    s = settings()
    if key = "crt" then
        s.crtLines = not s.crtLines
        save()
    else if key = "auto" then
        s.autoScroll = not s.autoScroll
        save()
    else if key = "idle" then
        s.idleSeconds = nextAfter([5, 8, 15, 30], s.idleSeconds, 8)
        save()
    else if key = "tune" then
        if s.tuneMode = "live" then s.tuneMode = "start" else s.tuneMode = "live"
        save()
    else if key = "quality" then   ' 2 Mbps exists because Plex Relay caps there
        s.maxBitrateKbps = nextAfter([0, 20000, 8000, 4000, 2000], s.maxBitrateKbps, 0)
        save()
        rebuildServer()
    else if key = "profile" then
        i = currentProfileIndex()
        go("profiles")
        m.focusIndex = i
    else if key = "server" then
        m.librariesOrigin = "settings"
        go("libraries")
    else if key = "rebuild" then
        m.rebuildToast = true
        loadLibrary(true, true)
    else if key = "signout" then
        if not m.signOutArmed then
            m.signOutArmed = true
            later("signout", 5, disarmSignOut)
            return
        end if
        m.signOutArmed = false
        signOut()
    end if
end sub

sub disarmSignOut()
    m.signOutArmed = false
end sub

' The value after `v` in `list`, round again; `fallback` when v isn't in it.
function nextAfter(list as Object, v as Dynamic, fallback as Dynamic) as Dynamic
    i = indexOf(list, v)
    if i < 0 then return fallback
    return list[(i + 1) mod list.Count()]
end function

' ---- Channel editor ----

' The detail fields, in order. Not on Roku yet: Trailers between programs (breaks show the station card).
function channelFields() as Object
    return ["title", "number", "order", "tune", "show", "delete"]
end function

' Position in the editor list: i = channels[i].
function channelIndex() as Integer
    if m.channelSelection = invalid then return 0
    for i = 0 to m.channels.Count() - 1
        if m.channels[i].id = m.channelSelection then return i
    end for
    return 0
end function

function selectedChannel() as Dynamic
    return findChannel(m.channelSelection)
end function

sub pressChannels(cmd as String)
    list = m.channels
    if list.Count() = 0 then
        if cmd = "back" then go("guide")
        return
    end if
    if m.channelSelection = invalid then m.channelSelection = list[0].id
    idx = channelIndex()
    if m.channelColumn = 0 then
        if cmd = "up" or cmd = "down" then
            if cmd = "down" then j = idx + 1 else j = idx - 1
            if j > list.Count() - 1 then j = list.Count() - 1
            if j < 0 then j = 0
            m.channelSelection = list[j].id
        else if cmd = "back" then
            go("guide")
        else if cmd = "right" or cmd = "select" then
            m.channelColumn = 1
            m.channelFieldIndex = 0
        end if
        return
    end if
    fields = channelFields()
    if cmd = "up" or cmd = "down" then
        i = m.channelFieldIndex
        if cmd = "down" then i = i + 1 else i = i - 1
        if i > fields.Count() - 1 then i = fields.Count() - 1
        if i < 0 then i = 0
        m.channelFieldIndex = i
        return
    end if
    if cmd = "left" or cmd = "back" then
        m.channelColumn = 0
        return
    end if
    if cmd <> "select" then return
    ch = selectedChannel()
    if ch = invalid then return
    field = fields[m.channelFieldIndex]
    if field = "title" then
        editText("chName", ch.name, invalid)
    else if field = "number" then
        editText("chNum", iStr(ch.number), invalid)
    else if field = "order" then
        updateChannel(ch.id, {order: PlayOrder_next(ch.order)})
    else if field = "tune" then
        t = ch.definition.tuneMode
        if t = invalid then
            t = "live"
        else if t = "live" then
            t = "start"
        else
            t = invalid
        end if
        updateChannel(ch.id, {tuneMode: t})
    else if field = "show" then
        setHidden(ch.id, not isHidden(ch.id))
    else if field = "delete" then
        if ch.isCustom then
            nxt = invalid
            if idx + 1 < list.Count() then
                nxt = list[idx + 1]
            else if idx >= 1 then
                nxt = list[idx - 1]
            end if
            deleteCustomChannel(ch.id)
            m.channelColumn = 0
            m.channelSelection = invalid
            if nxt <> invalid then m.channelSelection = nxt.id
            toast("Channel " + iStr(ch.number) + " is off the air.")
        else
            resetChannel(ch.id)
            ' The automatic number may have been given to another channel meanwhile: keep the edited one then.
            auto = findChannel(ch.id)
            if auto <> invalid then
                for each c in m.channels
                    if c.number = auto.number and c.id <> ch.id then
                        updateChannel(ch.id, {number: ch.number})
                        exit for
                    end if
                end for
            end if
            back = findChannel(ch.id)
            n = ch.number
            if back <> invalid then n = back.number
            toast("Channel " + iStr(n) + " is back to automatic.")
        end if
    end if
end sub

' Validate and apply a typed channel number.
sub commitNumber(draft as String)
    ch = selectedChannel()
    if ch = invalid then return
    t = draft.Trim()
    if t = "" or not CreateObject("roRegex", "^[0-9]+$", "").IsMatch(t) or Len(t) > 4 then return
    v = Val(t)
    if v = ch.number then return
    if v < 1 or v > 999 then
        toast("Pick a number from 1 to 999.")
        return
    end if
    for each c in m.channels
        if c.number = v and c.id <> ch.id then
            toast("Channel " + iStr(v) + " is taken.")
            return
        end if
    end for
    updateChannel(ch.id, {number: v})
end sub

' The Order field's value: "Shows take turns" for Shuffle on episodes of two or more shows.
function orderLabel(ch as Object) as String
    if ch.order = "shuffle" and GuideGenerator_takesTurns(ch) then return "Shows take turns"
    return PlayOrder_rawValue(ch.order)
end function

' "Join in progress" / "From the beginning", or "Default · …" when the channel follows the app setting.
function tuneLabel(mode as Dynamic, defaultMode as String) as String
    if mode = "live" then return "Join in progress"
    if mode = "start" then return "From the beginning"
    if defaultMode = "live" then return "Default · Join in progress"
    return "Default · From the beginning"
end function

' ---- Search ----

function titleIndex() as Object
    if m.searchIndex = invalid then m.searchIndex = TitleSearch_index(concat(m.library, m.freshItems))
    return m.searchIndex
end function

function searchSelection() as Dynamic
    i = m.searchFocus - 1
    if i < 0 or i >= m.searchResults.Count() then return invalid
    return m.searchResults[i]
end function

' Options > Search: an empty page with the keyboard open.
sub openSearch()
    go("search")
    refreshAirings()
    setSearchQuery("")
    m.searchFocus = 0
    editText("search", "", invalid)
end sub

sub setSearchQuery(q as String)
    m.searchQuery = q
    m.searchResults = TitleSearch_search(q, titleIndex())
    if m.searchFocus > m.searchResults.Count() then m.searchFocus = m.searchResults.Count()
end sub

' When everything airs in the next 24 hours, across the channels this profile sees.
sub refreshAirings()
    t = Time_now()
    lineups = []
    for each c in m.channels
        if not isHidden(c.id) then lineups.Push({channel: c, slots: slotsIn(c, t, t + TitleSearch_window())})
    end for
    m.searchAirings = TitleSearch_nextAirings(lineups, titleIndex(), t)
end sub

' "Tonight 10:00 PM · Ch 5 Fright Night".
function airsText(e as Object) as String
    return TitleSearch_airsText(m.searchAirings[e.id], Time_now(), Clock_full)
end function

sub pressSearch(cmd as String)
    if cmd = "up" or cmd = "down" then
        f = m.searchFocus
        if cmd = "down" then f = f + 1 else f = f - 1
        if f > m.searchResults.Count() then f = m.searchResults.Count()
        if f < 0 then f = 0
        m.searchFocus = f
    else if cmd = "back" then
        go("guide")
    else if cmd = "select" then
        e = searchSelection()
        if e = invalid then
            editText("search", m.searchQuery, invalid)
            return
        end if
        refreshAirings()
        a = m.searchAirings[e.id]
        if a <> invalid then
            openInfo({channelID: a.channelID, start: a.start})
        else
            toast(e.title + " isn’t on in the next 24 hours.")
        end if
    end if
end sub
