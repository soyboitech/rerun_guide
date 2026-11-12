' Port of web/src/core/JellyfinClient.ts and EmbyConnect.ts for ServerTask. Emby and Jellyfin share one client; s.kind
' selects the few places they differ. Sign-in returns {baseURL, token, userID, serverName}.
' Not on Roku yet: track selection (Audio and Subtitles), trailers, recently added.

function JF_base(url as String) as String
    b = url
    while Right(b, 1) = "/"
        b = Left(b, Len(b) - 1)
    end while
    return b
end function

' MediaBrowser auth on every request: Jellyfin reads Authorization, Emby X-Emby-Authorization and X-Emby-Token.
function JF_headers(token as String, devID as String, json = false as Boolean) as Object
    auth = "MediaBrowser Client=" + Chr(34) + "Rerun Guide" + Chr(34) + ", Device=" + Chr(34) + Http_deviceName() + Chr(34) + ", DeviceId=" + Chr(34) + devID + Chr(34) + ", Version=" + Chr(34) + "1.0" + Chr(34)
    h = {}
    if token <> "" then
        auth = auth + ", Token=" + Chr(34) + token + Chr(34)
        h["X-Emby-Token"] = token
    end if
    h["Authorization"] = auth
    h["X-Emby-Authorization"] = auth
    h["Accept"] = "application/json"
    if json then h["Content-Type"] = "application/json"
    return h
end function

' Query keys in Swift order (uppercase before lowercase), so every platform sends the same URL.
function JF_url(base as String, path as String, query as Object) as String
    keys = []
    for each k in query
        keys.Push(k)
    end for
    pairs = []
    for each k in stableSort(keys, JF_byName)
        pairs.Push([k, query[k]])
    end for
    return JF_base(base) + path + Http_query(pairs)
end function

function JF_byName(a as String, b as String, ctx as Dynamic) as Integer
    return swiftCompare(a, b)
end function

function JF_query() as Object
    q = {}
    q.SetModeCaseSensitive()
    return q
end function

function JF_request(s as Object, method as String, path as String, query as Object, body = invalid as Dynamic, timeoutSeconds = 30 as Integer) as Object
    return Http_json(method, JF_url(s.baseURL, path, query), JF_headers(s.token, s.deviceID, body <> invalid), body, timeoutSeconds)
end function

' ---- Sign-in ----

' Auth result to a client, named after the server when it will say.
function JF_signedIn(base as String, devID as String, a as Object) as Object
    if a.AccessToken = invalid or a.User = invalid or a.User.Id = invalid then return Http_fail("invalid", "The data couldn’t be read because it isn’t in the correct format.")
    name = ""
    info = Http_json("GET", JF_base(base) + "/System/Info/Public", JF_headers("", devID), invalid, 10)
    if info.ok and info.value.ServerName <> invalid then name = info.value.ServerName
    if name = "" then
        name = Http_host(base)
        if name = invalid then name = "Server"
    end if
    return {ok: true, value: {baseURL: JF_base(base), token: a.AccessToken, userID: a.User.Id, serverName: name}}
end function

' Where a sign-in goes: `base` with https in place of http when a server answers there (port 443 when no port was typed,
' the typed port otherwise), else `base` as given. A typed address with no scheme is taken as http (normalizedAddress),
' and the password or the Quick Connect secret must not cross in the clear, or be lost to a proxy's redirect (a 405),
' when the server has TLS. The question is /System/Info/Public, asked without a token.
' ponytail: that address only (an http side that redirects to another name or path is not followed), and asked on every
' attempt: remember the answer if a port that swallows the question (a firewall that drops 443; a server's plain port
' refuses a TLS hello at once) makes each try wait out the 4 seconds.
' Only at sign-in: a link saved earlier keeps its scheme until the viewer signs out and in, and the addresses an Emby
' Connect account lists are used as listed. An http:// typed on purpose is asked too; typing the port (host:80) stays
' on http.
' ponytail (Roku only): roUrlTransfer follows redirects by itself and has no switch for it, so an https side that only
' redirects (back to http, or to another name) still counts as answering here and the sign-in then fails at it. The
' other ports ask with redirects off; look for a way to see the hop on a device before changing this.
function JF_secureBase(base as String, devID as String) as String
    if LCase(Left(base, 7)) <> "http://" then return base
    https = "https://" + Mid(base, 8)
    probe = Http_json("GET", JF_base(https) + "/System/Info/Public", JF_headers("", devID), invalid, 4)
    if not probe.ok then return base
    if type(probe.value) <> "roAssociativeArray" then return base
    id = probe.value.Lookup("Id")   ' the exact key; a dot lookup would take "id" too
    if type(id) <> "roString" and type(id) <> "String" then return base
    return https
end function

function JF_login(base as String, username as String, password as String, devID as String) as Object
    base = JF_secureBase(base, devID)
    r = Http_json("POST", JF_base(base) + "/Users/AuthenticateByName", JF_headers("", devID, true), FormatJson({Username: username, Pw: password}))
    if not r.ok then return r
    return JF_signedIn(base, devID, r.value)
end function

' Jellyfin Quick Connect: {code, secret, baseURL}; baseURL is where the code was made, and so where to ask about it and sign in with it.
function JF_quickConnectStart(base as String, devID as String) as Object
    base = JF_secureBase(base, devID)
    e = Http_json("GET", JF_base(base) + "/QuickConnect/Enabled", JF_headers("", devID))
    if not e.ok then return e
    if e.value <> true then return Http_fail("notFound", "Not found: Quick Connect")
    r = Http_json("POST", JF_base(base) + "/QuickConnect/Initiate", JF_headers("", devID), "")
    if not r.ok and r.kind = "http" and r.code = 405 then r = Http_json("GET", JF_base(base) + "/QuickConnect/Initiate", JF_headers("", devID))   ' 10.8 routes GET only
    if not r.ok then return r
    if r.value.Code = invalid or r.value.Secret = invalid then return Http_fail("invalid", "The data couldn’t be read because it isn’t in the correct format.")
    return {ok: true, value: {code: r.value.Code, secret: r.value.Secret, baseURL: JF_base(base)}}
end function

' true once approved, invalid (keep waiting) before; notFound once the code has expired.
function JF_quickConnectCheck(base as String, secret as String, devID as String) as Object
    r = Http_json("GET", JF_base(base) + "/QuickConnect/Connect" + Http_query([["secret", secret]]), JF_headers("", devID))
    if not r.ok then
        if r.kind = "http" and r.code = 404 then return Http_fail("notFound", "Not found: Quick Connect code (expired)")
        return r
    end if
    if r.value.Authenticated = true then return {ok: true, value: true}
    return {ok: true, value: invalid}
end function

function JF_quickConnectLogin(base as String, secret as String, devID as String) as Object
    r = Http_json("POST", JF_base(base) + "/Users/AuthenticateWithQuickConnect", JF_headers("", devID, true), FormatJson({Secret: secret}))
    if not r.ok then return r
    return JF_signedIn(base, devID, r.value)
end function

' Emby Connect: trade a server's Connect access key for a local sign-in, its addresses in order, LAN first. A LAN address
' gets the key only if its /System/Info/Public, asked without a token, names this server.
function JF_connectExchange(server as Object, connectUserID as String, devID as String) as Object
    addresses = server.addresses
    if type(addresses) <> "roArray" or addresses.Count() = 0 then addresses = [{url: server.baseURL, local: false}]
    last = Http_fail("notFound", "Not found: an address for " + server.name)
    answered = invalid   ' a server's own refusal says more than another address timing out
    for each a in addresses
        ok = true
        if isTrue(a.local) then
            probe = Http_json("GET", JF_base(a.url) + "/System/Info/Public", JF_headers("", devID), invalid, 4)
            ok = probe.ok and probe.value.Id = server.id
        end if
        if ok then
            timeout = 10
            if isTrue(a.local) then timeout = 4
            q = JF_query()
            q.format = "json"
            q["ConnectUserId"] = connectUserID
            r = Http_json("GET", JF_url(a.url, "/Connect/Exchange", q), JF_headers(server.accessToken, devID), invalid, timeout)
            if r.ok and r.value.LocalUserId <> invalid and r.value.AccessToken <> invalid then
                return {ok: true, value: {baseURL: JF_base(a.url), token: r.value.AccessToken, userID: r.value.LocalUserId, serverName: server.name}}
            end if
            if r.ok then r = Http_fail("invalid", "The data couldn’t be read because it isn’t in the correct format.")
            if r.kind = "unreachable" then last = r else if answered = invalid then answered = r
        end if
    end for
    if answered <> invalid then return answered
    return last
end function

' ---- Library ----

function JF_libraries(s as Object, withCounts as Boolean) as Object
    r = JF_request(s, "GET", "/Users/" + s.userID + "/Views", JF_query())
    if not r.ok then return r
    out = []
    if type(r.value.Items) <> "roArray" then return {ok: true, value: out}
    for each v in r.value.Items
        if v.Id <> invalid then
            kind = "other"
            if v.CollectionType = "movies" then kind = "movies"
            if v.CollectionType = "tvshows" then kind = "shows"
            count = invalid
            if withCounts then
                q = JF_query()
                q["ParentId"] = v.Id
                q["Recursive"] = "true"
                q["IncludeItemTypes"] = "Movie,Series"
                q["IsMissing"] = "false"
                q["Limit"] = "1"
                c = JF_request(s, "GET", "/Users/" + s.userID + "/Items", q)
                if c.ok then count = c.value.TotalRecordCount
            end if
            name = v.Name
            if name = invalid then name = ""
            out.Push({id: v.Id, title: name, kind: kind, itemCount: count})
        end if
    end for
    return {ok: true, value: out}
end function

' Pages through /Users/{id}/Items, optionally under one view, 500 at a time.
function JF_items(s as Object, types as String, fields as String, parent as Dynamic) as Object
    all = []
    while true
        q = JF_query()
        q["Recursive"] = "true"
        q["IncludeItemTypes"] = types
        q["IsMissing"] = "false"
        q["SortBy"] = "SortName"
        q["Fields"] = fields
        q["StartIndex"] = iStr(all.Count())
        q["Limit"] = "500"
        if parent <> invalid then q["ParentId"] = parent
        r = JF_request(s, "GET", "/Users/" + s.userID + "/Items", q)
        if not r.ok then return r
        items = r.value.Items
        if type(items) <> "roArray" then items = []
        all.Append(items)
        total = r.value.TotalRecordCount
        if total = invalid then total = 0
        if items.Count() = 0 or all.Count() >= total then exit while
    end while
    return {ok: true, value: all}
end function

function JF_people(i as Dynamic, kind as String) as Object
    out = []
    if i = invalid or type(i.People) <> "roArray" then return out
    for each p in i.People
        if p.Type = kind and p.Name <> invalid then out.Push(p.Name)
    end for
    return out
end function

function JF_or(a as Dynamic, b as Dynamic) as Dynamic
    if a = invalid then return b
    t = type(a)
    if t = "roArray" then
        if a.Count() > 0 then return a
        return b
    end if
    if t = "String" or t = "roString" then
        if a <> "" then return a
        return b
    end if
    return a
end function

function JF_hasBackdrop(i as Dynamic) as Boolean
    return i <> invalid and type(i.BackdropImageTags) = "roArray" and i.BackdropImageTags.Count() > 0
end function

function JF_mediaItem(i as Object, series as Object, parent as Dynamic) as Dynamic
    ticks = i.RunTimeTicks
    if ticks = invalid or ticks <= 0 or i.Id = invalid or i.Type = invalid then return invalid
    isEpisode = i.Type = "Episode"
    show = invalid
    if isEpisode and i.SeriesId <> invalid then show = series[i.SeriesId]
    own = invalid
    if type(i.ImageTags) = "roAssociativeArray" and i.ImageTags.Primary <> invalid then own = "Items/" + i.Id + "/Images/Primary"
    art = own
    if isEpisode and i.SeriesPrimaryImageTag <> invalid and i.SeriesId <> invalid then art = "Items/" + i.SeriesId + "/Images/Primary"
    parentBackdrop = i.ParentBackdropItemId
    if parentBackdrop = invalid then parentBackdrop = i.SeriesId
    wide = invalid
    if JF_hasBackdrop(i) then
        wide = "Items/" + i.Id + "/Images/Backdrop/0"
    else if type(i.ParentBackdropImageTags) = "roArray" and i.ParentBackdropImageTags.Count() > 0 and parentBackdrop <> invalid then
        wide = "Items/" + parentBackdrop + "/Images/Backdrop/0"
    else if show <> invalid and JF_hasBackdrop(show) then
        wide = "Items/" + show.Id + "/Images/Backdrop/0"
    end if
    name = i.Name
    if name = invalid then name = ""
    if isEpisode then
        title = name
        kind = "episode"
    else
        title = MediaItem_title(name, JF_edition(i.Path))
        kind = "movie"
    end if
    showGenres = invalid
    showRating = invalid
    if show <> invalid then
        showGenres = show.Genres
        showRating = show.OfficialRating
    end if
    genres = JF_or(showGenres, i.Genres)
    if genres = invalid then genres = []
    directors = JF_or(JF_people(i, "Director"), JF_people(show, "Director"))
    actors = prefix(JF_or(JF_people(i, "Actor"), JF_people(show, "Actor")), 6)
    played = false
    if type(i.UserData) = "roAssociativeArray" then played = i.UserData.Played = true
    return MediaItem_new({id: i.Id, kind: kind, title: title, seriesTitle: i.SeriesName, seriesID: i.SeriesId,
        season: i.ParentIndexNumber, episode: i.IndexNumber, year: i.ProductionYear, genres: genres,
        runtime: ticks / 10000000#, artworkPath: art, backdropPath: wide, overview: JF_or(i.Overview, invalid),
        contentRating: JF_or(i.OfficialRating, showRating), directors: directors, actors: actors, libraryID: parent,
        addedAt: Http_isoSeconds(i.DateCreated), watched: played})
end function

' The cut named in a file path, Plex style: "Watchmen (2009) {edition-Directors Cut}.mkv".
function JF_edition(path as Dynamic) as Dynamic
    if path = invalid then return invalid
    r = CreateObject("roRegex", "\{edition-([^}]+)\}", "").Match(path)
    if r.Count() < 2 then return invalid
    return r[1]
end function

' Every movie and episode in `sectionIDs` (invalid = every library), episodes inheriting genres, people and rating from
' their series.
function JF_libraryItems(s as Object, sectionIDs as Dynamic) as Object
    sr = JF_items(s, "Series", "Genres,People,OfficialRating", invalid)
    if not sr.ok then return sr
    series = newMap()
    for each x in sr.value
        if x.Id <> invalid and series[x.Id] = invalid then series[x.Id] = x
    end for
    parents = [invalid]
    if sectionIDs <> invalid then parents = sectionIDs
    fetches = [["Movie", "Genres,People,Overview,ProductionYear,OfficialRating,DateCreated,Path"], ["Episode", "Overview,SeriesPrimaryImage,ProductionYear,OfficialRating,DateCreated"]]
    out = []
    for each parent in parents
        for each f in fetches
            r = JF_items(s, f[0], f[1], parent)
            if not r.ok then return r
            for each i in r.value
                it = JF_mediaItem(i, series, parent)
                if it <> invalid then out.Push(it)
            end for
        end for
    end for
    return {ok: true, value: out}
end function

' ---- Playback ----

' The TV-player-shaped profile: mp4/mov direct play only; everything else HLS (fMP4 first, TS h264 as the fallback).
function JF_deviceProfile(maxBitrate as LongInteger) as Object
    hls = []
    for each p in [["mp4", Http_videoCodecs()], ["ts", "h264"]]
        hls.Push({Type: "Video", Container: p[0], Protocol: "hls", VideoCodec: p[1], AudioCodec: Http_audioCodecs(), Context: "Streaming",
                  MinSegments: 2, BreakOnNonKeyFrames: true, MaxAudioChannels: "6"})
    end for
    return {MaxStreamingBitrate: maxBitrate,
            DirectPlayProfiles: [{Type: "Video", Container: "mp4,m4v,mov", VideoCodec: Http_videoCodecs(), AudioCodec: "aac,ac3,eac3,alac,flac"}],
            TranscodingProfiles: hls, CodecProfiles: [], SubtitleProfiles: []}
end function

' What the player loads for `itemID` from `offset` in: {url, startsAtOffset: false (the player starts at the offset),
' format, playSessionId}. `stopID` is the PlaySessionId the last load for this session started, stopped first. The
' subtitle is always asked for by index, -1 for none, or the server applies the account's remembered one (burned in).
function JF_playbackSource(s as Object, itemID as String, offset as Double, session as String, stopID as Dynamic) as Object
    if stopID <> invalid then JF_stopPlayback(s, stopID)
    kbps = s.maxBitrateKbps
    if kbps <= 0 then kbps = 120000
    if session = "preview" and kbps > 4000 then kbps = 4000
    bits = kbps * 1000&
    ticks = Int(offset) * 10000000&
    q = JF_query()
    q["UserId"] = s.userID
    q["StartTimeTicks"] = ticks.ToStr()
    q["MaxStreamingBitrate"] = bits.ToStr()
    q["EnableDirectPlay"] = "true"
    q["EnableDirectStream"] = "true"
    q["EnableTranscoding"] = "true"
    q["SubtitleStreamIndex"] = "-1"
    ' Emby only honours the stream indexes beside the MediaSourceId.
    src = JF_request(s, "GET", "/Users/" + s.userID + "/Items/" + itemID, {Fields: "MediaSources"})
    if src.ok and type(src.value.MediaSources) = "roArray" and src.value.MediaSources.Count() > 0 then
        if src.value.MediaSources[0].Id <> invalid then q["MediaSourceId"] = src.value.MediaSources[0].Id
    end if
    body = {UserId: s.userID, DeviceProfile: JF_deviceProfile(bits), StartTimeTicks: ticks, MaxStreamingBitrate: bits,
            EnableDirectPlay: true, EnableDirectStream: true, EnableTranscoding: true, AutoOpenLiveStream: true,
            AllowVideoStreamCopy: true, AllowAudioStreamCopy: true, SubtitleStreamIndex: -1}
    r = JF_request(s, "POST", "/Items/" + itemID + "/PlaybackInfo", q, FormatJson(body))
    if not r.ok then return r
    sources = r.value.MediaSources
    if type(sources) <> "roArray" or sources.Count() = 0 then return Http_fail("invalid", "Unexpected response: no MediaSources for " + itemID)
    m0 = sources[0]
    play = r.value.PlaySessionId
    if m0.SupportsDirectPlay = true or (m0.TranscodingUrl = invalid and m0.SupportsDirectStream = true) then
        dq = JF_query()
        dq["Static"] = "true"
        dq["MediaSourceId"] = m0.Id
        dq["DeviceId"] = s.deviceID
        dq.api_key = s.token
        return {ok: true, value: {url: JF_url(s.baseURL, "/Videos/" + itemID + "/stream", dq), startsAtOffset: false, format: "mp4", playSessionId: play}}
    end if
    path = m0.TranscodingUrl
    if path = invalid then return Http_fail("invalid", "Unexpected response: no playable source for " + itemID)
    if Left(path, 1) <> "/" then path = "/" + path
    ' Emby restarts an fMP4 encoder mid-play with timestamps from 0 and no discontinuity: TS segments keep them.
    if s.kind = "emby" then path = path.Replace("SegmentContainer=mp4", "SegmentContainer=ts")
    lower = LCase(path)
    if Instr(1, lower, "api_key=") = 0 and Instr(1, lower, "apikey=") = 0 then
        if Instr(1, path, "?") > 0 then path = path + "&" else path = path + "?"
        path = path + "api_key=" + s.token
    end if
    return {ok: true, value: {url: JF_base(s.baseURL) + path, startsAtOffset: false, format: "hls", playSessionId: play}}
end function

' Best-effort kill of a transcode (Jellyfin requires the PlaySessionId, Emby accepts it).
function JF_stopPlayback(s as Object, playSessionID as Dynamic) as Object
    if playSessionID = invalid then return {ok: true, value: invalid}
    q = JF_query()
    q["DeviceId"] = s.deviceID
    q["PlaySessionId"] = playSessionID
    Http_send("DELETE", JF_url(s.baseURL, "/Videos/ActiveEncodings", q), JF_headers(s.token, s.deviceID), "", 10)
    return {ok: true, value: invalid}
end function

' Both servers' "mark played" for this user.
function JF_markWatched(s as Object, item as Object) as Object
    return Http_send("POST", JF_base(s.baseURL) + "/Users/" + s.userID + "/PlayedItems/" + item.id, JF_headers(s.token, s.deviceID), "")
end function

' ---- Emby Connect (EmbyConnect.ts): the PIN typed at emby.media/pin, and the account's servers ----

function EC_request(path as String, query as Object, form as Dynamic, userToken = invalid as Dynamic) as Object
    h = {}
    h["X-Application"] = "RerunGuide/1.0"
    h["Accept"] = "application/json"
    if userToken <> invalid then h["X-Connect-UserToken"] = userToken
    url = "https://connect.emby.media/service/" + path + Http_query(query)
    if form = invalid then return Http_json("GET", url, h, invalid, 20)
    h["Content-Type"] = "application/x-www-form-urlencoded"
    return Http_json("POST", url, h, Mid(Http_query(form), 2), 20)
end function

' A 5-digit code to show: {code, deviceID}.
function EC_requestPIN(devID as String) as Object
    r = EC_request("pin", [["deviceId", devID]], [["deviceId", devID]])
    if not r.ok then return r
    if r.value.Pin = invalid then return Http_fail("invalid", "The data couldn’t be read because it isn’t in the correct format.")
    return {ok: true, value: {code: r.value.Pin, deviceID: devID}}
end function

' The Emby Connect account once the code has been typed ({userID, token}); invalid until then; notFound once expired.
function EC_pollPIN(pin as Object) as Object
    r = EC_request("pin", [["deviceId", pin.deviceID], ["pin", pin.code]], invalid)
    if not r.ok then
        if r.kind = "http" and r.code = 404 then return Http_fail("notFound", "Not found: Emby PIN (expired)")
        return r
    end if
    if r.value.IsExpired = true then return Http_fail("notFound", "Not found: Emby PIN (expired)")
    if r.value.IsConfirmed <> true then return {ok: true, value: invalid}
    a = EC_request("pin/authenticate", [], [["deviceId", pin.deviceID], ["pin", pin.code]])
    if not a.ok then return a
    if a.value.UserId = invalid or a.value.AccessToken = invalid then return Http_fail("invalid", "The data couldn’t be read because it isn’t in the correct format.")
    return {ok: true, value: {userID: a.value.UserId, token: a.value.AccessToken}}
end function

' The servers linked to the account, as server-list rows: accessToken is the server's Connect access key, addresses its
' LAN address first, then its remote one.
function EC_servers(account as Object) as Object
    r = EC_request("servers", [["userId", account.userID]], invalid, account.token)
    if not r.ok then return r
    out = []
    if type(r.value) <> "roArray" then return {ok: true, value: out}
    for each s in r.value
        if s.AccessKey <> invalid and s.AccessKey <> "" and s.SystemId <> invalid then
            addresses = []
            lan = EC_url(s.LocalAddress)
            if lan <> invalid then addresses.Push({url: lan, local: true})
            remote = EC_url(s.Url)
            if remote <> invalid then addresses.Push({url: remote, local: false})
            if addresses.Count() > 0 then
                name = s.Name
                if name = invalid then name = Http_host(addresses[0].url)
                if name = invalid then name = "Emby"
                out.Push({id: s.SystemId, name: name, baseURL: addresses[0].url, accessToken: s.AccessKey, addresses: addresses})
            end if
        end if
    end for
    return {ok: true, value: out}
end function

function EC_url(s as Dynamic) as Dynamic
    if s = invalid then return invalid
    a = JF_base(s.Trim())
    if Http_host(a) = invalid then return invalid
    return a
end function
