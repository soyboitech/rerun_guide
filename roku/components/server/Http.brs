' Port of web/src/core/MediaServer.ts's HTTP helpers, for ServerTask (roUrlTransfer runs only on a Task thread).
' Every call returns a result instead of throwing: {ok: true, value} or {ok: false, error (one short user-safe line),
' kind: "unauthorized" | "http" | "notFound" | "unreachable" | "invalid", code}.

function Http_fail(kind as String, message as String, code = 0 as Integer) as Object
    return {ok: false, kind: kind, error: message, code: code}
end function

' What this Roku decodes, for the servers' device profiles: HEVC only where the device says it can (4K models).
function Http_videoCodecs() as String
    g = GetGlobalAA()
    if g.httpVideoCodecs = invalid then
        di = CreateObject("roDeviceInfo")
        g.httpVideoCodecs = "h264"
        if di.CanDecodeVideo({codec: "hevc"}).result = true then g.httpVideoCodecs = "h264,hevc"
    end if
    return g.httpVideoCodecs
end function

function Http_audioCodecs() as String
    return "aac,ac3,eac3"
end function

' The Roku's model name, for X-Plex-Device and the MediaBrowser Device.
function Http_deviceName() as String
    return "Roku " + CreateObject("roDeviceInfo").GetModelDisplayName()
end function

' One request. `headers` an AA; `body` invalid for none. The answer's text with its status, or a failure.
' ponytail: one try, no retry; a flaky LAN shows the error and the next press tries again.
function Http_send(method as String, url as String, headers as Object, body as Dynamic, timeoutSeconds = 30 as Integer) as Object
    port = CreateObject("roMessagePort")
    x = CreateObject("roUrlTransfer")
    x.SetMessagePort(port)
    x.SetUrl(url)
    x.RetainBodyOnError(true)
    x.EnableEncodings(true)
    if LCase(Left(url, 6)) = "https:" then
        x.SetCertificatesFile("common:/certs/ca-bundle.crt")
        x.InitClientCertificates()
    end if
    for each k in headers
        x.AddHeader(k, headers[k])
    end for
    if method = "GET" then
        started = x.AsyncGetToString()
    else
        x.SetRequest(method)
        if body = invalid then body = ""
        started = x.AsyncPostFromString(body)
    end if
    if not started then return Http_fail("unreachable", "Could not connect to the server.")
    msg = Wait(timeoutSeconds * 1000, port)
    if msg = invalid then
        x.AsyncCancel()
        return Http_fail("unreachable", "The request timed out.")
    end if
    if type(msg) <> "roUrlEvent" then return Http_fail("unreachable", "Could not connect to the server.")
    code = msg.GetResponseCode()
    text = msg.GetString()
    if code < 0 or code = 0 then return Http_fail("unreachable", "Could not connect to the server.")
    ' 401 only: a 403 refuses a good token (a Jellyfin access schedule, remote access off, a proxy's block), and
    ' "unauthorized" signs the device out and drops its link. Emby's parental controls refuse with a 401 of their own,
    ' marked X-Application-Error-Code: ParentalControl.
    if code = 401 then
        refused = false
        hs = msg.GetResponseHeadersArray()   ' one header to an entry, for any status: GetResponseHeaders() is empty outside 2xx
        if hs <> invalid then
            for each h in hs
                if h.LookupCI("X-Application-Error-Code") = "ParentalControl" then refused = true
            end for
        end if
        if not refused then return Http_fail("unauthorized", "Not authorized. Sign in again.", code)
    end if
    if code < 200 or code >= 300 then return Http_fail("http", "Server returned " + code.ToStr(), code)
    return {ok: true, value: text, code: code}
end function

' The answer parsed as JSON; text that isn't JSON fails as Swift's Decodable would.
function Http_json(method as String, url as String, headers as Object, body = invalid as Dynamic, timeoutSeconds = 30 as Integer) as Object
    r = Http_send(method, url, headers, body, timeoutSeconds)
    if not r.ok then return r
    text = r.value
    if Left(text, 1) = Chr(&hFEFF) then text = Mid(text, 2)
    j = ParseJson(text)
    if j = invalid then return Http_fail("invalid", "The data couldn’t be read because it isn’t in the correct format.")
    return {ok: true, value: j}
end function

' RFC 3986 unreserved characters stay; everything else is %XX of its UTF-8 bytes, uppercase.
function Http_escape(s as String) as String
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

' "?a=1&b=2" from [[k, v], ...], in the order given ("" for none).
function Http_query(pairs as Object) as String
    if pairs.Count() = 0 then return ""
    parts = []
    for each p in pairs
        parts.Push(Http_escape(p[0]) + "=" + Http_escape(p[1]))
    end for
    return "?" + parts.Join("&")
end function

' ISO 8601 ("2026-02-12T08:00:00.0000000Z") as epoch seconds, the whole seconds only; invalid when it isn't one.
function Http_isoSeconds(s as Dynamic) as Dynamic
    if s = invalid or Len(s) < 19 then return invalid
    head = Left(s, 19)
    if not CreateObject("roRegex", "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$", "").IsMatch(head) then return invalid
    dt = CreateObject("roDateTime")
    dt.FromISO8601String(head + "Z")
    return dt.AsSeconds() * 1#
end function

' The host of a URL, or invalid.
function Http_host(url as Dynamic) as Dynamic
    if url = invalid then return invalid
    r = CreateObject("roRegex", "^[a-zA-Z][a-zA-Z0-9+.-]*://\[?([^/:?#\]]+)", "").Match(url)
    if r.Count() < 2 or r[1] = "" then return invalid
    return r[1]
end function

' "host:port" with the scheme's default port, for comparing addresses; invalid when `url` doesn't parse.
function Http_hostPort(url as Dynamic) as Dynamic
    if url = invalid then return invalid
    r = CreateObject("roRegex", "^([a-zA-Z][a-zA-Z0-9+.-]*)://\[?([^/:?#\]]+)\]?(?::(\d+))?", "").Match(url)
    if r.Count() < 3 or r[2] = "" then return invalid
    port = ""
    if r.Count() > 3 then port = r[3]
    if port = "" then
        if LCase(r[1]) = "https" then port = "443" else port = "80"
    end if
    return LCase(r[2]) + ":" + port
end function
