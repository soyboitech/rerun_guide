' The app: the model (app/Model.brs and the *Model.brs handlers, the web's AppModel*.ts) and the 1920x1080 stage its
' views draw. The remote's keys become the app's commands (the web's Remote.ts); render() redraws after every press,
' timer, tick and server answer.

sub init()
    m.top.backgroundColor = "0x14110FFF"
    m.top.backgroundURI = ""
    m.t = Theme_late()
    m.fonts = {}
    m.timers = {}
    m.timerActions = {}
    m.pending = {}
    m.requestSerial = 0
    m.linkSerial = 0
    m.launched = false
    Model_init()
    m.stage = UI_group(m.top)
    m.screenLayer = UI_group(m.stage)
    m.overlayLayer = UI_group(m.stage)
    m.toastLayer = UI_group(m.stage)
    ToastView_build(m.toastLayer)
    m.shownScreen = ""
    m.shownOverlay = ""
    m.tick = m.top.CreateChild("Timer")
    m.tick.repeat = true
    m.tick.duration = 1
    m.tick.ObserveField("fire", "onTick")
    m.tick.control = "start"
    Model_start()
    render()
    m.top.SetFocus(true)
end sub

' Roku's keys as the app's commands. Rewind and fast forward are the player's 10 s skips (Left and Right there), and
' instant replay goes back 10 s; the * button opens Options on the guide.
function remoteCommand(key as String) as Dynamic
    if key = "up" or key = "down" or key = "left" or key = "right" or key = "back" then return key
    if key = "OK" then return "select"
    if key = "play" or key = "playonly" then return "play"
    inPlayer = m.screen = "watch" and m.overlay = invalid
    if inPlayer then
        if key = "rewind" or key = "replay" then return "left"
        if key = "fastforward" then return "right"
        if key = "channelup" then return "up"
        if key = "channeldown" then return "down"
        return invalid   ' the * button over the video is Roku's own menu (certification 4.4)
    end if
    if key = "options" then return "options"
    return invalid
end function

' Back at the app's top level leaves the app: the drifting guide and Welcome.
function backExitsApp() as Boolean
    if m.overlay <> invalid or m.editingField <> invalid then return false
    return (m.screen = "guide" and not m.remoteHeld) or m.screen = "welcome"
end function

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    cmd = remoteCommand(key)
    if cmd = invalid then return false
    if cmd = "back" and backExitsApp() then return false   ' unhandled, so Roku closes the app
    pressRemote(cmd)
    render()
    return true
end function

' Once a second: the clocks, the progress bars, and the player's tick (the sleep timer, catching up to live).
sub onTick()
    if m.screen = "watch" then watchTick(Time_now())
    render()
end sub

sub render()
    if m.shownScreen <> m.screen then switchScreen()
    s = m.screen
    if s = "guide" then
        GuideView_update()
        applyDeepLink()
    else if s = "watch" then
        WatchView_update()
    else if s = "settings" then
        SettingsView_update()
    else if s = "channels" then
        ChannelsView_update()
    else if s = "profiles" then
        ProfilesView_update()
    else if s = "search" then
        SearchView_update()
    else
        OnboardingView_update()
    end if
    renderOverlay()
    ToastView_update()
    if not m.launched and (s <> "guide" or not m.libraryLoading) then
        m.launched = true
        m.top.signalBeacon("AppLaunchComplete")   ' the home screen is up (certification 3.2)
    end if
end sub

' The screen changed: drop the old screen's nodes (its player stopped first) and build the new one's.
sub switchScreen()
    old = m.shownScreen
    if old = "guide" then
        GuideView_stopPreview()
        GuideView_stopDrift()
        stopPlayback("preview")
        m.guide = invalid
    else if old = "watch" then
        WatchView_stop()
        stopPlayback("watch")
        m.watch = invalid
    end if
    m.screenLayer.RemoveChildrenIndex(m.screenLayer.GetChildCount(), 0)
    m.shownScreen = m.screen
    s = m.screen
    if s = "guide" then
        GuideView_build(m.screenLayer)
    else if s = "watch" then
        WatchView_build(m.screenLayer)
    else if s = "settings" then
        SettingsView_build(m.screenLayer)
    else if s = "channels" then
        ChannelsView_build(m.screenLayer)
    else if s = "profiles" then
        ProfilesView_build(m.screenLayer)
    else if s = "search" then
        SearchView_build(m.screenLayer)
    else
        OnboardingView_build(m.screenLayer)
    end if
end sub

sub renderOverlay()
    o = m.overlay
    key = ""
    if o <> invalid then
        key = o.kind
        if o.kind = "info" then key = key + "|" + o.key.channelID + "|" + iStr(o.key.start)
    end if
    if key <> m.shownOverlay then
        m.overlayLayer.RemoveChildrenIndex(m.overlayLayer.GetChildCount(), 0)
        m.shownOverlay = key
        if o <> invalid then
            if o.kind = "options" then OptionsView_build(m.overlayLayer)
            if o.kind = "info" then InfoView_build(m.overlayLayer)
        end if
    end if
    if o = invalid then return
    if o.kind = "options" then OptionsView_update()
    if o.kind = "info" then InfoView_update()
end sub

' Roku's memory warning (main.brs): drop what the model rebuilds on demand, the search index and every day's
' schedule but today's.
sub onLowMemory()
    m.searchIndex = invalid
    k = iStr(Time_startOfDay(Time_now()))
    today = m.dayCache[k]
    m.dayCache = newMap()
    if today <> invalid then m.dayCache[k] = today
end sub

' ---- Deep links (certification 5.1): contentId is a channel id (the Sample station's too), mediaType "live"/"livefeed"
' or any other; a channel that isn't there leaves the app on its home screen. ----

sub onLaunchArgs()
    takeDeepLink(m.top.launchArgs)
end sub

sub onDeepLink()
    takeDeepLink(m.top.deepLink)
end sub

sub takeDeepLink(args as Dynamic)
    if type(args) <> "roAssociativeArray" then return
    id = invalid
    for each k in args
        if LCase(k) = "contentid" then id = args[k]
    end for
    if id = invalid or id = "" then return
    m.pendingDeepLink = id
    ' Nothing linked yet (a reviewer's first launch): the Sample station's channel ids are valid content ids.
    if m.persisted.serverConfig = invalid and (m.screen = "welcome" or m.shownScreen = "") then
        m.serviceKind = "demo"
        connect({kind: "demo", baseURL: "demo://local", name: "Demo library"}, "")
        loadLibrary(true, true)
        go("guide")
    end if
    render()
end sub

' Tune to a pending deep link once the lineup is in.
sub applyDeepLink()
    id = m.pendingDeepLink
    if id = invalid or m.channels.Count() = 0 or m.screen <> "guide" then return
    m.pendingDeepLink = invalid
    ch = findChannel(id)
    if ch = invalid then
        for each c in m.channels
            if iStr(c.number) = id then ch = c
        end for
    end if
    if ch <> invalid then
        tune(ch.id, "live")
        render()
    end if
end sub
