package com.rerunguide.app

import androidx.compose.ui.Modifier
import com.rerunguide.core.ServerKind
import java.time.Instant

/* Phone and tablet input (the AppModel half of Touch.swift). The app has one input model, the remote's seven commands
 * (`RemoteCommand`, dispatched by `AppModel.press`), so touch maps onto it instead of adding controls: a tap focuses what
 * it hits and presses Select; drags arrive through `Modifier.remoteDrags`. Every modifier here is a no-op on TV. */

/** The remote's way of acting on a list item: focus it (`focus` sets the screen's focus state), then Select. */
fun Modifier.tapSelects(model: AppModel, focus: () -> Unit = {}): Modifier = onTouch { focus(); model.press(RemoteCommand.select) }

/** Up / Down from drags and the scroll wheel; never on the player, where they would flip channels. On Channels they
 *  scroll the channel list even with the editor's fields focused (seven rows that never scroll), where the remote's
 *  Up / Down would move between fields. */
fun AppModel.scroll(cmd: RemoteCommand) {
    if (screen == Screen.watch && overlay == null && trackMenu == null) return   // the track list scrolls
    if (screen == Screen.channels && overlay == null) channelColumn = 0
    press(cmd)
}

/** A tap on the picture is Play/Pause, at once, as in video apps: the banner's buttons and the picture's own
 *  (`PictureControls`) come up with it. A break that is running has nothing to pause: there a tap stays the remote's
 *  Select on the stage (the break card's "Watch it now", or a banner with buttons put away) and does nothing held
 *  upright, where Now playing's buttons start the next program. Never skips the spot, running or paused: only its
 *  Skip chip does. A tap beside the track list puts it away. */
fun AppModel.watchTap() {
    closeEntry()   // a tap isn't the number box's OK
    val pb = playback ?: return
    val info = watchInfo() ?: return
    if (trackMenu != null) { hideBanner(); return }
    val spot = SpotOnAir.started != null
    if (info.isBreak && !pb.paused) {
        if (bannerVisible && bannerFocus >= 0) hideBanner() else if (!portrait && !spot) press(RemoteCommand.select)
        return
    }
    if (spot) return
    press(RemoteCommand.play)
    // Not after a paused break's Play: that tunes to what is on, with its own banner or none.
    if (!info.isBreak) { bannerVisible = true; bannerFocus = 0; barFocused = false; bannerLater() }
}

/** The picture's own Play/Pause and 10 s buttons (`PictureControls`): up with the banner's buttons, which a tap on
 *  the picture brings, and for as long as the picture is paused (held upright they are the only Play button). A break has nothing to
 *  pause: none while it runs, and on the stage none while it is paused either, where its Play is beside Back
 *  (`TouchChrome`) and the picture's would sit on the station card. */
fun AppModel.showsPictureControls(at: Instant = Instant.now()): Boolean {
    if (Platform.isTV || screen != Screen.watch || overlay != null || trackMenu != null || editingField != null || pip) return false
    val pb = playback ?: return false
    val info = watchInfo(at) ?: return false
    return (pb.paused && (portrait || !info.isBreak)) || (!info.isBreak && bannerVisible && bannerFocus >= 0)
}

/** The 10 s pair goes with Play/Pause on a program only: a break and channel 99 have nothing to skip in, and the Sample
 *  station's one looped clip has nowhere to skip to. */
fun AppModel.pictureSkips(info: WatchInfo): Boolean = !info.isBreak && !info.channel.isScrambled && server?.kind != ServerKind.demo

/** The picture's 10 s buttons: the remote's Left and Right on the player (`skip`). As any press there, it puts a typed
 *  channel number away, and while paused the program's art. */
fun AppModel.pictureSkip(seconds: Double) {
    closeEntry()
    if (playback?.paused == true) armPauseArt()
    skip(seconds)
}

/** A swipe in from the left edge: the guide's menu (Options), elsewhere Back. */
fun AppModel.edgeSwipe() {
    if (overlay != null || editingField != null) return
    if (screen == Screen.guide) { if (attracting) attractReset() else openOptions() }
    else if (showsTouchBack) touchBack()
}

/** The guide's menu button and first-launch hint: the menu (Options) slides in from the left. Portrait has its tab bar. */
val AppModel.showsMenuButton: Boolean get() = screen == Screen.guide && overlay == null && editingField == null && !attracting && !portrait

/** The screens Portrait*.kt draws when the window is taller than wide. The rest keep the stage: a phone turns to
 *  landscape for them (MainActivity), a tablet letterboxes it. */
val AppModel.portraitReady: Boolean
    get() = screen in listOf(Screen.guide, Screen.watch, Screen.channels, Screen.settings) && overlay != Overlay.options && !fullScreen

/** The on-screen Back: the remote's Back, except that from the player it always goes to the guide. */
fun AppModel.touchBack() {
    if (screen == Screen.watch && fullScreen) { fullScreen = false; return }   // back to portrait Now playing (which puts the banner away)
    val pb = playback
    if (screen == Screen.watch && overlay == null && trackMenu == null && pb != null) toGuide(pb.channelID) else press(RemoteCommand.back)
}

/** Not on the top-level screens (the guide has its menu button instead); the player shows Back with its banner. */
val AppModel.showsTouchBack: Boolean
    get() {
        if (overlay != null || editingField != null || portrait) return false
        return when (screen) {
            Screen.welcome, Screen.guide -> false
            Screen.watch -> bannerVisible || (playback?.paused == true && watchInfo()?.isBreak == true)   // a paused break keeps Back, and its Play, up
            else -> true
        }
    }
