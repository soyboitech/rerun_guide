' Port of web/src/core/Lang.ts, plus the 64-bit maths the TS port does in BigInt.
' A u64 lives in a LongInteger with the same bits (from 2^63 up it reads as negative). Add and multiply wrap, as Swift's
' &+ and &*. No shift operators: the off-device engine rejects shifts past 31 bits, so shifts divide by powers of two.
' Identifiers are case-insensitive in BrightScript and share one namespace with functions: a local never takes a
' function's name (mid, left, right, len, str, int, next, end, to, step, pos, type...).

' a xor b (BrightScript has no xor).
function U64_xor(a as LongInteger, b as LongInteger) as LongInteger
    return (a or b) and not (a and b)
end function

' x >>> n, logical, for n in 1...62: `pow` is 2^n and `top` 2^(63 - n), the sign bit's place after the shift.
function U64_shr(x as LongInteger, pow as LongInteger, top as LongInteger) as LongInteger
    if x >= 0 then return x \ pow
    return ((x and &h7FFFFFFFFFFFFFFF&) \ pow) + top
end function

' Unsigned a < b.
function U64_less(a as LongInteger, b as LongInteger) as Boolean
    if (a >= 0) = (b >= 0) then return a < b
    return a >= 0
end function

' Unsigned x mod n, for 0 < n < 2^31.
function U64_mod(x as LongInteger, n as LongInteger) as Integer
    if x >= 0 then return x mod n
    ' The value is (x without its sign bit) + 2^63, and 2^63 mod n is twice 2^62 mod n.
    r = (x and &h7FFFFFFFFFFFFFFF&) mod n + (&h4000000000000000& mod n) * 2 mod n
    return r mod n
end function

' The unsigned decimal digits, as the fixture and Swift's String(UInt64) write them.
function U64_toStr(x as LongInteger) as String
    if x >= 0 then return x.ToStr()
    y = x and &h7FFFFFFFFFFFFFFF&   ' the value is y + 9223372036854775808
    d = y mod 10 + 8
    q = y \ 10 + 922337203685477580& + d \ 10
    return q.ToStr() + (d mod 10).ToStr()
end function

' [high 64 bits, low 64 bits] of x * b, for 0 < b < 2^31 (Lemire's multiplyHigh and the product's low half).
function U64_mulBound(x as LongInteger, b as LongInteger) as Object
    lo = x and &hFFFFFFFF&
    hi = U64_shr(x, 4294967296&, 2147483648&)
    a = hi * b   ' < 2^63
    c = lo * b   ' < 2^63
    high = (a + c \ 4294967296&) \ 4294967296&
    low = (a and &hFFFFFFFF&) * 4294967296& + c   ' wraps to the low 64 bits
    return [high, low]
end function

' Kotlin sortedWith: a sorted copy, stable. cmp(a, b, ctx) < 0 puts a first. Bottom-up merge sort.
function stableSort(a as Object, cmp as Function, ctx = invalid as Dynamic) as Object
    src = []
    for each v in a
        src.Push(v)
    end for
    n = src.Count()
    if n < 2 then return src
    dst = CreateObject("roArray", n, true)
    width = 1
    while width < n
        i = 0
        while i < n
            md = i + width
            if md > n then md = n
            hi = i + 2 * width
            if hi > n then hi = n
            l = i
            r = md
            k = i
            while l < md and r < hi
                if cmp(src[r], src[l], ctx) < 0 then
                    dst[k] = src[r]
                    r = r + 1
                else
                    dst[k] = src[l]
                    l = l + 1
                end if
                k = k + 1
            end while
            while l < md
                dst[k] = src[l]
                l = l + 1
                k = k + 1
            end while
            while r < hi
                dst[k] = src[r]
                r = r + 1
                k = k + 1
            end while
            i = i + 2 * width
        end while
        t = src
        src = dst
        dst = t
        width = width * 2
    end while
    return src
end function

' Kotlin compareValues for numbers: invalid sorts first.
function compareValues(a as Dynamic, b as Dynamic) as Integer
    if a = invalid then
        if b = invalid then return 0
        return -1
    end if
    if b = invalid then return 1
    if a < b then return -1
    if a > b then return 1
    return 0
end function

' Swift's String <: code point order. BrightScript compares strings that way (UTF-8 bytes on the device).
' ponytail: no NFC step, so an NFD title sorts apart from its NFC twin; normalize where items are built if it bites.
function swiftCompare(a as String, b as String) as Integer
    if a < b then return -1
    if a > b then return 1
    return 0
end function

' a's elements then b's, as a new array.
function concat(a as Object, b as Object) as Object
    out = []
    out.Append(a)
    out.Append(b)
    return out
end function

' The first n elements (all of them when there are fewer).
function prefix(a as Object, n as Integer) as Object
    out = []
    for each v in a
        if out.Count() >= n then exit for
        out.Push(v)
    end for
    return out
end function

' a[from...] (to the end).
function suffixFrom(a as Object, from as Integer) as Object
    out = []
    for i = from to a.Count() - 1
        out.Push(a[i])
    end for
    return out
end function

' The index of v in a (=, so strings and numbers), or -1.
function indexOf(a as Object, v as Dynamic) as Integer
    for i = 0 to a.Count() - 1
        if a[i] = v then return i
    end for
    return -1
end function

function contains(a as Object, v as Dynamic) as Boolean
    return indexOf(a, v) >= 0
end function

' A Map/Set for library data: case-sensitive keys (an AA's default ignores case, and "Sci-Fi" isn't "sci-fi").
function newMap() as Object
    o = {}
    o.SetModeCaseSensitive()
    return o
end function

' An Integer (or a whole Double under 2^31) as digits, without Str's leading space.
function iStr(n as Dynamic) as String
    return Int(n).ToStr()
end function

' n as at least `width` digits with leading zeros.
function zeroPad(n as Integer, width as Integer) as String
    s = n.ToStr()
    while Len(s) < width
        s = "0" + s
    end while
    return s
end function

' JS Math.round for the whole and half seconds the scheduler meets: floor(x + 0.5).
function jsRound(x as Double) as Double
    return Int(x + 0.5#)
end function

' Math.ceil.
function ceil(x as Double) as Double
    return -Int(-x)
end function

function maxD(a as Double, b as Double) as Double
    if a > b then return a
    return b
end function

function minD(a as Double, b as Double) as Double
    if a < b then return a
    return b
end function

' s starts with p.
function startsWith(s as String, p as String) as Boolean
    return Left(s, Len(p)) = p
end function

' Kotlin String.replace(old, new): every occurrence.
function replaceAll(s as String, old as String, repl as String) as String
    if old = "" then return s
    return s.Replace(old, repl)
end function

' A letter, as \p{L} reads it, for the code point before a keyword (`ChannelBuilder.mentions`).
' ponytail: ASCII exactly; above it everything but the common punctuation and symbol blocks counts as a letter (no
' Unicode tables on the device), so a rare symbol before a keyword hides the match. Add ranges if one turns up.
function isLetterCode(c as Integer) as Boolean
    if c < 128 then return (c >= 97 and c <= 122) or (c >= 65 and c <= 90)
    if c = &hAA or c = &hB5 or c = &hBA then return true
    if c < &hC0 or c = &hD7 or c = &hF7 then return false
    if c >= &h2000 and c <= &h2BFF then return false   ' punctuation, symbols, arrows, shapes, dingbats
    if c >= &h3000 and c <= &h303F then return false   ' CJK punctuation
    if c >= &hFE30 and c <= &hFE4F then return false
    if c >= &hFF00 and c <= &hFF20 then return false   ' fullwidth punctuation and digits
    return true
end function

' v is the Boolean true (a missing key or JSON null is not).
function isTrue(v as Dynamic) as Boolean
    if type(v) = "Boolean" or type(v) = "roBoolean" then return v
    return false
end function

' v is the Boolean false.
function isFalse(v as Dynamic) as Boolean
    if type(v) = "Boolean" or type(v) = "roBoolean" then return not v
    return false
end function
