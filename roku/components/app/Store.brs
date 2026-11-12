' The device's storage, shared by the render thread and ServerTask: the registry section "RerunGuide" (the Persisted JSON,
' the token, the device id) and the library cache.

' ---- Registry ----

function Store_get(key as String) as Dynamic
    sec = CreateObject("roRegistrySection", "RerunGuide")
    if sec.Exists(key) then return sec.Read(key)
    return invalid
end function

sub Store_set(key as String, value as String)
    sec = CreateObject("roRegistrySection", "RerunGuide")
    sec.Write(key, value)
    sec.Flush()
end sub

sub Store_delete(key as String)
    sec = CreateObject("roRegistrySection", "RerunGuide")
    sec.Delete(key)
    sec.Flush()
end sub

' ---- Library cache: the library index as JSON in cachefs:, so the guide is up before the server answers ----
' ponytail: cachefs: can be evicted by the OS; a miss just waits for the server.

function LibraryCache_load(link as String) as Dynamic
    s = ReadAsciiFile("cachefs:/library.json")
    if s = "" then return invalid
    o = ParseJson(s)
    if type(o) <> "roAssociativeArray" or o.link <> link or type(o.items) <> "roArray" then return invalid
    out = []
    for each j in o.items
        it = MediaItem_fromJson(j)
        if it = invalid then return invalid   ' an older shape: refetch
        out.Push(it)
    end for
    return out
end function

sub LibraryCache_save(items as Object, link as String)
    a = []
    for each it in items
        a.Push(MediaItem_toJson(it))
    end for
    WriteAsciiFile("cachefs:/library.json", FormatJson({link: link, items: a}))
    Store_set("libraryCachedAt", iStr(Time_now()))
end sub

sub LibraryCache_clear()
    DeleteFile("cachefs:/library.json")
    Store_delete("libraryCachedAt")
end sub

' Seconds since the cache was written, or -1.
function LibraryCache_age() as Double
    at = Store_get("libraryCachedAt")
    if at = invalid then return -1
    return Time_now() - Val(at)
end function

' Which server and account a cached library belongs to.
function Server_link(cfg as Object) as String
    id = cfg.machineID
    if id = invalid then id = cfg.baseURL
    user = cfg.userID
    if user = invalid then user = ""
    return cfg.kind + "|" + id + "|" + user
end function
