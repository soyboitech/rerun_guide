' Port of web/src/core/Time.ts. An instant is epoch seconds as a Double, never an roDateTime; durations are seconds. The
' local calendar is the device's time zone (Settings > System > Time), read through roDateTime.ToLocalTime.
' ponytail: roDateTime.FromSeconds takes a 32-bit Integer, so instants past January 2038 fail; switch to
' FromSecondsLong once every supported Roku OS has it.

' Instant.now().
function Time_now() as Double
    dt = CreateObject("roDateTime")
    return dt.AsSeconds() + dt.GetMilliseconds() / 1000#
end function

' The local wall clock at t: [year, month (1...12), day, hours, minutes, seconds].
function Time_fields(t as Double) as Object
    g = GetGlobalAA()
    dt = g.timeLocalDT
    if dt = invalid then
        dt = CreateObject("roDateTime")
        g.timeLocalDT = dt
    end if
    dt.FromSeconds(Int(t))
    dt.ToLocalTime()
    return [dt.GetYear(), dt.GetMonth(), dt.GetDayOfMonth(), dt.GetHours(), dt.GetMinutes(), dt.GetSeconds()]
end function

' Seconds the local wall clock is ahead of UTC at t.
function Time_offset(t as Double) as Double
    s = Int(t)
    f = Time_fields(s)
    wall = Time_daysFromCivil(f[0], f[1], f[2]) * 86400# + f[3] * 3600 + f[4] * 60 + f[5]
    return wall - s
end function

' Days from 1970-01-01 to y-m-d in the proleptic Gregorian calendar (Howard Hinnant's days_from_civil, as Swift counts).
function Time_daysFromCivil(y as Integer, mo as Integer, d as Integer) as Integer
    if mo <= 2 then y = y - 1
    if y >= 0 then era = y \ 400 else era = (y - 399) \ 400
    yoe = y - era * 400
    if mo > 2 then mp = mo - 3 else mp = mo + 9
    doy = (153 * mp + 2) \ 5 + d - 1
    doe = yoe * 365 + yoe \ 4 - yoe \ 100 + doy
    return era * 146097 + doe - 719468
end function

' The calendar date `z` days after 1970-01-01: [year, month, day].
function Time_civilFromDays(z as Integer) as Object
    z = z + 719468
    if z >= 0 then era = z \ 146097 else era = (z - 146096) \ 146097
    doe = z - era * 146097
    yoe = (doe - doe \ 1460 + doe \ 36524 - doe \ 146096) \ 365
    y = yoe + era * 400
    doy = doe - (365 * yoe + yoe \ 4 - yoe \ 100)
    mp = (5 * doy + 2) \ 153
    d = doy - (153 * mp + 2) \ 5 + 1
    if mp < 10 then mo = mp + 3 else mo = mp - 9
    if mo <= 2 then y = y + 1
    return [y, mo, d]
end function

' LocalDate.atStartOfDay(zone) for y-mo-d. Where a DST change skips midnight (Cairo, the last Friday of April) the day
' starts at the first time that exists, 01:00, as in Java and Swift.
function Time_midnight(y as Integer, mo as Integer, d as Integer) as Double
    w = Time_daysFromCivil(y, mo, d) * 86400#   ' midnight's wall clock, read as UTC
    t = w - Time_offset(w)
    t = w - Time_offset(t)   ' again from the right side of a DST change
    for i = 0 to 95
        f = Time_fields(t)
        if f[0] = y and f[1] = mo and f[2] = d then exit for
        t = t + 900
    end for
    return t
end function

' The start of t's local day.
function Time_startOfDay(t as Double) as Double
    f = Time_fields(t)
    return Time_midnight(f[0], f[1], f[2])
end function

' Local midnight n calendar days after dayStart's day (a DST day is 23 or 25 hours, so never n * 86400).
function Time_addDays(dayStart as Double, n as Integer) as Double
    f = Time_fields(dayStart)
    c = Time_civilFromDays(Time_daysFromCivil(f[0], f[1], f[2]) + n)
    return Time_midnight(c[0], c[1], c[2])
end function

' t's local date: [year, month, day].
function Time_localYMD(t as Double) as Object
    f = Time_fields(t)
    return [f[0], f[1], f[2]]
end function

function Time_localYear(t as Double) as Integer
    return Time_fields(t)[0]
end function

' 0...23.
function Time_localHour(t as Double) as Integer
    return Time_fields(t)[3]
end function
