' Port of web/src/app/Theme.ts, Stage.tsx's at() and Text.tsx's Clock: the Late Show tokens as SceneGraph colors, the
' bundled fonts, and helpers that place nodes on the 1920x1080 stage (manifest ui_resolutions=fhd, so the other ports'
' numbers carry over). SceneGraph rectangles have no corner radius: rounded boxes are white 9-patch Posters
' (images/rN.9.png) tinted with blendColor.
' ponytail: no letter-spacing on Roku Labels, so the handoff's tracked kickers and tight headings set at the font's own.

' The Late Show theme (Theme.late). Midnight Movie isn't on Roku yet.
function Theme_late() as Object
    return {
        bg: "0x14110FFF", panel: "0x1E1A17FF", panel2: "0x2A231EFF", line: "0x3B3129FF",
        ink: "0xF3EBE0FF", mute: "0xC9BDAEFF", dim: "0xA89C8EFF",
        accent: "0xF0A33AFF", accentInk: "0x14110FFF",
        focusBg: "0xF3EBE0FF", focusInk: "0x16120FFF", focusDim: "0x5A4E42FF",
        pvText: "0xE6D8C4FF", liveCell: "0x28211CFF", focusFill: "0xE2D2BCFF", ring: "0x2E2722FF",
        breakBadge: "0xFFA94DFF", startOver: "0x7D97FFFF", white: "0xFFFFFFFF", black: "0x000000FF"
    }
end function

' A bundled face: family "heading" (Bricolage Grotesque 500, 600, 700) or "body" (Hanken Grotesk 400 to 800).
function UI_font(family as String, size as Integer, weight = 400 as Integer) as Object
    key = family + iStr(weight) + "_" + iStr(size)
    f = m.fonts[key]
    if f = invalid then
        if family = "heading" then
            name = "BricolageGrotesque-Bold"
            if weight <= 500 then
                name = "BricolageGrotesque-Medium"
            else if weight = 600 then
                name = "BricolageGrotesque-SemiBold"
            end if
        else
            names = {w400: "HankenGrotesk-Regular", w500: "HankenGrotesk-Medium", w600: "HankenGrotesk-SemiBold", w700: "HankenGrotesk-Bold", w800: "HankenGrotesk-ExtraBold"}
            name = names["w" + iStr(weight)]
            if name = invalid then name = "HankenGrotesk-Regular"
        end if
        f = CreateObject("roSGNode", "Font")
        f.uri = "pkg:/fonts/" + name + ".ttf"
        f.size = size
        m.fonts[key] = f
    end if
    return f
end function

function UI_heading(size as Integer, weight = 700 as Integer) as Object
    return UI_font("heading", size, weight)
end function

function UI_body(size as Integer, weight = 400 as Integer) as Object
    return UI_font("body", size, weight)
end function

function UI_group(parent as Object, x = 0 as Float, y = 0 as Float) as Object
    g = parent.CreateChild("Group")
    g.translation = [x, y]
    return g
end function

' The 9-patch radius for a box: the largest drawn one that fits (a pill asks for 999 and gets half its height).
function UI_nine(radius as Integer, w as Float, h as Float) as String
    if radius * 2 >= h and Abs(w - h) < 1 and h > 88 then return "pkg:/images/circle.png"   ' a circle past the 9-patches' 44
    r = radius
    if r * 2 > h then r = Int(h / 2)
    if r * 2 > w then r = Int(w / 2)
    best = 4
    for each n in [4, 8, 12, 16, 20, 24, 30, 44]
        if n <= r then best = n
    end for
    return "pkg:/images/r" + iStr(best) + ".9.png"
end function

' A filled box at (x, y): a Rectangle, or with `radius` a tinted rounded Poster. A color's alpha becomes the opacity.
function UI_rect(parent as Object, x as Float, y as Float, w as Float, h as Float, color as String, radius = 0 as Integer) as Object
    if radius <= 0 then
        n = parent.CreateChild("Rectangle")
        n.color = color
    else
        n = parent.CreateChild("Poster")
        n.uri = UI_nine(radius, w, h)
        UI_tint(n, color)
    end if
    n.translation = [x, y]
    n.width = w
    n.height = h
    return n
end function

' Recolor a box made by UI_rect.
sub UI_tint(n as Object, color as String)
    if n.subtype() = "Rectangle" then
        n.color = color
    else
        n.blendColor = Left(color, 8) + "FF"
        n.opacity = Val(Right(color, 2), 16) / 255
    end if
end sub

' Resize a rounded box, keeping its 9-patch right for the new size.
sub UI_size(n as Object, w as Float, h as Float, radius = 0 as Integer)
    n.width = w
    n.height = h
    if radius > 0 and n.subtype() = "Poster" then n.uri = UI_nine(radius, w, h)
end sub

' One line (or `lines` wrapped lines) of text, top-left at (x, y); w = 0 lets it run its natural width.
function UI_label(parent as Object, x as Float, y as Float, text as String, font as Object, color as String, w = 0 as Float, align = "left" as String, lines = 1 as Integer) as Object
    l = parent.CreateChild("Label")
    l.font = font
    l.color = color
    l.text = text
    l.translation = [x, y]
    l.horizAlign = align
    l.ellipsisText = "…"
    if w > 0 then l.width = w
    if lines > 1 then
        l.wrap = true
        l.maxLines = lines
    end if
    return l
end function

' A label's laid-out width.
function UI_width(l as Object) as Float
    return l.boundingRect().width
end function

function UI_poster(parent as Object, x as Float, y as Float, w as Float, h as Float, uri as String, color = "" as String) as Object
    p = parent.CreateChild("Poster")
    p.uri = uri
    p.translation = [x, y]
    p.width = w
    p.height = h
    if color <> "" then UI_tint(p, color)
    return p
end function

' A pill of text: a rounded box sized to the label plus padding. Returns {box, label, w, h}.
function UI_pill(parent as Object, x as Float, y as Float, text as String, font as Object, ink as String, fill as String, padX as Float, padY as Float) as Object
    bx = UI_rect(parent, x, y, 10, 10, fill, 999)
    l = UI_label(parent, x + padX, y + padY, text, font, ink)
    r = l.boundingRect()
    w = r.width + padX * 2
    h = r.height + padY * 2
    UI_size(bx, w, h, 999)
    return {box: bx, label: l, w: w, h: h}
end function

' Re-text a pill made by UI_pill (its box follows the label).
sub UI_repill(p as Object, text as String, padX as Float, padY as Float)
    p.label.text = text
    r = p.label.boundingRect()
    p.w = r.width + padX * 2
    p.h = r.height + padY * 2
    UI_size(p.box, p.w, p.h, 999)
end sub

' "#f0a33a" (a profile's color) as a SceneGraph color; black when it doesn't parse.
function UI_hex(s as String) as String
    h = s
    if Left(h, 1) = "#" then h = Mid(h, 2)
    if Len(h) <> 6 then return "0x000000FF"
    return "0x" + UCase(h) + "FF"
end function

' The handoff's oklch(L C H) channel gradients, approximated: HSB with hue H (Theme.ts channelColor).
function UI_channelColor(hue as Integer, lightness as Float, chroma as Float) as String
    h = ((hue mod 360) + 360) mod 360
    s = chroma * 4
    if s > 1 then s = 1
    v = lightness * 1.15
    if v > 1 then v = 1
    out = "0x"
    for each n in [5, 3, 1]
        k = (n + h / 60)
        k = k - Int(k / 6) * 6
        f = k
        if 4 - k < f then f = 4 - k
        if f > 1 then f = 1
        if f < 0 then f = 0
        c = Int((v - v * s * f) * 255 + 0.5)
        out = out + UI_hex2(c)
    end for
    return out + "FF"
end function

function UI_hex2(n as Integer) as String
    digits = "0123456789ABCDEF"
    return Mid(digits, n \ 16 + 1, 1) + Mid(digits, n mod 16 + 1, 1)
end function

' ---- Clock (Text.tsx): 12-hour clock text, shared by the guide, the player and the info sheet ----
' ponytail: English AM/PM whatever the device's language.

' "8:30".
function Clock_time(t as Double) as String
    f = Time_fields(t)
    h = f[3] mod 12
    if h = 0 then h = 12
    return iStr(h) + ":" + zeroPad(f[4], 2)
end function

' "PM".
function Clock_ap(t as Double) as String
    if Time_fields(t)[3] < 12 then return "AM"
    return "PM"
end function

' "8:30 PM".
function Clock_full(t as Double) as String
    return Clock_time(t) + " " + Clock_ap(t)
end function

' "7:30 – 9:30 PM": the first AM/PM only when it differs from the second.
function Clock_range(a as Double, b as Double) as String
    x = Clock_ap(a)
    y = Clock_ap(b)
    s = Clock_time(a)
    if x <> y then s = s + " " + x
    return s + " – " + Clock_time(b) + " " + y
end function

' "Starts in 45 min", "Starts in 2 hr 5 min".
function Clock_startsIn(seconds as Double) as String
    mins = Int(ceil(seconds / 60))
    h = mins \ 60
    r = mins mod 60
    if h = 0 then return "Starts in " + iStr(r) + " min"
    if r = 0 then return "Starts in " + iStr(h) + " hr"
    return "Starts in " + iStr(h) + " hr " + iStr(r) + " min"
end function
