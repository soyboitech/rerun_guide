' A ServerTask runs one request (app/Server.brs `request`) off the render thread and sets `response` to {ok, value} or
' {ok: false, error, kind}. args.server is the client's settings (Server_make); args.deviceID this device's client id.
sub init()
    m.top.functionName = "runRequest"
end sub

sub runRequest()
    req = m.top.request
    r = invalid
    try
        r = Server_dispatch(req.op, req.args)
    catch e
        r = {ok: false, error: "The operation couldn’t be completed.", kind: "invalid", detail: e.message}
    end try
    if r = invalid then r = {ok: false, error: "The operation couldn’t be completed.", kind: "invalid"}
    m.top.response = r
end sub

function Server_dispatch(op as String, args as Object) as Object
    dev = args.deviceID
    s = args.server
    ' Sign-in: plex.tv, Emby Connect, and a Jellyfin or Emby server's own.
    if op = "plexSignIn" then return Plex_signIn(args.username, args.password, dev)
    if op = "plexRequestPIN" then return Plex_requestPIN(dev)
    if op = "plexPollPIN" then return Plex_pollPIN(args.pin, dev)
    if op = "plexServers" then return Plex_servers(args.token, dev)
    if op = "plexServerAt" then return Plex_serverAt(args.url, args.account, dev)
    if op = "embyRequestPIN" then return EC_requestPIN(dev)
    if op = "embyPollPIN" then return EC_pollPIN(args.pin)
    if op = "embyServers" then return EC_servers(args.account)
    if op = "embyExchange" then return JF_connectExchange(args.server, args.connectUserID, dev)
    if op = "jfLogin" then return JF_login(args.url, args.username, args.password, dev)
    if op = "jfQuickConnectStart" then return JF_quickConnectStart(args.url, dev)
    if op = "jfQuickConnectCheck" then return JF_quickConnectCheck(args.url, args.secret, dev)
    if op = "jfQuickConnectLogin" then return JF_quickConnectLogin(args.url, args.secret, dev)
    if s = invalid then return {ok: false, error: "Could not connect to the server.", kind: "unreachable"}
    ' The signed-in server.
    if op = "libraries" then
        if s.kind = "plex" then return Plex_libraries(s, true)
        return JF_libraries(s, true)
    end if
    if op = "loadLibrary" then return Server_loadLibrary(s, args.sectionIDs, args.link)
    if op = "playbackSource" then
        if s.kind = "plex" then return Plex_playbackSource(s, args.item.id, args.session)
        return JF_playbackSource(s, args.item.id, args.offset, args.session, args.stopID)
    end if
    if op = "stopPlayback" then
        if s.kind = "plex" then return Plex_stopPlayback(s, args.session)
        return JF_stopPlayback(s, args.stopID)
    end if
    if op = "markWatched" then
        if s.kind = "plex" then return Plex_markWatched(s, args.item)
        return JF_markWatched(s, args.item)
    end if
    return {ok: false, error: "The operation couldn’t be completed.", kind: "invalid"}
end function

' The library load (AppModel.loadLibraryOnce's server half): the sections, the chosen ones' items with each film and
' episode once (a 4K library's copies last), and the cache written. {sections, items}.
function Server_loadLibrary(s as Object, ids as Dynamic, link as String) as Object
    if s.kind = "plex" then r = Plex_libraries(s, false) else r = JF_libraries(s, false)
    if not r.ok then return r
    sections = r.value
    last = Duplicates_lastResort(sections)
    ' Every library is one query that names none, unless a 4K library has to go last: then library by library.
    chosen = invalid
    if ids <> invalid then
        chosen = []
        for each sec in sections
            if contains(ids, sec.id) then chosen.Push(sec)
        end for
    else if last.Count() > 0 then
        chosen = sections
    end if
    if s.kind = "plex" then
        items = Plex_libraryItems(s, chosen)
    else
        chosenIDs = invalid
        if chosen <> invalid then
            chosenIDs = []
            for each sec in chosen
                chosenIDs.Push(sec.id)
            end for
        end if
        items = JF_libraryItems(s, chosenIDs)
    end if
    if not items.ok then return items
    merged = Duplicates_merge(items.value, last)
    LibraryCache_save(merged, link)
    return {ok: true, value: {sections: sections, items: merged}}
end function
