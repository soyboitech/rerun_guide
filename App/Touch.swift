import SwiftUI
import UIKit

/// iPhone, iPad and Mac (Catalyst) input. The app has one input model, the Siri Remote's seven commands
/// (`RemoteCommand`, dispatched by `AppModel.press`), so touch and mouse map onto it instead of adding controls: a tap
/// focuses what it hits and presses Select; drags, the scroll wheel and keys arrive through `RemoteCaptureUIView`. Every modifier here except `exitCommand` is a no-op on tvOS.
enum Platform {
    #if os(tvOS)
    static let isTV = true
    #else
    static let isTV = false
    #endif

    /// What the copy calls this device.
    @MainActor static var device: String {
        #if os(tvOS)
        return "Apple TV"
        #elseif targetEnvironment(macCatalyst)
        return "Mac"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    /// How the copy says "act on it": the remote's clickpad, a finger, a mouse.
    static var verb: String {
        #if os(tvOS)
        return "Press"
        #elseif targetEnvironment(macCatalyst)
        return "Click"
        #else
        return "Tap"
        #endif
    }
}

extension View {
    /// A tap (or click) on this element runs `action`; VoiceOver reads it as one button (its texts combined).
    func onTouch(_ action: @escaping () -> Void) -> some View {
        #if os(tvOS)
        return self
        #else
        return contentShape(Rectangle()).tap(action)
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
        #endif
    }

    /// A tap on empty space (a scrim, the picture). Elements on top keep their own taps.
    func backgroundTap(_ action: @escaping () -> Void) -> some View {
        #if os(tvOS)
        return self
        #else
        return contentShape(Rectangle()).tap(action)
        #endif
    }

    /// A tap anywhere on an element that draws its own background, with no content shape: what it draws outside its
    /// bounds (the banner's track list) keeps its own taps.
    func plainTap(_ action: @escaping () -> Void) -> some View {
        #if os(tvOS)
        return self
        #else
        return tap(action)
        #endif
    }

    #if !os(tvOS)
    /// A tap that is not also a drag. The window's pan (`RemoteCaptureUIView.dragged`) recognizes alongside SwiftUI's
    /// taps, and SwiftUI still calls a touch a tap after it has moved 45 points: more than a swipe on the player or a
    /// flick down the guide needs. Every tap on the stage goes through here; App/Portrait has no window pan.
    func tap(_ action: @escaping () -> Void) -> some View {
        onTapGesture { if !RemoteCaptureUIView.swiping { action() } }
    }
    #endif

    /// The remote's way of acting on a list item: focus it (`focus` sets the screen's focus state), then Select.
    func tapSelects(_ model: AppModel, _ focus: @escaping () -> Void = {}) -> some View {
        onTouch { focus(); model.press(.select) }
    }

    /// Menu on tvOS, and the keyboard closing (its done, or Menu, which leaves the field focused): an inline field hands
    /// the remote back in one press. Elsewhere text goes through `TextEntry`'s alert, so no inline field is ever left this way.
    func exitCommand(_ action: @escaping () -> Void) -> some View {
        #if os(tvOS)
        return onExitCommand(perform: action)
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)) { _ in action() }
        #else
        return self
        #endif
    }
}

extension AppModel {
    /// The field a screen draws inline. tvOS only: elsewhere `TextEntry` edits `editingField` in an alert, which brings
    /// the system keyboard and stays legible however small the stage is drawn.
    var inlineEditing: String? { Platform.isTV ? editingField : nil }

    /// Up / Down from drags and the scroll wheel; never on the player, where they would flip channels. On Channels they
    /// scroll the channel list even with the editor's fields focused (seven rows that never scroll), where the remote's
    /// Up / Down would move between fields.
    func scroll(_ cmd: RemoteCommand) {
        guard screen != .watch || overlay != nil || trackMenu != nil else { return }   // the track list scrolls
        if screen == .channels, overlay == nil { channelColumn = 0 }
        press(cmd)
    }

    /// A tap on the picture is Play/Pause, at once, as in video apps: the banner's buttons and the picture's own
    /// (`PictureControls`) come up with it. A break that is running has nothing to pause: there a tap stays the
    /// remote's Select on the stage (the break card's "Watch it now", or a banner with buttons put away) and does
    /// nothing held upright, where Now playing's buttons start the next program. Never skips the spot, running or
    /// paused: only its Skip chip does. A tap beside the track list puts it away.
    func watchTap() {
        closeEntry()   // a tap isn't the number box's OK
        guard let pb = playback, let info = watchInfo() else { return }
        if trackMenu != nil { hideBanner(); return }
        let spot = SpotOnAir.shared.started != nil
        if info.isBreak, !pb.paused {
            if bannerVisible && bannerFocus >= 0 { hideBanner() } else if !portrait, !spot { press(.select) }
            return
        }
        if spot { return }
        press(.play)
        // Not after a paused break's Play: that tunes to what is on, with its own banner or none.
        if !info.isBreak { bannerVisible = true; bannerFocus = 0; barFocused = false; bannerLater() }
    }

    /// The picture's own Play/Pause and 10 s buttons (`PictureControls`): up with the banner's buttons, which a tap on
    /// the picture brings, and for as long as the picture is paused (held upright they are the only Play button). A break has
    /// nothing to pause: none while it runs, and on the stage none while it is paused either, where its Play is
    /// beside Back (`TouchChrome`) and the picture's would sit on the station card.
    func showsPictureControls(at now: Date = .now) -> Bool {
        guard !Platform.isTV, screen == .watch, overlay == nil, trackMenu == nil, editingField == nil, !pip,
              let pb = playback, let info = watchInfo(at: now) else { return false }
        return (pb.paused && (portrait || !info.isBreak)) || (!info.isBreak && bannerVisible && bannerFocus >= 0)
    }

    /// The 10 s pair goes with Play/Pause on a program only: a break and channel 99 have nothing to skip in, and the
    /// Sample station's one looped clip has nowhere to skip to.
    func pictureSkips(_ info: WatchInfo) -> Bool { !info.isBreak && !info.channel.isScrambled && server?.kind != .demo }

    /// The picture's 10 s buttons: the remote's Left and Right on the player (`skip`). As any press there, it puts a
    /// typed channel number away, and while paused the program's art.
    func pictureSkip(_ seconds: TimeInterval) {
        closeEntry()
        if playback?.paused == true { armPauseArt() }
        skip(seconds)
    }

    /// A swipe in from the left edge: the guide's menu (Options), elsewhere Back, as on iOS.
    func edgeSwipe() {
        guard overlay == nil, editingField == nil else { return }
        if screen == .guide { if attracting { attractReset() } else { openOptions() } }
        else if showsTouchBack { touchBack() }
    }

    /// The guide's menu button and first-launch hint: the menu (Options) slides in from the left. Portrait has its tab bar.
    var showsMenuButton: Bool { screen == .guide && overlay == nil && editingField == nil && !attracting && !portrait }

    /// The screens App/Portrait draws when the window is taller than wide. The rest keep the stage: an iPhone turns to
    /// landscape for them (OrientationLock), an iPad letterboxes it.
    var portraitReady: Bool { [.guide, .watch, .channels, .settings].contains(screen) && overlay != .options && !fullScreen }

    /// The on-screen Back: the remote's Back, except that from the player it always goes to the guide (once the track
    /// list is put away).
    func touchBack() {
        if screen == .watch, fullScreen { fullScreen = false; return }   // back to portrait Now playing (which puts the banner away)
        if screen == .watch, overlay == nil, trackMenu == nil, let pb = playback { toGuide(from: pb.channelID) } else { press(.back) }
    }

    /// Not on the top-level screens (the guide has its menu button instead); the player shows Back with its banner.
    var showsTouchBack: Bool {
        guard overlay == nil, editingField == nil, !portrait else { return false }
        switch screen {
        case .welcome, .guide: return false
        case .watch: return bannerVisible || (playback?.paused == true && watchInfo()?.isBreak == true)   // a paused break keeps Back, and its Play, up
        default: return true
        }
    }
}

#if !os(tvOS)
/// The guide's menu button and Back: the remote's buttons have no on-screen equivalent in the TV design. Window space,
/// 44 pt, in the top-left corner: on an iPhone in landscape that is the margin beside the Dynamic Island, so they take
/// nothing from the guide. The Mac has the keyboard, the Options hint pill and the profile chip. The player's Play/Pause
/// is on the picture (`PictureControls`), except in a break, where Play stays beside Back.
struct TouchChrome: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            #if !targetEnvironment(macCatalyst)
            if model.showsMenuButton { TouchButton(symbol: "line.3.horizontal", label: "Menu") { model.openOptions() } }
            #endif
            if model.showsTouchBack {
                TouchButton(symbol: "chevron.backward", label: "Back") { model.touchBack() }
                // A break has no Pause, so the picture shows no buttons there: its Play is the remote's, "watch it
                // again" while the break runs (a trailer break has no pill for it), back to live once it is paused.
                if model.screen == .watch, model.watchInfo()?.isBreak == true {
                    TouchButton(symbol: "play.fill", label: "Play") { model.press(.play) }
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.showsTouchBack)
        .animation(.easeOut(duration: 0.2), value: model.showsMenuButton)
    }
}

/// Play/Pause on the picture with 10 s back and ahead beside it, where video apps have them. A tap on the picture
/// pauses or plays (`watchTap`) and brings them up; they stay while it is paused (`showsPictureControls`), so the
/// next tap can be a skip. Held upright they sit in the middle of Now playing's picture box, inside its drag
/// (PortraitWatch); on the stage in window space, 200 points above the middle, clear of the banner and of a paused
/// subtitle (RootView). Ahead is dimmed on a live program: there is nothing ahead of the clock.
struct PictureControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .timelineOrigin, by: 1)) { ctx in   // a program rolls into its break under them
            let show = model.showsPictureControls(at: ctx.date)
            let info = show ? model.watchInfo(at: ctx.date) : nil, paused = model.playback?.paused == true
            HStack(spacing: 22) {
                if let info {
                    let skips = model.pictureSkips(info)
                    if skips { TouchButton(symbol: "gobackward.10", label: "Back 10 seconds", size: 52) { model.pictureSkip(-10) } }
                    TouchButton(symbol: paused ? "play.fill" : "pause.fill", label: paused ? "Play" : "Pause", size: 64) { model.press(.play) }
                    if skips {
                        TouchButton(symbol: "goforward.10", label: "Ahead 10 seconds", size: 52) { model.pictureSkip(10) }
                            .opacity(info.live ? 0.4 : 1)
                    }
                }
            }
            .animation(.easeOut(duration: 0.2), value: show)
        }
    }
}

/// One of the on-screen buttons: the theme's panel behind an SF Symbol, round (square on Midnight Movie).
private struct TouchButton: View {
    @Environment(AppModel.self) private var model
    let symbol: String, label: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        let t = model.theme
        Image(systemName: symbol).font(.system(size: size * 18 / 44, weight: .bold)).foregroundStyle(t.ink)
            .frame(width: size, height: size)
            .background(t.panel.opacity(0.9), in: t.radius == 0 ? AnyShape(Rectangle()) : AnyShape(Circle()))
            .contentShape(Rectangle())
            .tap(action)
            .accessibilityLabel(label).accessibilityAddTraits(.isButton)
            .transition(.opacity)
    }
}

/// The first three launches, the menu's edge peeks in from the left three times on the guide, then goes away: the
/// menu slides in from there (a swipe in from the edge, the menu button, or the profile chip).
struct MenuHint: View {
    @Environment(AppModel.self) private var model
    @State private var peek: CGFloat = 0
    @State private var finished = false
    private static let key = "menuHintLaunches"
    /// Read once per launch; counted when this launch's hint has played.
    private static let due = UserDefaults.standard.integer(forKey: key) < 3
    @MainActor private static var played = false

    var body: some View {
        if Self.due, !Self.played, !finished, model.showsMenuButton {
            HStack(spacing: 0) {
                model.theme.panel.frame(width: 60)
                Capsule().fill(model.theme.ink.opacity(0.4)).frame(width: 5, height: 56).padding(.leading, 8)
            }
            .frame(maxHeight: .infinity, alignment: .leading)
            .shadow(color: .black.opacity(0.5), radius: 16, x: 6)
            .offset(x: -73 + peek)   // hidden off the left edge until it peeks
            .allowsHitTesting(false).accessibilityHidden(true)
            .task { await bounce() }
        }
    }

    private func bounce() async {
        guard (try? await Task.sleep(for: .seconds(1.2))) != nil else { return }
        for _ in 0..<3 {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { peek = 34 }
            guard (try? await Task.sleep(for: .seconds(0.45))) != nil else { return }
            withAnimation(.easeIn(duration: 0.25)) { peek = 0 }
            guard (try? await Task.sleep(for: .seconds(0.5))) != nil else { return }
        }
        Self.played = true; finished = true
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: Self.key) + 1, forKey: Self.key)
    }
}

/// Text input off tvOS: the field the remote would have opened inline (`editingField`) as an alert with a text field.
/// OK commits the way the tvOS fields' submit does; Cancel leaves the value as it was. Search's results follow the
/// typing behind the alert.
struct TextEntry: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @State private var original = ""
    /// The field the alert is up for, set with its draft: an alert presented in the update that opened the field kept the
    /// draft it found there (the last field's text, after an OK).
    @State private var shown: String?

    func body(content: Content) -> some View {
        let field = shown
        content
            .onChange(of: model.editingField, initial: true) { _, f in if f != nil { draft = initial(f); original = draft }; shown = f }   // draft kept on close: OK may run after
            .onChange(of: draft) { _, d in if model.editingField == "search" { model.searchQuery = d } }
            .alert(title(field), isPresented: Binding(get: { shown != nil && model.editingField != nil }, set: { if !$0 { cancel() } })) {
                if field == "pass" {
                    SecureField(title(field), text: $draft)
                } else {
                    TextField(title(field), text: $draft)
                        .keyboardType(field == "addr" ? .URL : field == "chNum" ? .numberPad : .default)
                        .textInputAutocapitalization(field == "addr" || field == "user" ? .never : .words)
                        .autocorrectionDisabled()
                }
                Button("Cancel", role: .cancel) { draft = ""; cancel() }   // a typed password isn't kept either
                Button("OK") { commit(field) }
            }
    }

    private func title(_ f: String?) -> String {
        switch f {
        case "addr": "Server address"
        case "user": "Username"
        case "pass": "Password"
        case "profileName": "Profile name"
        case "chName": "Channel name"
        case "chNum": "Channel number"
        case "search": "Search"
        default: ""
        }
    }

    private func initial(_ f: String?) -> String {
        let profiles = model.persisted.profiles
        switch f {
        case "addr": return model.address
        case "user": return model.username
        case "pass": return model.password
        case "profileName": return profiles.indices.contains(model.focusIndex) ? profiles[model.focusIndex].name : ""
        case "chName": return model.selectedChannel?.name ?? ""
        case "chNum": return model.numberDraft ?? ""
        case "search": return model.searchQuery
        default: return ""
        }
    }

    /// Never reads `editingField`: SwiftUI may dismiss (and so `cancel()`) before it runs the button's action.
    private func commit(_ f: String?) {
        switch f {
        case "addr": model.address = AppModel.normalized(draft)
        case "user": model.username = draft
        case "pass": model.password = draft; draft = ""   // not left behind in this view's state
        case "profileName": model.commitProfileName(model.focusIndex, draft)
        case "chName": if let id = model.channelSelection { let name = draft; model.updateChannel(id) { $0.name = name } }
        case "chNum": model.numberDraft = String(draft.filter(\.isNumber).prefix(3)); model.commitNumber()
        case "search": model.searchQuery = draft
        default: break
        }
        model.editingField = nil
    }

    private func cancel() {
        guard model.editingField != nil else { return }
        if model.editingField == "chNum" { model.numberDraft = nil }
        if model.editingField == "search" { model.searchQuery = original }
        model.editingField = nil
    }
}
#endif
