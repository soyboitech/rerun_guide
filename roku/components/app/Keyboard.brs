' Text fields: the Roku keyboard (StandardKeyboardDialog, Roku OS 10 and later) over the screen, where the web opens its
' text-entry panel and Android a dialog. `field` says what the text is for; commitText applies it.

sub editText(field as String, value as String, ctx as Dynamic)
    m.editingField = field
    m.editContext = ctx
    d = CreateObject("roSGNode", "StandardKeyboardDialog")
    titles = {addr: "Server address", user: "Username or email", pass: "Password", chName: "Channel name", chNum: "Channel number",
              profileName: "Profile name", search: "Search"}
    d.title = titles[field]
    if field = "addr" then d.message = ["Like 192.168.1.20:8096 or https://jellyfin.example.com"]
    if field = "search" then d.message = ["Films by title, shows by name."]
    d.text = value
    d.buttons = ["OK", "Cancel"]
    if field = "pass" then d.keyboardDomain = "password"
    if field = "chNum" then d.keyboardDomain = "numeric"
    d.ObserveField("buttonSelected", "onKeyboardButton")
    d.ObserveField("wasClosed", "onKeyboardClosed")
    if field = "search" then d.ObserveField("text", "onKeyboardText")
    m.top.dialog = d
end sub

sub onKeyboardButton()
    d = m.top.dialog
    if d = invalid then return
    field = m.editingField
    text = d.text
    m.editingField = invalid
    d.close = true
    if d.buttonSelected = 0 and field <> invalid then commitText(field, text, m.editContext)
    render()
end sub

' Back on the keyboard: nothing typed is kept (Search keeps what it already found).
sub onKeyboardClosed()
    if m.editingField = invalid then return
    m.editingField = invalid
    render()
end sub

' Search finds as you type.
sub onKeyboardText()
    d = m.top.dialog
    if d = invalid or m.editingField <> "search" then return
    setSearchQuery(d.text)
    render()
end sub

sub commitText(field as String, text as String, ctx as Dynamic)
    if field = "addr" then
        m.address = text.Trim()
    else if field = "user" then
        m.username = text.Trim()
    else if field = "pass" then
        m.password = text
    else if field = "chName" then
        n = text.Trim()
        ch = selectedChannel()
        if ch <> invalid and n <> "" then updateChannel(ch.id, {name: n})
    else if field = "chNum" then
        commitNumber(text)
    else if field = "profileName" then
        commitProfileName(ctx, text)
    else if field = "search" then
        setSearchQuery(text)
        if m.searchResults.Count() > 0 then m.searchFocus = 1 else m.searchFocus = 0
    end if
end sub
