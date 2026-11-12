' The render thread's side of web/src/core/MediaServer.ts and the clients: roUrlTransfer isn't allowed on the render
' thread, so every server call runs in a ServerTask (components/ServerTask.brs, one task per request) and answers a
' named continuation here. The Sample station answers at once, on this thread.
' m.server is the client's settings (ServerTask builds its client from them): {kind, serverName, baseURL, token,
' userID, deviceID, maxBitrateKbps, addresses, machineID}.

function Server_make(cfg as Object, token as String, devID as String, maxBitrateKbps as Integer) as Object
    return {kind: cfg.kind, serverName: cfg.name, baseURL: cfg.baseURL, token: token, userID: cfg.userID, deviceID: devID,
            maxBitrateKbps: maxBitrateKbps, addresses: cfg.addresses, machineID: cfg.machineID}
end function

' Ask a ServerTask for `op` with `args` (m.server rides along as args.server). `onDone(r, ctx)` runs here with
' {ok, value} or {ok: false, error (one short user-safe line), kind ("unauthorized", "notFound", "unreachable", ...)}.
sub request(op as String, args as Object, onDone as Function, ctx = invalid as Dynamic)
    if ctx = invalid then ctx = {}
    m.requestSerial = m.requestSerial + 1
    id = "request" + iStr(m.requestSerial)
    t = CreateObject("roSGNode", "ServerTask")
    t.id = id
    if args.server = invalid and m.server <> invalid then args.server = m.server
    args.deviceID = deviceID()
    t.request = {op: op, args: args}
    t.ObserveField("response", "onServerResponse")
    m.pending[id] = {onDone: onDone, ctx: ctx, task: t}
    t.control = "RUN"
end sub

sub onServerResponse(e as Object)
    id = e.GetNode()
    p = m.pending[id]
    if p = invalid then return
    m.pending.Delete(id)
    r = e.GetData()
    if type(r) <> "roAssociativeArray" then r = {ok: false, error: "The operation couldn’t be completed.", kind: "invalid"}
    if not r.ok and r.kind = "unauthorized" and p.ctx.signsOut = true then serverUnauthorized()
    ' Called through a local, never as p.onDone(...): that would make `m` the pending record inside the continuation.
    f = p.onDone
    f(r, p.ctx)
    render()
end sub

' A dead token: the device is signed out, with a toast that says so.
sub serverUnauthorized()
    name = "The server"
    if m.server <> invalid then name = serverKindName(m.server.kind)
    msg = name + " signed this device out. Sign in again."
    toast(msg)
    signOut()
end sub

' The server's libraries: onDone(r) with r.value [{id, title, kind, itemCount}].
sub serverLibraries(onDone as Function, ctx as Object)
    if m.server.kind = "demo" then
        onDone({ok: true, value: DemoServer_libraries()}, ctx)
        return
    end if
    ctx.signsOut = true
    request("libraries", {}, onDone, ctx)
end sub

' Load the library: the cached index first (instant launch), then the server's, unless the cache is under six hours
' old (`force` skips that: Settings > Rebuild, a changed library selection). A newer load or a sign-out supersedes
' this one (libraryGen), so a slow answer can't write stale data.
sub loadLibrary(refresh as Boolean, force as Boolean)
    if m.server = invalid then return
    m.libraryGen = m.libraryGen + 1
    gen = m.libraryGen
    link = Server_link(m.persisted.serverConfig)
    if m.library.Count() = 0 and m.server.kind <> "demo" then
        cached = LibraryCache_load(link)
        if cached <> invalid then
            setLibrary(Duplicates_merge(cached))
            rebuildChannels()
        end if
    end if
    if not refresh then return
    age = LibraryCache_age()
    if not force and m.library.Count() > 0 and age >= 0 and age < 6 * 3600 then
        m.libraryLoading = false
        return
    end if
    m.libraryLoading = true
    m.libraryError = invalid
    ids = m.persisted.selectedLibraryIDs
    if m.server.kind = "demo" then
        sections = DemoServer_libraries()
        items = []
        for each it in DemoServer_items()
            if ids = invalid or contains(ids, it.libraryID) then items.Push(it)
        end for
        onLibraryLoaded({ok: true, value: {sections: sections, items: items}}, {gen: gen, link: link})
        return
    end if
    request("loadLibrary", {sectionIDs: ids, link: link}, onLibraryLoaded, {gen: gen, link: link, signsOut: true})
end sub

' r.value: {sections, items}, the items merged (Duplicates) and the cache written by the task.
sub onLibraryLoaded(r as Object, ctx as Object)
    if ctx.gen <> m.libraryGen then
        ' Signed out or switched servers while it loaded: that cache belongs to no current link.
        if m.persisted.serverConfig = invalid or Server_link(m.persisted.serverConfig) <> ctx.link then LibraryCache_clear()
        return
    end if
    m.libraryLoading = false
    if not r.ok then
        if r.kind = "unauthorized" then return   ' signed out already
        m.libraryError = r.error
        if m.channels.Count() > 0 then toast(r.error)   ' the cache is on screen, so the guide's empty line never shows
        m.rebuildToast = false
        return
    end if
    sections = []
    for each s in r.value.sections
        if s.itemCount = invalid or s.itemCount <> 0 then sections.Push(s)
    end for
    m.librarySections = sections
    setLibrary(r.value.items)
    m.freshItems = []
    rebuildChannels()
    if m.screen = "building" then revealBuild()
    if m.screen = "guide" then holdForLaunch()
    if m.rebuildToast = true then
        m.rebuildToast = false
        toast("Channels rebuilt. Your edits and custom channels stayed put.")
    end if
end sub

' What the player loads for `item` from `offset` seconds in: onDone(r) with r.value {url, startsAtOffset, loop}.
' `session` is "preview" (the guide's window) or "watch".
sub playbackSource(item as Object, offset as Double, session as String, onDone as Function, ctx as Object)
    if m.server = invalid then
        onDone({ok: false, error: "Could not connect to the server.", kind: "unreachable"}, ctx)
        return
    end if
    if m.server.kind = "demo" then   ' a fixed ~10 min sample that starts at its own beginning; the player loops it
        onDone({ok: true, value: {url: DemoServer_playbackURL(), startsAtOffset: true, loop: true, format: "hls"}}, ctx)
        return
    end if
    stopID = invalid
    if m.playSessions <> invalid then stopID = m.playSessions[session]
    wrap = {signsOut: true, session: session, onDone: onDone, ctx: ctx}
    request("playbackSource", {item: item, offset: offset, session: session, stopID: stopID}, onPlaybackSource, wrap)
end sub

' Each request is a new task, so the transcode a Jellyfin or Emby load started (its PlaySessionId) is kept here, for
' the next load or stopPlayback of that session to end.
sub onPlaybackSource(r as Object, ctx as Object)
    if m.playSessions = invalid then m.playSessions = {}
    if r.ok then m.playSessions[ctx.session] = r.value.playSessionId
    f = ctx.onDone
    f(r, ctx.ctx)
end sub

' Best-effort: the server's transcode for `session` can stop now.
sub stopPlayback(session as String)
    if m.server = invalid or m.server.kind = "demo" then return
    stopID = invalid
    if m.playSessions <> invalid then
        stopID = m.playSessions[session]
        m.playSessions.Delete(session)
    end if
    request("stopPlayback", {session: session, stopID: stopID}, ignoreAnswer)
end sub

' A program started from its beginning played to 90%: marked watched on the server. No-op for the Sample station.
sub markWatched(item as Object)
    if m.server = invalid or m.server.kind = "demo" then return
    request("markWatched", {item: item}, ignoreAnswer)
end sub

sub ignoreAnswer(r as Object, ctx as Object)
end sub

' Absolute, authenticated URL for a server-relative artwork path, or "" (the Sample station has none).
function artworkURL(path as Dynamic, w = 600 as Integer, h = 400 as Integer) as String
    s = m.server
    if s = invalid or path = invalid or path = "" or s.kind = "demo" then return ""
    if s.kind = "plex" then
        return s.baseURL + "/photo/:/transcode?width=" + iStr(w) + "&height=" + iStr(h) + "&minSize=1&url=" + encodeURIComponent(path) + "&X-Plex-Token=" + encodeURIComponent(s.token)
    end if
    ' Emby and Jellyfin: the path is "Items/{id}/Images/{type}"; the token rides in the query (an image request has no headers).
    sep = "?"
    if Instr(1, path, "?") > 0 then sep = "&"
    return s.baseURL + "/" + path + sep + "maxWidth=" + iStr(w) + "&quality=90&api_key=" + encodeURIComponent(s.token)
end function

' Wide art for the preview window, falling back to the poster.
function backdropURL(item as Object) as String
    p = item.backdropPath
    if p = invalid then p = item.artworkPath
    return artworkURL(p, 1280, 720)
end function

' RFC 3986 unreserved characters stay; everything else is %XX of its UTF-8 bytes (roUrlTransfer isn't allowed here).
function encodeURIComponent(s as String) as String
    ba = CreateObject("roByteArray")
    ba.FromAsciiString(s)
    hexd = "0123456789ABCDEF"
    out = ""
    for i = 0 to ba.Count() - 1
        b = ba[i]
        if (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b = 45 or b = 46 or b = 95 or b = 126 then
            out = out + Chr(b)
        else
            out = out + "%" + Mid(hexd, b \ 16 + 1, 1) + Mid(hexd, b mod 16 + 1, 1)
        end if
    end for
    return out
end function
