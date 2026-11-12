' Port of web/src/app/OnboardingScreens.tsx (Late Show), simplified to the same copy and flow: Welcome, the server
' address, the link code, the password sign-in, the libraries and the building board.

sub OnboardingView_build(parent as Object)
    t = m.t
    g = {rows: [], cards: [], boxes: [], tiles: []}
    g.root = UI_group(parent)
    UI_poster(g.root, 0, 0, 1080, 748, "pkg:/images/glow.png")
    g.kicker = UI_label(g.root, 96, 96, "", UI_body(26, 700), t.accent, 1500)
    g.title = UI_label(g.root, 96, 140, "", UI_heading(84), t.ink, 1500, "left", 2)
    g.lead = UI_label(g.root, 96, 260, "", UI_body(32), t.mute, 1300, "left", 3)
    g.lead.lineSpacing = 8
    g.error = UI_label(g.root, 96, 960, "", UI_body(28), t.accent, 1728, "left", 2)
    g.footer = UI_label(g.root, 96, 1000, "", UI_body(24), t.dim, 1728)
    m.onboardingView = g
    s = m.screen
    if s = "welcome" then
        OnboardingView_welcomeBuild()
    else if s = "link" then
        OnboardingView_linkBuild()
    else if s = "building" then
        g.board = UI_group(g.root, 96, 420)
    end if
    if s = "libraries" then fetchLibraries()
end sub

sub OnboardingView_update()
    s = m.screen
    if s = "welcome" then
        OnboardingView_welcome()
    else if s = "address" then
        OnboardingView_address()
    else if s = "link" then
        OnboardingView_link()
    else if s = "login" then
        OnboardingView_login()
    else if s = "libraries" then
        OnboardingView_libraries()
    else if s = "building" then
        OnboardingView_building()
    end if
    g = m.onboardingView
    if m.authError <> invalid then g.error.text = m.authError else g.error.text = ""
end sub

' A pool of focusable rows (a box and a label, an optional value on the right) from y down, 96 apart.
sub OnboardingView_rows(labels as Object, values as Object, y as Integer, focus as Integer)
    g = m.onboardingView
    t = m.t
    while g.rows.Count() < labels.Count()
        r = {}
        r.bg = UI_rect(g.root, 96, 0, 1100, 84, t.panel, 24)
        r.label = UI_label(g.root, 132, 0, "", UI_body(32, 600), t.ink, 700)
        r.value = UI_label(g.root, 640, 0, "", UI_body(30), t.dim, 520, "right")
        g.rows.Push(r)
    end while
    for i = 0 to g.rows.Count() - 1
        r = g.rows[i]
        show = i < labels.Count()
        r.bg.visible = show
        r.label.visible = show
        r.value.visible = show
        if show then
            ry = y + i * 96
            r.bg.translation = [96, ry]
            r.label.translation = [132, ry + 22]
            r.value.translation = [640, ry + 24]
            r.label.text = labels[i]
            r.value.text = values[i]
            if i = focus then
                UI_tint(r.bg, t.focusBg)
                r.label.color = t.focusInk
                r.value.color = t.focusDim
            else
                UI_tint(r.bg, t.panel)
                r.label.color = t.ink
                r.value.color = t.dim
            end if
        end if
    end for
end sub

' ---- Welcome ----

sub OnboardingView_welcomeBuild()
    g = m.onboardingView
    t = m.t
    cards = welcomeCards()
    for i = 0 to 3
        c = {}
        if i < 3 then
            x = 96 + i * 588
            y = 640
        else
            x = 96 + 2 * 588
            y = 420
        end if
        c.bg = UI_rect(g.root, x, y, 552, 200, t.panel, 24)
        c.name = UI_label(g.root, x + 40, y + 44, cards[i][0], UI_heading(52, 700), t.ink, 472)
        c.line = UI_label(g.root, x + 40, y + 120, cards[i][1], UI_body(28), t.mute, 472)
        g.cards.Push(c)
    end for
end sub

sub OnboardingView_welcome()
    g = m.onboardingView
    t = m.t
    g.kicker.text = "TONIGHT’S LINEUP."
    g.title.text = "Rerun Guide"
    g.lead.text = "The movies and shows on your server, running to a schedule the way TV used to be. Pick a channel, catch whatever’s playing, change your mind whenever. Nothing to set up on the server side."
    g.lead.width = 1000
    g.footer.text = welcomeTerms()
    for i = 0 to 3
        c = g.cards[i]
        if i = m.focusIndex then
            UI_tint(c.bg, t.focusBg)
            c.name.color = t.focusInk
            c.line.color = t.focusDim
        else
            UI_tint(c.bg, t.panel)
            c.name.color = t.ink
            c.line.color = t.mute
        end if
    end for
end sub

' ---- Address ----

sub OnboardingView_address()
    g = m.onboardingView
    name = serverKindName(m.serviceKind)
    if m.foundServers.Count() > 0 then
        g.kicker.text = UCase("On your " + name + " account")
        g.title.text = "Which server?"
        g.lead.text = "Pick the server your lineup comes from. OK connects."
    else
        g.kicker.text = UCase(name)
        g.title.text = "Where do your shows live?"
        g.lead.text = "Type the address you use on other devices."
    end if
    labels = ["Server address"]
    if m.address = "" then values = ["Press OK to type"] else values = [m.address]
    for each s in m.foundServers
        labels.Push(s.name)
        if s.baseURL = m.address then values.Push("✓ " + hostLabel(s.baseURL)) else values.Push(hostLabel(s.baseURL))
    end for
    if m.authBusy then labels.Push("Connecting…") else labels.Push("Continue")
    values.Push("")
    OnboardingView_rows(labels, values, 400, m.focusIndex)
    g.footer.text = ""
end sub

function hostLabel(url as String) as String
    h = hostOf(url)
    if h = invalid then return url
    return h
end function

' ---- Link ----

sub OnboardingView_linkBuild()
    g = m.onboardingView
    t = m.t
    for i = 0 to 5
        b = {}
        b.bg = UI_rect(g.root, 0, 520, 120, 150, t.panel2, 24)
        b.char = UI_label(g.root, 0, 548, "", UI_heading(96, 700), t.ink, 120, "center")
        g.boxes.Push(b)
    end for
    g.url = UI_label(g.root, 96, 420, "", UI_heading(56, 700), t.accent, 1728)
    g.status = UI_label(g.root, 96, 720, "", UI_body(30), t.mute, 1728)
    g.alt = UI_label(g.root, 96, 860, "", UI_body(28), t.dim, 1728)
end sub

sub OnboardingView_link()
    g = m.onboardingView
    name = serverKindName(m.serviceKind)
    if m.serviceKind = "jellyfin" then
        g.kicker.text = UCase("Jellyfin · " + hostLabel(m.address))
        g.title.text = "Link with Quick Connect"
        g.lead.text = "Open Jellyfin on your phone or computer and sign in. Type in this code. Once it’s approved, we move on."
        g.url.text = "Settings › Quick Connect"
        g.alt.text = "Press OK to sign in with a password instead."
    else
        g.kicker.text = "SIGN IN WITH A CODE"
        g.title.text = "Link your " + name + " account"
        if m.serviceKind = "plex" then
            g.lead.text = "On your phone or computer, open the address below and type in this code. The moment Plex says yes, we move on."
            g.url.text = "plex.tv/link"
        else
            g.lead.text = "On your phone or computer, open the address below. Sign in with Emby Connect and type in this code. Once Emby says yes, we move on."
            g.url.text = "emby.media/pin"
        end if
        g.alt.text = "Press OK to type a server address instead."
    end if
    chars = linkCodeChars()
    n = chars.Count()
    total = n * 120 + (n - 1) * 20
    for i = 0 to 5
        b = g.boxes[i]
        show = i < n
        b.bg.visible = show
        b.char.visible = show
        if show then
            x = 96 + i * 140
            b.bg.translation = [x, 520]
            b.char.translation = [x, 538]
            b.char.text = chars[i]
        end if
    end for
    if m.linked then
        if m.serviceKind = "jellyfin" then
            g.status.text = "Approved. Reading your libraries…"
        else
            g.status.text = "Linked. Looking for your server, which takes 10–15 seconds…"
        end if
    else if m.linkCode = invalid then
        g.status.text = "Getting a code…"
    else
        g.status.text = "Waiting for you to type the code…"
    end if
    g.footer.text = ""
end sub

' ---- Login ----

sub OnboardingView_login()
    g = m.onboardingView
    name = serverKindName(m.serviceKind)
    g.kicker.text = UCase(name)
    g.title.text = "Sign in to " + name
    if m.serviceKind = "plex" then
        g.lead.text = "Use the account you already use for Plex on your other devices. Two-factor enabled? Enter your password followed by the 6-digit code."
    else
        g.lead.text = "Use the account you already use for " + name + " on your other devices."
    end if
    if m.username = "" then user = "Press OK to type" else user = m.username
    pass = "Press OK to type"
    if m.password <> "" then
        pass = ""
        for i = 1 to Len(m.password)
            pass = pass + "•"
        end for
    end if
    if m.authBusy then button = "Signing in…" else button = "Sign in"
    OnboardingView_rows(["Username", "Password", button], [user, pass, ""], 420, m.focusIndex)
    g.footer.text = ""
end sub

' ---- Libraries ----

sub OnboardingView_libraries()
    g = m.onboardingView
    g.kicker.text = UCase("Connected to " + m.server.serverName)
    g.title.text = "What goes in the lineup?"
    g.lead.text = "Pick the libraries Rerun Guide may schedule. You can change this in the Settings any time."
    labels = []
    values = []
    for each s in m.librarySections
        if m.librarySelection[s.id] <> invalid then mark = "✓  " else mark = "    "
        labels.Push(mark + s.title)
        v = ""
        if s.kind = "movies" then v = "Films"
        if s.kind = "shows" then v = "TV"
        if s.itemCount <> invalid then
            if v <> "" then v = v + " · "
            v = v + iStr(s.itemCount)
        end if
        values.Push(v)
    end for
    if m.authBusy then labels.Push("Asking the server…") else labels.Push("Continue")
    values.Push("")
    OnboardingView_rows(labels, values, 400, m.focusIndex)
    g.footer.text = ""
end sub

' ---- Building ----

sub OnboardingView_building()
    g = m.onboardingView
    t = m.t
    server = ""
    if m.server <> invalid then server = m.server.serverName
    if m.libraryError <> invalid then
        g.kicker.text = "BUILDING LINEUP"
        g.title.text = "That didn’t work"
        g.lead.text = m.libraryError + Chr(10) + "Press OK to try again."
    else if not buildDone() then
        g.kicker.text = "BUILDING LINEUP"
        if m.libraryLoading then
            g.title.text = "Configuring channels"
            g.lead.text = "Sorting " + server + " by genre, decade, director and cast…"
        else
            g.title.text = "Configuring channels"
            g.lead.text = iStr(m.builtCount) + " of " + iStr(m.channels.Count()) + " channels"
        end if
    else if m.channels.Count() = 0 then
        g.kicker.text = "BUILDING LINEUP"
        g.title.text = "Nothing to schedule"
        g.lead.text = "Titles without a runtime are skipped. If " + server + " is still scanning, try again in a few minutes; otherwise press OK to pick other libraries."
    else
        g.kicker.text = "TONIGHT’S LINEUP."
        g.title.text = "Sign-on complete"
        g.lead.text = iStr(m.channels.Count()) + " channels are on the air. Press OK to start flipping."
    end if
    ' The board: a tile per channel built so far, four rows of six.
    shown = m.builtCount
    if shown > m.channels.Count() then shown = m.channels.Count()
    first = 0
    if shown > 24 then first = ((shown - 1) \ 6 - 3) * 6
    while g.tiles.Count() < 24
        tl = {}
        tl.bg = UI_rect(g.board, 0, 0, 272, 100, t.panel, 16)
        tl.number = UI_label(g.board, 0, 0, "", UI_body(26, 600), t.accent, 48, "right")
        tl.name = UI_label(g.board, 0, 0, "", UI_heading(28, 600), t.ink, 180)
        g.tiles.Push(tl)
    end while
    for i = 0 to 23
        tl = g.tiles[i]
        j = first + i
        show = j < shown
        tl.bg.visible = show
        tl.number.visible = show
        tl.name.visible = show
        if show then
            c = m.channels[j]
            x = (i mod 6) * 288
            y = (i \ 6) * 116
            tl.bg.translation = [x, y]
            tl.number.translation = [x + 8, y + 32]
            tl.name.translation = [x + 68, y + 30]
            tl.number.text = iStr(c.number)
            tl.name.text = c.name
        end if
    end for
    g.footer.text = ""
end sub
