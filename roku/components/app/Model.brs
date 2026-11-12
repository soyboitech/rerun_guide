' Port of web/src/app/AppModel.ts: the persisted types, the model's shared core and the library cache. The model is the
' scene's m (the TS `this`): screen handlers live in *Model.brs files (the web's AppModel*.ts), views in *View.brs.
' State changes are plain assignments; render() (MainScene.brs) redraws after every press, timer and server answer.

sub Model_init()
    ' navigation
    m.screen = "welcome"
    m.overlay = invalid           ' {kind: "options"} | {kind: "info", key} | {kind: "newChannel"} | {kind: "makeChannel"}
    m.focusIndex = 0
    ' server + library
    m.server = invalid            ' the client: {kind, serverName, baseURL, token, userID, ...} (Server.brs)
    m.persisted = Persisted_load()
    m.library = []
    m.movies = []
    m.librarySections = []
    m.channels = []
    m.channelByID = newMap()
    m.channelsVersion = 0
    m.foregroundSerial = 0
    m.visibleCache = invalid
    m.dayCache = newMap()
    m.autoDefinitions = []
    m.candidateCache = []
    m.libraryGen = 0
    m.freshItems = []
    m.libraryLoading = false
    m.libraryError = invalid
    ' onboarding
    m.serviceKind = "plex"
    m.address = ""
    m.username = ""
    m.password = ""
    m.linkCode = invalid
    m.linked = false
    m.authError = invalid
    m.authBusy = false
    m.foundServers = []
    m.pendingToken = invalid
    m.authSerial = 0
    m.librarySelection = newMap()
    m.builtCount = 0
    ' guide
    m.focused = invalid           ' ProgramKey {channelID, start}
    m.remoteHeld = false
    m.windowOffset = 0
    m.guideTop = 0                ' the raw row at the top of the grid while it drifts (wraps through the lineup)
    m.guideRow = 0                ' the focused raw row while the remote is held (drawn second from the top)
    m.focusTime = 0#
    m.launchHeld = false
    ' watch
    m.playback = invalid
    m.bannerVisible = false
    m.bannerFocus = -1
    m.barFocused = false
    m.skipCue = 0
    ' The skips, for the player: how many there have been and how far they moved the program in all, in seconds (a sum,
    ' so two skips between two looks at it are not one), and whether the last came after a pause so long that the
    ' server has likely dropped the stream (stalePause()). WatchView moves the picture as far inside the stream it has.
    m.seek = {n: 0, moved: 0#, stale: false}
    m.sleep = invalid             ' {at, minutes, warned}
    m.tunes = 0
    m.flips = 0
    ' channel editor
    m.channelSelection = invalid
    m.channelColumn = 0
    m.channelFieldIndex = 0
    m.numberDraft = invalid
    m.newChannelStep = 0
    m.newChannelType = invalid
    m.editingField = invalid
    ' search
    m.searchQuery = ""
    m.searchResults = []
    m.searchFocus = 0
    m.searchAirings = newMap()
    m.makePeople = invalid
    m.searchIndex = invalid
    m.currentToast = invalid
    m.toastSerial = 0
    m.signOutArmed = false
    m.librariesOrigin = invalid
    m.profileMenu = invalid
    m.profileMenuIndex = 0
end sub

' The rest of the TS constructor: open the saved link, or stay on Welcome.
sub Model_start()
    if m.persisted.serverConfig = invalid then return
    rebuildServer()
    if m.server = invalid then return
    m.screen = "guide"
    m.libraryLoading = true
    loadLibrary(true, false)
end sub

' ---- Persisted (registry section "RerunGuide": the JSON of Persisted, the token, the device id) ----

' A per-install client id (X-Plex-Client-Identifier, the MediaBrowser DeviceId).
function deviceID() as String
    if m.deviceIDValue = invalid then
        id = Store_get("deviceID")
        if id = invalid or id = "" then
            id = UCase(CreateObject("roDeviceInfo").GetRandomUUID())
            Store_set("deviceID", id)
        end if
        m.deviceIDValue = id
    end if
    return m.deviceIDValue
end function

function Settings_make() as Object
    return {crtLines: true, autoScroll: true, idleSeconds: 8, tuneMode: "live", trailerBreaks: true, maxBitrateKbps: 0,
            audioLanguage: invalid, stationIdents: true, attractMinutes: 3, subtitleMode: "forced", subtitleLanguage: invalid,
            screensaver: "wall", houseSpots: false, matchContent: false}
end function

function Profile_new(id as String, name as String, colorHex as String) as Object
    return {id: id, name: name, colorHex: colorHex, theme: "late", hidden: newMap(), favorites: newMap()}
end function

function Persisted_make() as Object
    return {profiles: [Profile_new("p1", "You", "#f0a33a")], currentProfileID: "p1", settings: Settings_make(),
            channelEdits: newMap(), customChannels: [], selectedLibraryIDs: invalid, serverConfig: invalid, lastChannelID: invalid,
            guideFilter: "all"}
end function

function setOf(a as Dynamic) as Object
    s = newMap()
    if type(a) = "roArray" then
        for each v in a
            if type(v) = "String" or type(v) = "roString" then s[v] = true
        end for
    end if
    return s
end function

function keysOf(s as Object) as Object
    out = []
    for each k in s
        out.Push(k)
    end for
    return out
end function

' Hand-written, so a build that adds a property keeps every profile, edit and the server link: missing keys keep the
' defaults. Shapes are the web's (and Android's) Persisted JSON.
function Persisted_load() as Object
    d = Persisted_make()
    s = Store_get("persisted")
    if s = invalid then return d
    o = ParseJson(s)
    if type(o) <> "roAssociativeArray" then return d
    if type(o.profiles) = "roArray" and o.profiles.Count() > 0 then
        d.profiles = []
        for each p in o.profiles
            if type(p) = "roAssociativeArray" and p.id <> invalid and p.name <> invalid then
                colorHex = p.colorHex
                if colorHex = invalid then colorHex = "#f0a33a"
                pr = Profile_new(p.id, p.name, colorHex)
                pr.hidden = setOf(p.hiddenChannelIDs)
                pr.favorites = setOf(p.favoriteChannelIDs)
                d.profiles.Push(pr)
            end if
        end for
        if d.profiles.Count() = 0 then d.profiles = Persisted_make().profiles
    end if
    if o.currentProfileID <> invalid then d.currentProfileID = o.currentProfileID
    if type(o.settings) = "roAssociativeArray" then
        for each k in d.settings
            if o.settings.DoesExist(k) and o.settings[k] <> invalid then d.settings[k] = o.settings[k]
        end for
        if d.settings.subtitleMode = "auto" then d.settings.subtitleMode = "forced"   ' earlier builds stored "auto"
    end if
    if type(o.channelEdits) = "roAssociativeArray" then
        for each id in o.channelEdits
            e = o.channelEdits[id]
            if type(e) = "roAssociativeArray" then
                tm = e.tuneMode
                if tm <> "live" and tm <> "start" then tm = invalid
                d.channelEdits[id] = {name: e.name, number: e.number, order: PlayOrder_from(e.order), tuneMode: tm, trailerBreaks: e.trailerBreaks}
            end if
        end for
    end if
    if type(o.customChannels) = "roArray" then
        for each c in o.customChannels
            if type(c) = "roAssociativeArray" then
                def = ChannelDefinition_fromJson(c)
                if def <> invalid then d.customChannels.Push(def)
            end if
        end for
    end if
    if type(o.selectedLibraryIDs) = "roArray" then d.selectedLibraryIDs = o.selectedLibraryIDs
    if type(o.serverConfig) = "roAssociativeArray" and o.serverConfig.kind <> invalid and o.serverConfig.baseURL <> invalid then d.serverConfig = o.serverConfig
    d.lastChannelID = o.lastChannelID
    if contains(["all", "movies", "tv", "favorites"], o.guideFilter) then d.guideFilter = o.guideFilter
    return d
end function

function Persisted_toJson(p as Object) as Object
    profiles = []
    for each pr in p.profiles
        profiles.Push({id: pr.id, name: pr.name, colorHex: pr.colorHex, theme: pr.theme, hiddenChannelIDs: keysOf(pr.hidden),
                       favoriteChannelIDs: keysOf(pr.favorites)})
    end for
    sj = {}
    for each k in p.settings
        if p.settings[k] <> invalid then sj[k] = p.settings[k]
    end for
    edits = {}
    for each id in p.channelEdits
        e = p.channelEdits[id]
        j = {}
        if e.name <> invalid then j.name = e.name
        if e.number <> invalid then j.number = e.number
        if e.order <> invalid then j.order = PlayOrder_rawValue(e.order)
        if e.tuneMode <> invalid then j["tuneMode"] = e.tuneMode
        if e.trailerBreaks <> invalid then j["trailerBreaks"] = e.trailerBreaks
        edits[id] = j
    end for
    custom = []
    for each d in p.customChannels
        custom.Push(ChannelDefinition_toJson(d))
    end for
    o = {profiles: profiles, currentProfileID: p.currentProfileID, settings: sj, channelEdits: edits, customChannels: custom,
         guideFilter: p.guideFilter}
    if p.selectedLibraryIDs <> invalid then o["selectedLibraryIDs"] = p.selectedLibraryIDs
    if p.serverConfig <> invalid then o["serverConfig"] = p.serverConfig
    if p.lastChannelID <> invalid then o["lastChannelID"] = p.lastChannelID
    return o
end function

sub save()
    Store_set("persisted", FormatJson(Persisted_toJson(m.persisted)))
end sub

' ---- Derived ----

function currentProfile() as Object
    for each p in m.persisted.profiles
        if p.id = m.persisted.currentProfileID then return p
    end for
    return m.persisted.profiles[0]
end function

function settings() as Object
    return m.persisted.settings
end function

function isHidden(id as String) as Boolean
    return currentProfile().hidden[id] <> invalid
end function

function isFavorite(id as String) as Boolean
    return currentProfile().favorites[id] <> invalid
end function

function findChannel(id as Dynamic) as Dynamic
    if id = invalid then return invalid
    return m.channelByID[id]
end function

' Every channel, sorted by number, hidden ones included. Setting it drops the lineup days and the visible list.
sub setChannels(list as Object)
    m.channels = list
    m.channelsVersion = m.channelsVersion + 1
    m.channelByID = newMap()
    for each c in list
        m.channelByID[c.id] = c
    end for
    m.dayCache = newMap()
    m.visibleCache = invalid
end sub

' Channels in the lineup: not hidden for this profile, and in the current guide (All / Movies / TV Shows / Favorites).
function visibleChannels() as Object
    if m.visibleCache <> invalid then return m.visibleCache
    p = currentProfile()
    f = m.persisted.guideFilter
    out = []
    for each c in m.channels
        if p.hidden[c.id] = invalid then
            if f = "all" then
                out.Push(c)
            else if f = "movies" then
                if c.isMovies then out.Push(c)
            else if f = "tv" then
                if not c.isMovies then out.Push(c)
            else if p.favorites[c.id] <> invalid then
                out.Push(c)
            end if
        end if
    end for
    m.visibleCache = out
    return out
end function

' The guide's title after "Rerun Guide · ": invalid for every channel.
function guideFilterTitle(f as String) as Dynamic
    if f = "movies" then return "Movies"
    if f = "tv" then return "TV Shows"
    if f = "favorites" then return "Favorites"
    return invalid
end function

' The Favorites guide with nothing starred: the guide's empty state says how to add one.
function noFavorites() as Boolean
    return m.persisted.guideFilter = "favorites" and m.channels.Count() > 0 and visibleChannels().Count() = 0
end function

' Switch guides (Options > Guide / Movies / TV Shows / Favorites): the drift starts over from the top of the new lineup.
sub setGuideFilter(f as String)
    m.persisted.guideFilter = f
    save()
    m.visibleCache = invalid
    guideReset()
    m.overlay = invalid
    m.focusIndex = 0
    if m.screen <> "guide" then go("guide")
end sub

sub setLibrary(items as Object)
    m.library = items
    m.movies = []
    for each it in items
        if it.kind = "movie" then m.movies.Push(it)
    end for
    m.searchIndex = invalid
end sub

' Guide row pitch and viewport (Late Show).
function rowPitch() as Integer
    return 100
end function

function gridHeight() as Integer
    return 424
end function

function windowSpan() as Integer
    return 90 * 60
end function

' How many 30-min pages Right can move the window ahead: the last one ends 24 hours past the current half hour.
function maxWindowOffset() as Integer
    return 45
end function

' Guide window start: now floored to the half hour, plus `offset` pages (-1: the current offset).
function windowStart(at as Double, offset = -1 as Integer) as Double
    if offset < 0 then offset = m.windowOffset
    return Int(at / 1800) * 1800# + offset * 1800#
end function

' One channel's lineup for the day containing `day`, scheduled for the whole lineup at once and kept.
' ponytail: on the render thread; a big library's first day takes the year's tape walk with it. Move it to a Task with
' the library if a real server's guide stalls on a Roku.
function daySlots(ch as Object, day as Double) as Object
    d = Time_startOfDay(day)
    k = iStr(d)
    all = m.dayCache[k]
    if all = invalid then
        all = GuideGenerator_scheduleLineup(m.channels, d)
        m.dayCache[k] = all
    end if
    s = all[ch.id]
    if s = invalid then
        s = GuideGenerator_schedule(ch, d)   ' a channel outside the lineup: on its own
        all[ch.id] = s
    end if
    return s
end function

' Slots intersecting [from, upTo], spanning days.
function slotsIn(ch as Object, from as Double, upTo as Double) as Object
    out = []
    day = Time_startOfDay(from)
    while day < upTo
        for each s in daySlots(ch, day)
            if s.finish > from and s.start < upTo then out.Push(s)
        end for
        day = Time_addDays(day, 1)
    end while
    return out
end function

function slotOnAir(ch as Object, at as Double) as Dynamic
    for each s in daySlots(ch, at)
        if s.start <= at and at < s.finish then return s
    end for
    return invalid
end function

' The slot by its exact start (sub-second tolerance for a start that went through JSON).
function slotStarting(ch as Object, start as Double) as Dynamic
    for each s in daySlots(ch, start)
        if Abs(s.start - start) < 1 then return s
    end for
    return invalid
end function

' {channel, slot} for a ProgramKey, or invalid.
function programAt(key as Dynamic) as Dynamic
    if key = invalid then return invalid
    ch = findChannel(key.channelID)
    if ch = invalid then return invalid
    s = slotStarting(ch, key.start)
    if s = invalid then return invalid
    return {channel: ch, slot: s}
end function

function makeKey(ch as Object, s as Object) as Object
    return {channelID: ch.id, start: s.start}
end function

function sameKey(a as Dynamic, b as Dynamic) as Boolean
    if a = invalid or b = invalid then return a = invalid and b = invalid
    return a.channelID = b.channelID and a.start = b.start
end function

' ---- Timers and the toast ----

' Run `action` in `seconds`; one timer per key, so re-arming replaces the pending one.
sub later(key as String, seconds as Float, action as Function)
    t = m.timers[key]
    if t = invalid then
        t = m.top.CreateChild("Timer")
        t.id = key
        t.repeat = false
        t.ObserveField("fire", "onTimerFire")
        m.timers[key] = t
    end if
    t.control = "stop"
    t.duration = seconds
    m.timerActions[key] = action
    t.control = "start"
end sub

sub cancelTimer(key as String)
    t = m.timers[key]
    if t <> invalid then t.control = "stop"
    m.timerActions.Delete(key)
end sub

sub onTimerFire(e as Object)
    key = e.GetNode()
    action = m.timerActions[key]
    if action = invalid then return
    m.timerActions.Delete(key)
    action()
    render()
end sub

sub toast(message as String)
    m.toastSerial = m.toastSerial + 1
    m.currentToast = {message: message, n: m.toastSerial}
    later("toast", 3.2, clearToast)
end sub

sub clearToast()
    m.currentToast = invalid
end sub

' ---- Navigation ----

sub go(target as String)
    if m.screen = "guide" and target <> "guide" then guidePark()
    if m.screen = "link" and target <> "link" then cancelLink()   ' a PIN or Quick Connect poll never outlives its screen
    if m.screen = "login" and target <> "login" then m.password = ""
    m.authSerial = m.authSerial + 1   ' a sign-in step in flight belongs to the screen being left
    if m.screen = "address" or m.screen = "login" then m.authBusy = false
    cancelTimer("banner")
    m.sleep = invalid
    m.screen = target
    m.overlay = invalid
    m.focusIndex = 0
    m.editingField = invalid
    if target = "link" then startLink()
    if target = "building" then startBuild()
end sub

sub closeOverlay()
    m.overlay = invalid
    m.focusIndex = 0
    if m.screen = "guide" and m.remoteHeld then guideBump()
end sub

sub openOptions()
    cancelTimer("idle")
    m.overlay = {kind: "options"}
    m.focusIndex = 1
end sub

sub openInfo(key as Object)
    cancelTimer("idle")
    cancelTimer("banner")
    m.overlay = {kind: "info", key: key}
    m.focusIndex = 0
end sub

' A remote press, to whichever overlay or screen owns the remote right now (the TS `press`; `press` is onKeyEvent's
' parameter here).
sub pressRemote(cmd as String)
    if m.overlay <> invalid then
        k = m.overlay.kind
        if k = "options" then
            pressOptions(cmd)
        else if k = "info" then
            pressInfo(cmd)
        else if k = "newChannel" then
            pressNewChannel(cmd)
        else if k = "makeChannel" then
            pressMakeChannel(cmd)
        end if
        return
    end if
    s = m.screen
    if s = "welcome" then
        pressWelcome(cmd)
    else if s = "address" then
        pressAddress(cmd)
    else if s = "link" then
        pressLink(cmd)
    else if s = "login" then
        pressLogin(cmd)
    else if s = "libraries" then
        pressLibraries(cmd)
    else if s = "building" then
        pressBuilding(cmd)
    else if s = "profiles" then
        pressProfiles(cmd)
    else if s = "guide" then
        pressGuide(cmd)
    else if s = "watch" then
        pressWatch(cmd)
    else if s = "channels" then
        pressChannels(cmd)
    else if s = "settings" then
        pressSettings(cmd)
    else if s = "search" then
        pressSearch(cmd)
    end if
end sub

' Move focusIndex within 0 ..< count for Up/Down (Left/Right when horizontal). True when the press was a move.
function stepFocus(cmd as String, count as Integer, horizontal = false as Boolean) as Boolean
    if horizontal then
        dec = "left"
        inc = "right"
    else
        dec = "up"
        inc = "down"
    end if
    if cmd <> dec and cmd <> inc then return false
    i = m.focusIndex
    if cmd = inc then i = i + 1 else i = i - 1
    if i > count - 1 then i = count - 1
    if i < 0 then i = 0
    m.focusIndex = i
    return true
end function

' Edit the current profile in place and save.
sub profileChanged()
    m.visibleCache = invalid
    save()
end sub

sub switchProfile(id as String)
    if m.screen = "guide" then guideReset()
    m.persisted.currentProfileID = id
    m.visibleCache = invalid
    save()
end sub

' ---- Guide core (shared with watch and overlays; the drift itself is GuideModel.brs) ----

' Leaving the guide (or letting go of the remote): the drift resumes from where the grid was. A held focus snaps to
' what's on now on its channel unless it's in the first window, the one the guide comes back to.
sub guidePark()
    cancelTimer("idle")
    if m.remoteHeld then m.guideTop = m.guideRow - 1
    t = Time_now()
    ws0 = windowStart(t, 0)
    if m.remoteHeld then
        k = guideKey(t)
        pr = programAt(k)
        if pr <> invalid then
            if pr.slot.start < ws0 + windowSpan() and pr.slot.finish > ws0 then
                m.focused = k
            else
                m.focused = cellAt(pr.channel, t, ws0)
            end if
        end if
    end if
    m.remoteHeld = false
    m.windowOffset = 0
end sub

' Profile change: start the guide over from the top.
sub guideReset()
    cancelTimer("idle")
    m.guideTop = 0
    m.guideRow = 0
    m.remoteHeld = false
    m.windowOffset = 0
    m.focused = invalid
end sub

' The cell on `ch` nearest `time` inside the window starting at `ws`.
function cellAt(ch as Object, time as Double, ws as Double) as Dynamic
    vis = slotsIn(ch, ws, ws + windowSpan())
    pick = invalid
    for each s in vis
        if s.start <= time and time < s.finish then
            pick = s
            exit for
        end if
    end for
    if pick = invalid then
        for each s in vis
            if pick = invalid then
                pick = s
            else if Abs(s.start - time) < Abs(pick.start - time) then
                pick = s
            end if
        end for
    end if
    if pick = invalid then pick = slotOnAir(ch, time)
    if pick = invalid then return invalid
    return makeKey(ch, pick)
end function

' The focused cell, falling back to what's airing now on the first visible channel.
function guideKey(at = -1 as Double) as Dynamic
    if at < 0 then at = Time_now()
    k = m.focused
    p = programAt(k)
    if p <> invalid then
        visible = false
        for each c in visibleChannels()
            if c.id = p.channel.id then
                visible = true
                exit for
            end if
        end for
        if visible then
            if m.remoteHeld or p.slot.finish > at then return k
            ' Drifting and the focused program is over: follow the channel to what's on now.
            cur = cellAt(p.channel, at, windowStart(at, 0))
            if cur <> invalid then return cur
        end if
    end if
    list = visibleChannels()
    if list.Count() = 0 then return invalid
    return cellAt(list[0], at, windowStart(at, 0))
end function

' ---- Tune / watch core ----

' Start watching `channelID`. "live" joins in progress (unless the tune mode says start over and `force` is false);
' "start" plays the slot beginning at `programStart` from its beginning.
sub tune(channelID as String, mode as String, programStart = -1 as Double, force = false as Boolean)
    ch = findChannel(channelID)
    if ch = invalid then return
    t = Time_now()
    onAir = slotOnAir(ch, t)
    tuneMode = ch.definition.tuneMode
    if tuneMode = invalid then tuneMode = settings().tuneMode
    if mode = "start" and programStart >= 0 then
        pb = Playback_new(channelID, "start", programStart, {slot: slotStarting(ch, programStart)})
    else if tuneMode = "start" and not force and onAir <> invalid then
        pb = Playback_new(channelID, "start", onAir.start, {slot: onAir})
    else
        st = t
        if onAir <> invalid then st = onAir.start
        pb = Playback_new(channelID, "live", st, {slot: onAir})
    end if
    pb.fromStart = pb.mode = "start"   ' both "start" cases play from the slot's beginning
    if m.screen = "guide" then guidePark()
    cancelTimer("seek")   ' a skip's pending reload would load this channel a second time
    same = m.screen = "watch" and m.playback <> invalid and m.playback.channelID = channelID
    fromPlayer = m.screen = "watch"
    if m.playback <> invalid and m.playback.channelID <> channelID then
        m.persisted.lastChannelID = m.playback.channelID
        save()
    end if
    m.screen = "watch"
    m.overlay = invalid
    m.focusIndex = 0
    m.playback = pb
    followEndOfProgram()
    m.tunes = m.tunes + 1
    ' The banner shows on a change of channel in the player. Picked in the guide, Search or Program info, the viewer has
    ' just read what it is, so none (OK brings it up). In a break the card says it all.
    info = watchInfo()
    m.bannerVisible = fromPlayer and info <> invalid and not WatchInfo_isBreak(info)
    m.bannerFocus = -1
    if not same then m.flips = m.flips + 1
    bannerLater()
end sub

' {channelID, mode, programStart, offset, startedAt, paused, slot, fromStart, markDue}; p holds the optional fields.
function Playback_new(channelID as String, mode as String, programStart as Double, p as Object) as Object
    pb = {channelID: channelID, mode: mode, programStart: programStart, offset: 0#, startedAt: Time_now(), paused: false,
          slot: p.slot, fromStart: false, markDue: false}
    if p.offset <> invalid then pb.offset = p.offset
    if p.startedAt <> invalid then pb.startedAt = p.startedAt
    if p.paused <> invalid then pb.paused = p.paused
    if p.fromStart <> invalid then pb.fromStart = p.fromStart
    return pb
end function

function lastChannel() as Dynamic
    ch = findChannel(m.persisted.lastChannelID)
    if ch = invalid then return invalid
    if isHidden(ch.id) then return invalid
    return ch
end function

' Back to the guide, drifting from the channel that was on.
sub toGuide(from as String)
    list = visibleChannels()
    i = -1
    for j = 0 to list.Count() - 1
        if list[j].id = from then
            i = j
            exit for
        end if
    end for
    if i >= 0 then
        m.guideTop = i - 1
        t = Time_now()
        m.focused = cellAt(list[i], t, windowStart(t, 0))
    else
        m.focused = invalid
    end if
    cancelTimer("banner")
    if m.sleep <> invalid then
        m.sleep = invalid
        toast("Sleep timer off.")   ' the guide's preview keeps the TV awake
    end if
    m.screen = "guide"
    m.overlay = invalid
    m.focusIndex = 0
    m.editingField = invalid
    m.windowOffset = 0
    m.remoteHeld = false
    m.bannerVisible = false
    m.bannerFocus = -1
end sub

' ---- Channels ----

function byNumber(a as Object, b as Object, ctx as Dynamic) as Integer
    if a.number <> b.number then return a.number - b.number
    return swiftCompare(a.id, b.id)
end function

' The lineup from `library` (which automatic channels exist, and their numbers) plus the viewer's edits and custom
' channels; `fresh` only adds to the "what's new" channels. {auto, channels}.
function resolveChannels(library as Object, fresh as Object, edits as Object, custom as Object) as Object
    auto = ChannelBuilder_automaticChannels(library)
    defs = []
    for each d in auto
        e = edits[d.id]
        if e <> invalid then d = ChannelDefinition_copy(d, Edit_apply(e, d))
        defs.Push(d)
    end for
    ' The holiday channel, last of the automatic ones, steps past a custom channel's number as the lineup steps past 99.
    for i = 0 to defs.Count() - 1
        if defs[i].id = "holiday" and (edits["holiday"] = invalid or edits["holiday"].number = invalid) then
            taken = newMap()
            for each c in custom
                taken[iStr(c.number)] = true
            end for
            n = defs[i].number
            while taken[iStr(n)] <> invalid or n = 99
                n = n + 1
            end while
            defs[i] = ChannelDefinition_copy(defs[i], {number: n})
        end if
    end for
    resolved = ChannelBuilder_channels(concat(defs, custom), library, fresh, Time_now())
    if library.Count() > 0 then   ' channel 99 rides along with any real lineup; rename and renumber still apply
        scr = Channel_scrambled()
        e = edits[scr.id]
        if e <> invalid then
            ch = {}
            if e.name <> invalid then ch.name = e.name
            if e.number <> invalid then ch.number = e.number
            if e.tuneMode <> invalid then ch.tuneMode = e.tuneMode
            scr = Channel_new(ChannelDefinition_copy(scr.definition, ch), scr.items)
        end if
        resolved.Push(scr)
    end if
    return {auto: auto, channels: stableSort(resolved, byNumber)}
end function

' The fields an edit overrides on definition d.
function Edit_apply(e as Object, d as Object) as Object
    c = {}
    if e.name <> invalid then c.name = e.name
    if e.number <> invalid then c.number = e.number
    if e.order <> invalid then c.order = e.order
    if e.trailerBreaks <> invalid then c.trailerBreaks = e.trailerBreaks
    if e.tuneMode <> invalid then c.tuneMode = e.tuneMode
    return c
end function

sub rebuildChannels()
    r = resolveChannels(m.library, m.freshItems, m.persisted.channelEdits, m.persisted.customChannels)
    m.autoDefinitions = r.auto
    setChannels(r.channels)
end sub

' Replace (or insert) one channel from its definition: one library filter instead of one per definition.
sub splice(d as Object)
    others = []
    for each c in m.channels
        if c.id <> d.id then others.Push(c)
    end for
    others.Append(ChannelBuilder_channels([d], m.library, m.freshItems, Time_now()))
    setChannels(stableSort(others, byNumber))
end sub

' Edit fields of a channel: an automatic one records an edit, a custom one is written into its definition.
sub updateChannel(id as String, changes as Object)
    for i = 0 to m.persisted.customChannels.Count() - 1
        if m.persisted.customChannels[i].id = id then
            d = ChannelDefinition_copy(m.persisted.customChannels[i], changes)
            m.persisted.customChannels[i] = d
            save()
            splice(d)
            return
        end if
    end for
    ch = findChannel(id)
    if ch = invalid then return
    d = ChannelDefinition_copy(ch.definition, changes)
    e = m.persisted.channelEdits[id]
    if e = invalid then e = {name: invalid, number: invalid, order: invalid, tuneMode: invalid, trailerBreaks: invalid}
    e.name = d.name
    e.number = d.number
    e.order = d.order
    e.trailerBreaks = d.trailerBreaks
    e.tuneMode = d.tuneMode
    m.persisted.channelEdits[id] = e
    save()
    if id = "scrambled" then
        rebuildChannels()
    else
        splice(d)
    end if
end sub

sub resetChannel(id as String)
    m.persisted.channelEdits.Delete(id)
    save()
    if id = "scrambled" then
        rebuildChannels()
        return
    end if
    for each d in m.autoDefinitions
        if d.id = id then splice(d)
    end for
end sub

sub deleteCustomChannel(id as String)
    kept = []
    for each d in m.persisted.customChannels
        if d.id <> id then kept.Push(d)
    end for
    m.persisted.customChannels = kept
    save()
    others = []
    for each c in m.channels
        if c.id <> id then others.Push(c)
    end for
    setChannels(others)
end sub

sub addCustomChannel(d as Object)
    m.persisted.customChannels.Push(d)
    save()
    splice(d)
end sub

sub setHidden(id as String, hidden as Boolean)
    p = currentProfile()
    if hidden then p.hidden[id] = true else p.hidden.Delete(id)
    profileChanged()
end sub

sub setFavorite(id as String, starred as Boolean)
    p = currentProfile()
    if starred then p.favorites[id] = true else p.favorites.Delete(id)
    profileChanged()
end sub

' The movie whose trailer fills a break on `ch` after `s`. Deterministic (channel + slot start), so the guide's preview
' and the player agree.
function breakTrailerCandidate(ch as Object, s as Object) as Dynamic
    pool = []
    items = ch.items
    if ChannelDefinition_hasChip(ch.definition, "holiday") then
        items = []
        for each x in daySlots(ch, s.start)
            items.Push(x.item)
        end for
    end if
    for each it in items
        if it.kind = "movie" and it.id <> s.item.id then pool.Push(it)
    end for
    if pool.Count() = 0 then
        for each it in m.movies
            if it.id <> s.item.id then pool.Push(it)
        end for
    end if
    if pool.Count() = 0 then return invalid
    return pool[U64_mod(StableHash_fnv1a(ch.id + "|" + iStr(Int(s.start))), pool.Count())]
end function

' Lowest unused channel number from 50 up (custom channels).
function nextFreeNumber() as Integer
    used = newMap()
    for each c in m.channels
        used[iStr(c.number)] = true
    end for
    n = 50
    while used[iStr(n)] <> invalid
        n = n + 1
    end while
    return n
end function

' ---- Server and library ----

' A server link made (or the Sample station picked): keep it, and the token.
sub connect(config as Object, token as String)
    m.username = ""
    m.password = ""   ' a shared TV mustn't offer the next person this sign-in
    Store_set("token", token)
    m.persisted.serverConfig = config
    save()
    m.libraryGen = m.libraryGen + 1
    m.freshItems = []
    m.server = Server_make(config, token, deviceID(), settings().maxBitrateKbps)
end sub

' Re-create the client from the saved link (after a setting the clients read changes, e.g. quality).
sub rebuildServer()
    cfg = m.persisted.serverConfig
    if cfg = invalid then return
    token = Store_get("token")
    if token = invalid then
        if cfg.kind <> "demo" then return
        token = ""
    end if
    m.server = Server_make(cfg, token, deviceID(), settings().maxBitrateKbps)
end sub

sub signOut()
    m.libraryGen = m.libraryGen + 1
    Store_delete("token")
    Store_delete("plexAccount")
    m.persisted.serverConfig = invalid
    m.persisted.selectedLibraryIDs = invalid
    save()
    m.server = invalid
    setLibrary([])
    setChannels([])
    m.librarySections = []
    m.freshItems = []
    m.username = ""
    m.password = ""
    m.pendingToken = invalid
    m.foundServers = []
    LibraryCache_clear()
    go("welcome")
end sub

' The display name of a server kind.
function serverKindName(kind as String) as String
    if kind = "plex" then return "Plex"
    if kind = "emby" then return "Emby"
    if kind = "jellyfin" then return "Jellyfin"
    return "Demo"
end function

function serverLabel() as String
    if m.server = invalid then return ""
    return m.server.serverName + " · " + serverKindName(m.server.kind)
end function
