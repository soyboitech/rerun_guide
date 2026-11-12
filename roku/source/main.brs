' Rerun Guide for Roku: the channel's entry point. One SceneGraph screen, MainScene, is the whole app. Launch arguments
' (a deep link's contentId and mediaType), deep links while running (roInput) and Roku's memory warnings go to the
' scene's fields.
sub Main(args as Dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    scene = screen.CreateScene("MainScene")
    screen.Show()
    if type(args) = "roAssociativeArray" then scene.launchArgs = args
    input = CreateObject("roInput")
    input.SetMessagePort(port)
    ' Memory warnings, which certification wants from every app since 2026-10-01: roAppMemoryMonitor, or on the models
    ' without it (Liberty, Austin, Mustang, Littlefield) the device's low-memory event, as in Roku's sample.
    monitor = CreateObject("roAppMemoryMonitor")
    monitor.SetMessagePort(port)
    if not monitor.EnableMemoryWarningEvent(true) then
        device = CreateObject("roDeviceInfo")
        device.SetMessagePort(port)
        device.EnableLowGeneralMemoryEvent(true)
    end if
    while true
        msg = Wait(0, port)
        t = type(msg)
        if t = "roSGScreenEvent" then
            if msg.IsScreenClosed() then return
        else if t = "roInputEvent" then
            if msg.IsInput() then scene.deepLink = msg.GetInfo()
        else if t = "roAppMemoryNotificationEvent" then
            ' At 80% of the app's limit; since Roku OS 15.2 also at 85, 90 and 95%, and on the way back down.
            used = msg.GetInfo().memoryUsagePercent
            if used <> invalid and used >= 80 then scene.lowMemory = true
        else if t = "roDeviceInfoEvent" then
            level = msg.GetInfo().generalMemoryLevel
            if level <> invalid and level <> "normal" then scene.lowMemory = true
        end if
    end while
end sub
