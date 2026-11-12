' Port of web/src/app/AppModelOnboarding.ts. First launch: welcome, (address), link or login, libraries, building, wired
' to the real servers: Plex PIN or plex.tv password, Jellyfin Quick Connect or password, Emby PIN (emby.media/pin) or
' password, and the Sample station. Every server step is a request (Server.brs) whose answer comes back to a named
' continuation with the TS closure's captures in `ctx`; a step answered after the viewer moved on (authSerial,
' linkSerial) is dropped.
' Not on Roku yet: finding servers on the network (LAN discovery), and the QR code on the Plex link screen.

' The Welcome cards: Plex, Jellyfin, Emby, then the sample library.
function welcomeCards() as Object
    return [
        ["Plex", "Link this Roku to your Plex account"],
        ["Jellyfin", "Point it at your Jellyfin server"],
        ["Emby", "Link this Roku to your Emby account"],
        ["Sample station", "Take a look with a made-up library"]
    ]
end function

function welcomeTerms() as String
    return "By choosing a service or the Sample station, you agree to the terms of use at rerunguide.tv/terms."
end function

' The manifest's link_codes: 1 (sideloaded builds) shows the Plex and Emby codes and Jellyfin Quick Connect; 0 (a store
' build: certification 2.2 wants sign-in on the device itself) signs in with a password, Plex with plex.tv's.
function linkCodesOn() as Boolean
    return CreateObject("roAppInfo").GetValue("link_codes") <> "0"
end function

' Plex and Emby link an account and then pick one of its servers; Jellyfin's Quick Connect signs in to the typed server.
function linksAccount() as Boolean
    return m.serviceKind <> "jellyfin"
end function

' Focus index of the Continue button on the address screen (field, found servers..., Continue).
function continueIndex() as Integer
    return m.foundServers.Count() + 1
end function

' The link code as boxes: Plex 4 characters, Emby 5 digits, Jellyfin 6.
function linkCodeChars() as Object
    n = 6
    if m.serviceKind = "plex" then n = 4
    if m.serviceKind = "emby" then n = 5
    out = []
    for i = 1 to n
        c = " "
        if m.linkCode <> invalid and i <= Len(m.linkCode) then c = Mid(m.linkCode, i, 1)
        out.Push(c)
    end for
    return out
end function

function buildDone() as Boolean
    return not m.libraryLoading and m.libraryError = invalid and m.builtCount >= m.channels.Count()
end function

' Trim, prepend http:// when there is no scheme, drop a trailing slash.
function normalizedAddress(s as String) as String
    a = s.Trim()
    if a <> "" and Instr(1, a, "://") = 0 then a = "http://" + a
    while Right(a, 1) = "/"
        a = Left(a, Len(a) - 1)
    end while
    return a
end function

' The host of an address, or invalid when it names none.
function hostOf(address as String) as Dynamic
    re = CreateObject("roRegex", "^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:?#]+)", "")
    r = re.Match(address)
    if r.Count() < 2 or r[1] = "" then return invalid
    return r[1]
end function

' ---- Welcome ----

sub pressWelcome(cmd as String)
    ' Plex / Jellyfin / Emby are one row; the Sample station card sits above it.
    if cmd = "up" and m.focusIndex < 3 then
        m.focusIndex = 3
        return
    end if
    if cmd = "down" and m.focusIndex = 3 then
        m.focusIndex = 2
        return
    end if
    if m.focusIndex < 3 and stepFocus(cmd, 3, true) then return
    if cmd <> "select" then return
    m.authError = invalid
    m.foundServers = []
    m.pendingToken = invalid
    kinds = ["plex", "jellyfin", "emby", "demo"]
    picked = kinds[m.focusIndex]
    if picked <> m.serviceKind then m.address = ""   ' a Plex address must not pre-fill the Emby or Jellyfin form
    if m.focusIndex = 0 then
        m.serviceKind = "plex"
        if linkCodesOn() then go("link") else go("login")
    else if m.focusIndex = 1 then
        m.serviceKind = "jellyfin"
        go("address")
    else if m.focusIndex = 2 then
        m.serviceKind = "emby"
        if linkCodesOn() then go("link") else go("address")
    else
        m.serviceKind = "demo"
        connect({kind: "demo", baseURL: "demo://local", name: "Demo library"}, "")
        go("libraries")
    end if
end sub

' ---- Address ----

sub pressAddress(cmd as String)
    ci = continueIndex()
    if stepFocus(cmd, ci + 1) then return
    if cmd = "back" then
        go("welcome")
        m.focusIndex = indexOf(["plex", "jellyfin", "emby"], m.serviceKind)
        if m.focusIndex < 0 then m.focusIndex = 0
        return
    end if
    if cmd <> "select" then return
    i = m.focusIndex
    if i = 0 then
        editText("addr", m.address, invalid)
    else if i < ci then
        s = m.foundServers[i - 1]
        ' A server from the Plex or Emby account carries its access token, so Select connects. A typed one still signs in.
        if m.serviceKind = "plex" and s.accessToken <> "" then
            connectPlex(s, invalid)
            return
        end if
        if m.serviceKind = "emby" and s.accessToken <> "" and m.pendingToken <> invalid then
            m.address = s.baseURL
            connectEmby(s, m.pendingToken)
            return
        end if
        m.address = s.baseURL
        m.focusIndex = ci
    else
        continueFromAddress()
    end if
end sub

sub continueFromAddress()
    m.address = normalizedAddress(m.address)
    if hostOf(m.address) = invalid then
        m.authError = "Enter an address like 192.168.1.20:32400"
        return
    end if
    m.authError = invalid
    if m.serviceKind = "plex" then
        for each s in m.foundServers
            if s.baseURL = m.address and s.accessToken <> "" then
                connectPlex(s, invalid)
                return
            end if
        end for
        ' A typed address goes through the account token, or a plex.tv password first.
        if m.pendingToken = invalid then
            go("login")
            return
        end if
        if m.authBusy then return
        m.authBusy = true
        m.authSerial = m.authSerial + 1
        request("plexServerAt", {url: m.address, account: m.pendingToken}, onPlexServerAt, {serial: m.authSerial, url: m.address, account: m.pendingToken})
    else if m.serviceKind = "jellyfin" then
        if linkCodesOn() then go("link") else go("login")
    else if m.serviceKind = "emby" then
        for each s in m.foundServers
            if s.baseURL = m.address and s.accessToken <> "" and m.pendingToken <> invalid then
                connectEmby(s, m.pendingToken)
                return
            end if
        end for
        go("login")
    else
        go("login")
    end if
end sub

' The account's server a typed Plex address names. No token goes to the address itself: plex.tv's list decides.
sub onPlexServerAt(r as Object, ctx as Object)
    if m.authSerial <> ctx.serial or m.serviceKind <> "plex" or m.pendingToken <> ctx.account then return
    m.authBusy = false
    if r.ok then
        connectPlex(r.value, ctx.account)
        return
    end if
    host = hostOf(ctx.url)
    if host = invalid then host = "that address"
    if r.kind = "noServer" then
        m.authError = "No Plex server answered at " + host + ". Check the address."
    else if r.kind = "notOnAccount" then
        m.authError = host + " is a Plex server, but not one on this Plex account."
    else if r.kind = "unreachable" then
        m.authError = "That’s your server, but no address Plex lists for it answered. On a VPN or proxy? Add it to the server’s Custom server access URLs."
    else if r.kind = "unauthorized" then
        m.pendingToken = invalid
        m.authError = "Plex didn’t accept this sign-in. Sign in again."
    else
        m.authError = r.error
    end if
end sub

' `account`: the plex.tv account token, kept so a server that moves can be found again.
sub connectPlex(s as Object, account as Dynamic)
    a = account
    if a = invalid then a = m.pendingToken
    if a <> invalid then Store_set("plexAccount", a)
    cfg = {kind: "plex", baseURL: s.baseURL, name: s.name, machineID: s.id}
    if s.addresses <> invalid and s.addresses.Count() > 0 then cfg.addresses = s.addresses
    connect(cfg, s.accessToken)
    go("libraries")
end sub

' An Emby Connect server: trade its access key for a sign-in, then pick libraries.
sub connectEmby(s as Object, connectUserID as String)
    if m.authBusy then return
    m.authBusy = true
    m.authError = invalid
    request("embyExchange", {server: s, connectUserID: connectUserID}, onEmbyExchange, {name: s.name})
end sub

sub onEmbyExchange(r as Object, ctx as Object)
    m.authBusy = false
    if m.screen <> "address" and m.screen <> "link" then return
    if not r.ok then
        m.authError = "Couldn’t sign in to " + ctx.name + ": " + r.error
        if m.screen = "link" then m.linked = false
        return
    end if
    c = r.value
    connect({kind: "emby", baseURL: c.baseURL, name: c.serverName, userID: c.userID}, c.token)
    go("libraries")
end sub

' ---- Link (Plex PIN, Emby PIN, Jellyfin Quick Connect) ----

sub startLink()
    cancelLink()
    m.linked = false
    m.linkCode = invalid
    m.authError = invalid
    m.linkPins = 0
    if m.serviceKind = "plex" then
        request("plexRequestPIN", {}, onLinkPIN, {serial: m.linkSerial})
    else if m.serviceKind = "emby" then
        requestEmbyPIN()
    else
        if hostOf(m.address) = invalid then
            m.authError = "Unexpected response: bad server address"
            return
        end if
        request("jfQuickConnectStart", {url: m.address}, onLinkPIN, {serial: m.linkSerial})
    end if
end sub

' Stop the PIN or Quick Connect poll: whatever answers later is dropped.
sub cancelLink()
    if m.linkSerial = invalid then m.linkSerial = 0
    m.linkSerial = m.linkSerial + 1
    cancelTimer("linkPoll")
end sub

function linkLive(ctx as Object) as Boolean
    return ctx.serial = m.linkSerial and m.screen = "link"
end function

sub requestEmbyPIN()
    m.linkPins = m.linkPins + 1
    if m.linkPins > 10 then   ' an expired PIN is replaced by a fresh one, ten at most
        m.authError = "The code expired. Go back and try again."
        return
    end if
    request("embyRequestPIN", {}, onLinkPIN, {serial: m.linkSerial})
end sub

' The code is in (plex.tv PIN, Emby PIN, Quick Connect): show it, and ask every 3 s whether it's been entered.
sub onLinkPIN(r as Object, ctx as Object)
    if not linkLive(ctx) then return
    if not r.ok then
        m.authError = r.error
        return
    end if
    m.linkPin = r.value
    m.linkCode = r.value.code
    later("linkPoll", 3, pollLink)
end sub

sub pollLink()
    ctx = {serial: m.linkSerial}
    if m.serviceKind = "plex" then
        request("plexPollPIN", {pin: m.linkPin}, onLinkPoll, ctx)
    else if m.serviceKind = "emby" then
        request("embyPollPIN", {pin: m.linkPin}, onLinkPoll, ctx)
    else
        request("jfQuickConnectCheck", {url: m.linkPin.baseURL, secret: m.linkPin.secret}, onLinkPoll, ctx)
    end if
end sub

' r.value: the plex.tv token, the Emby Connect account, or Quick Connect's approval; invalid while still waiting.
sub onLinkPoll(r as Object, ctx as Object)
    if not linkLive(ctx) then return
    if not r.ok then
        if m.serviceKind = "emby" and r.kind = "notFound" then   ' the PIN expired: a fresh one
            requestEmbyPIN()
            return
        end if
        m.authError = r.error
        return
    end if
    if r.value = invalid then
        later("linkPoll", 3, pollLink)
        return
    end if
    m.linked = true
    if m.serviceKind = "plex" then
        m.linkAccount = r.value
        request("plexServers", {token: r.value}, onLinkServers, ctx)
    else if m.serviceKind = "emby" then
        m.linkAccount = r.value
        request("embyServers", {account: r.value}, onLinkServers, ctx)
    else
        request("jfQuickConnectLogin", {url: m.linkPin.baseURL, secret: m.linkPin.secret}, onQuickConnectLogin, ctx)
    end if
end sub

sub onLinkServers(r as Object, ctx as Object)
    if not linkLive(ctx) then return
    if not r.ok then
        m.linked = false
        m.authError = r.error
        return
    end if
    servers = r.value
    if m.serviceKind = "plex" then
        token = m.linkAccount
        if servers.Count() = 0 then
            m.linked = false
            m.authError = "This Plex account has no Plex Media Server, and Rerun Guide plays the movies and shows on your server. To look around without one, go back and choose Sample station."
        else if servers.Count() = 1 then
            connectPlex(servers[0], token)
        else   ' land on the first server, not the address field
            m.foundServers = servers
            m.pendingToken = token
            m.address = servers[0].baseURL
            go("address")
            m.focusIndex = 1
        end if
    else
        userID = m.linkAccount.userID
        if servers.Count() = 0 then
            m.linked = false
            m.authError = "No server is linked to that Emby Connect account. In your server’s dashboard, add your Emby Connect email to a user, then try again."
        else if servers.Count() = 1 then
            connectEmby(servers[0], userID)
        else
            m.foundServers = servers
            m.pendingToken = userID
            m.address = servers[0].baseURL
            go("address")
            m.focusIndex = 1
        end if
    end if
end sub

sub onQuickConnectLogin(r as Object, ctx as Object)
    if not linkLive(ctx) then return
    if not r.ok then
        m.authError = r.error
        return
    end if
    c = r.value
    connect({kind: "jellyfin", baseURL: c.baseURL, name: c.serverName, userID: c.userID}, c.token)
    go("libraries")
end sub

sub pressLink(cmd as String)
    if cmd <> "back" and cmd <> "select" then return
    cancelLink()
    la = linksAccount()
    if cmd = "back" then
        if la then
            go("welcome")
            if m.serviceKind = "plex" then m.focusIndex = 0 else m.focusIndex = 2
        else
            go("address")
            m.focusIndex = continueIndex()
        end if
    else
        if la then go("address") else go("login")
    end if
end sub

' ---- Login (plex.tv, Jellyfin or Emby password) ----

sub pressLogin(cmd as String)
    if stepFocus(cmd, 3) then return
    if cmd = "back" then
        if m.serviceKind = "plex" and not linkCodesOn() then
            go("welcome")
            return
        end if
        go("address")
        m.focusIndex = continueIndex()
        return
    end if
    if cmd <> "select" or m.authBusy then return
    if m.focusIndex = 0 then
        editText("user", m.username, invalid)
    else if m.focusIndex = 1 then
        editText("pass", "", invalid)
    else
        signIn()
    end if
end sub

sub signIn()
    m.authBusy = true
    m.authError = invalid
    m.authSerial = m.authSerial + 1
    ctx = {serial: m.authSerial, kind: m.serviceKind}
    if m.serviceKind = "plex" then
        request("plexSignIn", {username: m.username, password: m.password}, onSignIn, ctx)
    else
        if hostOf(m.address) = invalid then
            m.authBusy = false
            m.authError = "Unexpected response: bad server address"
            return
        end if
        request("jfLogin", {url: m.address, username: m.username, password: m.password, kind: m.serviceKind}, onSignIn, ctx)
    end if
end sub

sub onSignIn(r as Object, ctx as Object)
    if m.authSerial <> ctx.serial then return   ' moved on while the server answered
    m.authBusy = false
    if not r.ok then
        if ctx.kind = "plex" and r.kind = "unauthorized" then
            ' plex.tv answers 401 both for bad credentials and for a missing 2FA code.
            m.authError = "Wrong email or password. Two-factor on? Type your password followed by the 6-digit code."
        else
            m.authError = r.error
        end if
        return
    end if
    if ctx.kind = "plex" then
        m.pendingToken = r.value
        if hostOf(m.address) = invalid then   ' no typed address: the account's servers, as after a link code
            m.authBusy = true
            request("plexServers", {token: r.value}, onSignInServers, {serial: m.authSerial, token: r.value})
            return
        end if
        m.authBusy = true
        request("plexServerAt", {url: m.address, account: r.value}, onPlexServerAt, {serial: m.authSerial, url: m.address, account: r.value})
        return
    end if
    c = r.value
    connect({kind: ctx.kind, baseURL: c.baseURL, name: c.serverName, userID: c.userID}, c.token)
    go("libraries")
end sub

' plex.tv's password sign-in found the account's servers: one connects, several are listed.
sub onSignInServers(r as Object, ctx as Object)
    if m.authSerial <> ctx.serial or m.screen <> "login" then return
    m.authBusy = false
    if not r.ok then
        m.authError = r.error
        return
    end if
    servers = r.value
    if servers.Count() = 0 then
        m.authError = "This Plex account has no Plex Media Server, and Rerun Guide plays the movies and shows on your server. To look around without one, go back and choose Sample station."
    else if servers.Count() = 1 then
        connectPlex(servers[0], ctx.token)
    else
        m.foundServers = servers
        m.address = servers[0].baseURL
        go("address")
        m.focusIndex = 1
    end if
end sub

' ---- Libraries ----

' What the rows show before the viewer changes any: the saved choice, else movies and shows (every library on a
' Settings re-pick, where nothing saved means every library).
function libraryPicks(sections as Object) as Object
    picks = newMap()
    ids = m.persisted.selectedLibraryIDs
    if ids <> invalid then
        for each id in ids
            picks[id] = true
        end for
        return picks
    end if
    for each s in sections
        if m.librariesOrigin = "settings" or s.kind <> "other" then picks[s.id] = true
    end for
    return picks
end function

' The Libraries screen came up: ask the server for its libraries.
sub fetchLibraries()
    m.authBusy = true
    m.authError = invalid
    m.librarySelection = libraryPicks(m.librarySections)
    if m.server = invalid then
        m.authBusy = false
        m.authError = "Could not connect to the server."
        return
    end if
    m.librariesSerial = m.authSerial
    serverLibraries(onFetchLibraries, {serial: m.authSerial})
end sub

sub onFetchLibraries(r as Object, ctx as Object)
    if ctx.serial <> m.authSerial or m.screen <> "libraries" then return
    m.authBusy = false
    if not r.ok then
        m.authError = r.error
        return
    end if
    sections = []
    for each s in r.value   ' empty ones (Emby's Collections, Playlists) have nothing to schedule; unknown counts stay
        if s.itemCount = invalid or s.itemCount <> 0 then sections.Push(s)
    end for
    m.librarySections = sections
    m.librarySelection = libraryPicks(sections)
end sub

' Back: a Settings re-pick returns to Settings (saved choice untouched); a Plex or Emby account with other servers still
' in memory returns to the server list; otherwise Welcome is the signed-out state.
sub pressLibraries(cmd as String)
    n = m.librarySections.Count()
    if stepFocus(cmd, n + 1) then return
    if cmd = "back" then
        if m.librariesOrigin = "settings" then
            m.librariesOrigin = invalid
            go("settings")
        else if linksAccount() and m.pendingToken <> invalid and m.foundServers.Count() > 0 then
            token = m.pendingToken
            rows = m.foundServers
            signOut()
            m.pendingToken = token
            m.foundServers = rows
            go("address")
            m.focusIndex = continueIndex()
        else
            signOut()
        end if
        return
    end if
    if cmd <> "select" or m.authBusy or m.server = invalid then return
    if m.authError <> invalid then   ' a list that failed to load keeps the saved choice: Continue builds that
        if m.focusIndex >= n then go("building")
        return
    end if
    if m.focusIndex < n then
        id = m.librarySections[m.focusIndex].id
        if m.librarySelection[id] <> invalid then m.librarySelection.Delete(id) else m.librarySelection[id] = true
    else
        if m.librarySelection.Count() = n then
            m.persisted.selectedLibraryIDs = invalid
        else
            m.persisted.selectedLibraryIDs = keysOf(m.librarySelection)
        end if
        save()
        go("building")
    end if
end sub

' ---- Building ----

' An empty result is not an error: the view offers "Pick other libraries"; libraryError means the load failed (Retry).
sub startBuild()
    m.builtCount = 0
    m.libraryError = invalid
    m.libraryLoading = true
    m.buildSerial = m.libraryGen + 1
    loadLibrary(true, true)
end sub

' The library landed on the Building screen: one tile every 170 ms until every channel is on the board (at most ~4 s).
sub revealBuild()
    if m.screen <> "building" or m.builtCount >= m.channels.Count() then return
    n = m.channels.Count()
    per = n \ 24
    if per < 1 then per = 1
    m.builtCount = m.builtCount + per
    if m.builtCount > n then m.builtCount = n
    later("build", 0.17, revealBuild)
end sub

sub pressBuilding(cmd as String)
    if cmd = "back" then
        m.libraryGen = m.libraryGen + 1   ' the load in flight lands nowhere
        m.libraryLoading = false
        cancelTimer("build")
        if m.librariesOrigin = "settings" then
            m.librariesOrigin = invalid
            go("settings")
        else
            go("libraries")
        end if
        return
    end if
    if cmd <> "select" then return
    if m.libraryError <> invalid then
        startBuild()
        return
    end if
    if not buildDone() then return
    if m.channels.Count() = 0 then
        go("libraries")
        return
    end if
    m.librariesOrigin = invalid
    guideReset()
    go("guide")
    toast("We’re live. Press any arrow to start flipping.")
end sub
