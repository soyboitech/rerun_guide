' Port of web/src/core/PlexClient.ts for ServerTask: plex.tv PIN and password sign-in, the account's servers and which of
' their addresses answers, the libraries, the items, and the universal transcoder's HLS. Results, not exceptions
' (Http.brs). A PlexServer row is {id, name, baseURL, accessToken, addresses: [{url, local}]}.
' Not on Roku yet: track selection (the PUT on the part), trailers, recently added.

function Plex_headers(token as Dynamic, clientID as String) as Object
    h = {}
    h["Accept"] = "application/json"
    h["X-Plex-Client-Identifier"] = clientID
    h["X-Plex-Product"] = "Rerun Guide"
    h["X-Plex-Version"] = "1.0"
    h["X-Plex-Platform"] = "Roku"
    h["X-Plex-Device"] = Http_deviceName()
    h["X-Plex-Device-Name"] = "Rerun Guide"
    if token <> invalid then h["X-Plex-Token"] = token
    return h
end function

' base + path (+ query), keeping a base's own path prefix and dropping its trailing slash.
function Plex_url(base as String, path as String, query = [] as Object) as String
    b = base
    while Right(b, 1) = "/"
        b = Left(b, Len(b) - 1)
    end while
    return b + path + Http_query(query)
end function

' ---- plex.tv ----

function Plex_signIn(username as String, password as String, clientID as String) as Object
    h = Plex_headers(invalid, clientID)
    h["Content-Type"] = "application/x-www-form-urlencoded"
    body = "login=" + Http_escape(username) + "&password=" + Http_escape(password)
    r = Http_json("POST", "https://plex.tv/api/v2/users/signin", h, body)
    if not r.ok then return r
    if r.value.authToken = invalid then return Http_fail("invalid", "The data couldn’t be read because it isn’t in the correct format.")
    return {ok: true, value: r.value.authToken}
end function

' A 4-character code for plex.tv/link: {id, code}.
function Plex_requestPIN(clientID as String) as Object
    r = Http_json("POST", "https://plex.tv/api/v2/pins", Plex_headers(invalid, clientID), "")
    if not r.ok then return r
    if r.value.id = invalid or r.value.code = invalid then return Http_fail("invalid", "The data couldn’t be read because it isn’t in the correct format.")
    return {ok: true, value: {id: r.value.id, code: r.value.code}}
end function

' The account token once the code has been typed; invalid until then.
function Plex_pollPIN(pin as Object, clientID as String) as Object
    r = Http_json("GET", "https://plex.tv/api/v2/pins/" + iStr(pin.id), Plex_headers(invalid, clientID))
    if not r.ok then
        if r.kind = "http" and r.code = 404 then return Http_fail("notFound", "Not found: PIN expired. Request a new code")
        return r
    end if
    return {ok: true, value: r.value.authToken}
end function

function Plex_resources(token as String, clientID as String) as Object
    return Http_json("GET", "https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=0", Plex_headers(token, clientID))
end function

function Plex_isServer(r as Object) as Boolean
    if r.provides = invalid then return false
    return contains(r.provides.Split(","), "server")
end function

' plex.tv's addresses for a server, best first: LAN before remote before relay, https before http; a LAN connection also
' gets its plain http://address:port unless the server requires secure connections.
function Plex_ranked(r as Object) as Object
    all = []
    conns = r.connections
    if type(conns) <> "roArray" then conns = []
    for each c in conns
        if c.uri <> invalid and Http_host(c.uri) <> invalid then all.Push({rank: Plex_priority(c) * 1000 + all.Count(), url: c.uri, local: isTrue(c.local)})
        if isTrue(c.local) and not isTrue(c.relay) and not isTrue(r.httpsRequired) and c.address <> invalid and c.port <> invalid then
            all.Push({rank: 1000 + all.Count(), url: "http://" + c.address + ":" + iStr(c.port), local: true})
        end if
    end for
    seen = newMap()
    out = []
    for each a in stableSort(all, Plex_byRank)
        if seen[a.url] = invalid then
            seen[a.url] = true
            out.Push({url: a.url, local: a.local})
        end if
    end for
    return out
end function

function Plex_byRank(a as Object, b as Object, ctx as Dynamic) as Integer
    return a.rank - b.rank
end function

function Plex_priority(c as Object) as Integer
    p = 1
    if isTrue(c.local) then
        p = 0
    else if isTrue(c.relay) then
        p = 2
    end if
    q = 1
    if c.protocol = "https" then q = 0
    return p * 2 + q
end function

' Whether plex.tv lists `at`'s host and port among the server's connections.
function Plex_lists(r as Object, at as String) as Boolean
    typed = Http_hostPort(at)
    if typed = invalid or type(r.connections) <> "roArray" then return false
    for each c in r.connections
        if Http_hostPort(c.uri) = typed then return true
        if c.address <> invalid and c.port <> invalid and Http_hostPort("http://" + c.address + ":" + iStr(c.port)) = typed then return true
    end for
    return false
end function

' Every address probed at once (GET /identity, no token); the best-ranked one that reports `machineID` wins, so a
' stranger's LAN at the same IP can't stand in for the server. invalid when none does within 4 s (2 s is plenty on a LAN).
function Plex_bestAddress(ranked as Object, machineID as String, clientID as String) as Dynamic
    port = CreateObject("roMessagePort")
    xfers = []
    for i = 0 to ranked.Count() - 1
        x = CreateObject("roUrlTransfer")
        x.SetMessagePort(port)
        x.SetUrl(Plex_url(ranked[i].url, "/identity"))
        if LCase(Left(ranked[i].url, 6)) = "https:" then
            x.SetCertificatesFile("common:/certs/ca-bundle.crt")
            x.InitClientCertificates()
        end if
        h = Plex_headers(invalid, clientID)
        for each k in h
            x.AddHeader(k, h[k])
        end for
        x.AsyncGetToString()
        xfers.Push(x)
    end for
    best = -1
    pendingN = ranked.Count()
    deadline = UpTime(0) + 4
    while pendingN > 0 and best <> 0
        ms = Int((deadline - UpTime(0)) * 1000)
        if ms <= 0 then exit while
        msg = Wait(ms, port)
        if msg = invalid then exit while
        if type(msg) = "roUrlEvent" then
            pendingN = pendingN - 1
            idx = -1
            for i = 0 to xfers.Count() - 1
                if xfers[i].GetIdentity() = msg.GetSourceIdentity() then idx = i
            end for
            if idx >= 0 and msg.GetResponseCode() = 200 then
                j = ParseJson(msg.GetString())
                if j <> invalid and j.MediaContainer <> invalid and j.MediaContainer.machineIdentifier = machineID then
                    if best < 0 or idx < best then best = idx
                end if
            end if
        end if
    end while
    for each x in xfers
        x.AsyncCancel()
    end for
    if best < 0 then return invalid
    return ranked[best].url
end function

' Every server on the account that answers. A shared server's own access token, never the account's.
function Plex_servers(token as String, clientID as String) as Object
    r = Plex_resources(token, clientID)
    if not r.ok then return r
    out = []
    if type(r.value) <> "roArray" then return {ok: true, value: out}
    for each res in r.value
        if Plex_isServer(res) and res.accessToken <> invalid and res.clientIdentifier <> invalid then
            addresses = Plex_ranked(res)
            uri = Plex_bestAddress(addresses, res.clientIdentifier, clientID)
            if uri <> invalid then
                name = res.name
                if name = invalid then name = "Plex"
                out.Push({id: res.clientIdentifier, name: name, baseURL: uri, accessToken: res.accessToken, addresses: addresses})
            end if
        end if
    end for
    return {ok: true, value: out}
end function

' The account's server a typed address names: its /identity (asked without a token) gives the machine, plex.tv must
' list that machine on this account, and the link goes to whichever address plex.tv lists for it answers as that machine.
' Fails with kind "noServer", "notOnAccount" or "unreachable" (the web's AddressError).
function Plex_serverAt(at as String, token as String, clientID as String) as Object
    r = Http_json("GET", Plex_url(at, "/identity"), Plex_headers(invalid, clientID), invalid, 8)
    id = invalid
    if r.ok and r.value.MediaContainer <> invalid then id = r.value.MediaContainer.machineIdentifier
    if id = invalid then return Http_fail("noServer", "No Plex server answered there.")
    res = Plex_resources(token, clientID)
    if not res.ok then return res
    found = invalid
    if type(res.value) = "roArray" then
        for each x in res.value
            if Plex_isServer(x) and x.clientIdentifier = id then found = x
        end for
    end if
    if found = invalid or found.accessToken = invalid then return Http_fail("notOnAccount", "That server isn’t on this Plex account.")
    known = Plex_ranked(found)
    best = Plex_bestAddress(known, id, clientID)
    if best = invalid then return Http_fail("unreachable", "No address answered.")
    name = found.name
    if name = invalid then name = "Plex"
    return {ok: true, value: {id: id, name: name, baseURL: best, accessToken: found.accessToken, addresses: known}}
end function

' ---- Plex Media Server ----

function Plex_get(s as Object, path as String, query = [] as Object, extra = invalid as Dynamic) as Object
    h = Plex_headers(s.token, s.deviceID)
    if extra <> invalid then h.Append(extra)
    return Http_json("GET", Plex_url(s.baseURL, path, query), h)
end function

function Plex_sections(s as Object) as Object
    r = Plex_get(s, "/library/sections")
    if not r.ok then return r
    dirs = []
    mc = r.value.MediaContainer
    if mc <> invalid and type(mc.Directory) = "roArray" then
        for each d in mc.Directory
            if d.key <> invalid and d.type <> invalid then dirs.Push(d)
        end for
    end if
    return {ok: true, value: dirs}
end function

' The server's libraries: [{id, title, kind, itemCount}]; counts (one zero-size page each) only when asked for.
function Plex_libraries(s as Object, withCounts as Boolean) as Object
    r = Plex_sections(s)
    if not r.ok then return r
    out = []
    for each d in r.value
        kind = "other"
        if d.type = "movie" then kind = "movies"
        if d.type = "show" then kind = "shows"
        count = invalid
        if withCounts then
            c = Plex_get(s, "/library/sections/" + d.key + "/all", [], {"X-Plex-Container-Start": "0", "X-Plex-Container-Size": "0"})
            if c.ok and c.value.MediaContainer <> invalid then count = c.value.MediaContainer.totalSize
        end if
        title = d.title
        if title = invalid then title = d.key
        out.Push({id: d.key, title: title, kind: kind, itemCount: count})
    end for
    return {ok: true, value: out}
end function

' One page of a section's items of `type` (1 movie, 2 show, 4 episode), without the Media subtree.
function Plex_page(s as Object, key as String, typ as Integer, start as Integer, size = 500 as Integer) as Object
    r = Plex_get(s, "/library/sections/" + key + "/all", [["type", iStr(typ)], ["excludeElements", "Media"]], {"X-Plex-Container-Start": iStr(start), "X-Plex-Container-Size": iStr(size)})
    if not r.ok then return r
    mc = r.value.MediaContainer
    items = []
    total = 0
    if mc <> invalid then
        if type(mc.Metadata) = "roArray" then items = mc.Metadata
        if mc.totalSize <> invalid then total = mc.totalSize
    end if
    return {ok: true, value: {items: items, total: total}}
end function

' Every item of `type` in a section, 500 at a time, in page order.
function Plex_all(s as Object, key as String, typ as Integer) as Object
    first = Plex_page(s, key, typ, 0)
    if not first.ok then return first
    out = []
    out.Append(first.value.items)
    start = 500
    total = first.value.total
    if total > 2000000 then total = 2000000   ' a bad server can't make it page without end
    while start < total and first.value.items.Count() > 0
        p = Plex_page(s, key, typ, start)
        if not p.ok then return p
        out.Append(p.value.items)
        start = start + 500
    end while
    return {ok: true, value: out}
end function

function Plex_tags(o as Object, key as String) as Object
    out = []
    if type(o[key]) = "roArray" then
        for each t in o[key]
            if t.tag <> invalid then out.Push(t.tag)
        end for
    end if
    return out
end function

' Every movie and episode in `sections` (invalid = every movie and TV section), in section order.
function Plex_libraryItems(s as Object, sections as Dynamic) as Object
    dirs = []
    if sections = invalid then
        r = Plex_sections(s)
        if not r.ok then return r
        for each d in r.value
            if d.type = "movie" or d.type = "show" then dirs.Push({key: d.key, type: d.type})
        end for
    else
        for each sec in sections
            if sec.kind = "movies" then dirs.Push({key: sec.id, type: "movie"})
            if sec.kind = "shows" then dirs.Push({key: sec.id, type: "show"})
        end for
    end if
    out = []
    for each d in dirs
        if d.type = "movie" then
            r = Plex_all(s, d.key, 1)
            if not r.ok then return r
            for each mt in r.value
                it = Plex_movie(mt, d.key)
                if it <> invalid then out.Push(it)
            end for
        else
            ' Genres, cast, rating and the blurb live on the show, not the episode: joined on grandparentRatingKey.
            shows = Plex_all(s, d.key, 2)
            if not shows.ok then return shows
            byKey = newMap()
            for each sh in shows.value
                if sh.ratingKey <> invalid and byKey[sh.ratingKey] = invalid then byKey[sh.ratingKey] = sh
            end for
            eps = Plex_all(s, d.key, 4)
            if not eps.ok then return eps
            for each e in eps.value
                show = invalid
                if e.grandparentRatingKey <> invalid then show = byKey[e.grandparentRatingKey]
                it = Plex_episode(e, show, d.key)
                if it <> invalid then out.Push(it)
            end for
        end if
    end for
    return {ok: true, value: out}
end function

function Plex_runtime(o as Object) as Dynamic
    if o.duration = invalid or o.duration <= 0 then return invalid
    return o.duration / 1000#
end function

function Plex_movie(o as Object, section as String) as Dynamic
    runtime = Plex_runtime(o)
    if runtime = invalid or o.ratingKey = invalid then return invalid
    title = o.title
    if title = invalid then title = "Untitled"
    added = invalid
    if o.addedAt <> invalid then added = o.addedAt * 1#
    viewCount = o.viewCount
    if viewCount = invalid then viewCount = 0
    return MediaItem_new({id: o.ratingKey, kind: "movie", title: MediaItem_title(title, o.editionTitle), year: o.year,
        genres: Plex_tags(o, "Genre"), runtime: runtime, artworkPath: o.thumb, backdropPath: o.art, overview: o.summary,
        contentRating: o.contentRating, directors: Plex_tags(o, "Director"), actors: prefix(Plex_tags(o, "Role"), 6),
        libraryID: section, addedAt: added, watched: viewCount > 0})
end function

function Plex_episode(e as Object, show as Dynamic, section as String) as Dynamic
    runtime = Plex_runtime(e)
    if runtime = invalid or e.ratingKey = invalid then return invalid
    title = e.title
    if title = invalid then title = "Untitled"
    genres = []
    directors = []
    actors = []
    rating = invalid
    if show <> invalid then
        genres = Plex_tags(show, "Genre")
        directors = Plex_tags(show, "Director")
        actors = prefix(Plex_tags(show, "Role"), 6)
        rating = show.contentRating
    end if
    art = e.grandparentThumb
    if art = invalid then art = e.thumb
    wide = e.grandparentArt
    if wide = invalid then wide = e.art
    added = invalid
    if e.addedAt <> invalid then added = e.addedAt * 1#
    viewCount = e.viewCount
    if viewCount = invalid then viewCount = 0
    return MediaItem_new({id: e.ratingKey, kind: "episode", title: title, seriesTitle: e.grandparentTitle,
        seriesID: e.grandparentRatingKey, season: e.parentIndex, episode: e.index, year: e.year, genres: genres,
        runtime: runtime, artworkPath: art, backdropPath: wide, overview: e.summary, contentRating: rating,
        directors: directors, actors: actors, libraryID: section, addedAt: added, watched: viewCount > 0})
end function

' The universal transcoder's fMP4 HLS for a rating key, starting at 0 (the player starts at the offset itself). The
' session id is stable per device and purpose, so a reload replaces the old transcode instead of adding one. The guide's
' muted preview is capped at 720p / 4 Mbps.
function Plex_playbackSource(s as Object, ratingKey as String, session as String) as Object
    profile = "add-transcode-target(type=videoProfile&context=streaming&protocol=hls&container=mp4&videoCodec=" + Http_videoCodecs() + "&audioCodec=" + Http_audioCodecs() + ")"
    cap = s.maxBitrateKbps
    if session = "preview" and (cap <= 0 or cap > 4000) then cap = 4000
    query = [["path", "/library/metadata/" + ratingKey], ["mediaIndex", "0"], ["partIndex", "0"], ["protocol", "hls"],
        ["directPlay", "0"], ["directStream", "1"], ["fastSeek", "1"], ["offset", "0"], ["session", s.deviceID + "-" + session],
        ["X-Plex-Client-Identifier", s.deviceID], ["X-Plex-Token", s.token], ["X-Plex-Platform", "Roku"],
        ["X-Plex-Product", "Rerun Guide"], ["X-Plex-Version", "1.0"], ["X-Plex-Client-Profile-Extra", profile]]
    if cap > 0 then
        query.Push(["maxVideoBitrate", iStr(cap)])
        if cap <= 4000 then query.Push(["videoResolution", "1280x720"]) else query.Push(["videoResolution", "1920x1080"])
    end if
    ' PMS 1.43 can answer start.m3u8 with 400 unless this client asked for a decision first, as every official client does.
    Http_send("GET", Plex_url(s.baseURL, "/video/:/transcode/universal/decision", query), {}, invalid, 10)
    return {ok: true, value: {url: Plex_url(s.baseURL, "/video/:/transcode/universal/start.m3u8", query), startsAtOffset: false, format: "hls"}}
end function

function Plex_stopPlayback(s as Object, session as String) as Object
    Http_send("GET", Plex_url(s.baseURL, "/video/:/transcode/universal/stop", [["session", s.deviceID + "-" + session]]), Plex_headers(s.token, s.deviceID), invalid, 10)
    return {ok: true, value: invalid}
end function

' Plex's own "mark as played".
function Plex_markWatched(s as Object, item as Object) as Object
    return Http_send("PUT", Plex_url(s.baseURL, "/:/scrobble", [["identifier", "com.plexapp.plugins.library"], ["key", item.id]]), Plex_headers(s.token, s.deviceID), "")
end function
