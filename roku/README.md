# Rerun Guide for Roku

`roku/` is Rerun Guide for Roku players and Roku TVs: a native BrightScript and SceneGraph channel, since Roku has no browser engine to run the web app in. Like `android/` and `web/`, it ports the Swift app (the reference) file by file, through the web port, and keeps the names where BrightScript allows. The scheduler is checked value for value against the same Swift parity fixture, so a channel airs the same thing at the same minute on a Roku as on an Apple TV, a Google TV or an LG or Samsung TV.

## Layout

- `manifest`: title, version, artwork, `ui_resolutions=fhd` (the other ports' 1920×1080 stage, scaled down on HD Rokus), `rsg_version=1.3`, `supports_input_launch=1` (deep links while running), and `link_codes` (see [Store build](#store-build)).
- `source/main.brs`: the roSGScreen. Launch arguments, roInput deep links and Roku's memory warnings go to the scene. Certification has wanted the warnings since 2026-10-01; on one, the scene drops the search index and every day's schedule but today's.
- `components/core/`: port of `web/src/core`: `GuideGenerator.brs` (ChannelBuilder, the tape, tile, Holiday), `Models.brs`, `Time.brs`, `Lang.brs`, `DemoServer.brs`, `TitleSearch.brs`, `Duplicates.brs`. Plain functions, no SceneGraph, used by the scene, by `ServerTask` and by the test.
- `components/app/`: port of `web/src/app`. `Model.brs` is AppModel (the model is the scene's `m`), the `*Model.brs` files are the `AppModel*.ts` handlers, the `*View.brs` and `*Views.brs` files draw the screens, `Ui.brs` holds Theme, `at()` and Clock, `Server.brs` is the render thread's side of every server call, `Store.brs` the registry and the library cache, `Keyboard.brs` the text fields.
- `components/server/`: the Plex, Jellyfin and Emby, and Emby Connect clients and their HTTP, run inside `ServerTask` (roUrlTransfer works only on a Task thread).
- `components/MainScene.*`: the scene: remote keys, render, the 1-second tick, deep links, the launch beacon. `components/ServerTask.*`: one server call per Task.
- `images/`: the channel poster and splash screens (from the app icon), the white 9-patch rounded rectangles the app tints, and the stage's drawn parts (glow, gradients, CRT lines, key glyphs). `tools/images.py` makes them all (needs Pillow). The fonts are copied from `App/Fonts` at build time, so they exist once in the repo.
- `test/parity.brs`: the Swift parity check, reading `android/core/src/test/resources/parity-fixture.json` in place.
- `sim/index.html`: the browser simulator's page. `build.mjs`: build, test, deploy and the simulator (the `npm run` scripts).

## Porting rules

BrightScript differs from TypeScript in ways that bite silently. These are the ones this port ran into.

- **Names.** Identifiers are case-insensitive and share one namespace with functions and keywords. A local never takes a function's or a keyword's name: not `m`, `next`, `end`, `to`, `step`, `pos`, `box`, `left`, `mid`, `str`, `sleep`, `wait`, `run`, `stop`, or an app function such as `tune` or `settings`. So a Slot's end is `finish`, a years chip's range is `yearFrom`/`yearTo`, and the dispatcher is `pressRemote` (`press` is onKeyEvent's parameter). `npx bsc --project bsconfig.json` (brighterscript) catches these after `npm run build`.
- **`m`.** Calling a function stored in an AA as `aa.f()` makes `m` that AA. Server continuations and timer actions are called through a local (`f = p.onDone`, then `f(r, ctx)`), or the model writes go to the wrong object.
- **Maps.** AAs ignore key case by default, so every map keyed by library data (genres, series ids, names) is `newMap()` (SetModeCaseSensitive). Dot assignment lowercases the key (`aa.Key = v` stores `key`), so JSON shapes and query strings use brackets (`aa["Key"]`) or literals, which keep the case.
- **Numbers.** Instants are Doubles (epoch seconds, never an roDateTime). `/` on Integers gives a Float, which has 24 bits: never divide an instant that way. ParseJson reads decimals as Float. The 64-bit hashes (FNV-1a, SplitMix64, Lemire) are LongIntegers whose `*` and `+` wrap. There is no xor (`(a or b) and not (a and b)`) and no shift (division by powers of two instead; the off-device engine rejects shifts past 31 bits).
- **Time.** The local calendar comes from `roDateTime.ToLocalTime()` per instant, which follows the device's time zone setting (Settings › System › Time). `FromSeconds` is 32-bit, so instants past January 2038 fail (`Time.brs` says so).
- **Statements.** One per line: a call can't continue on the next line (an AA or array literal can).
- **Threads.** roUrlTransfer, sockets and roAudioResource don't run on the render thread. A field holding an AA is deep-copied when it crosses to another thread, so a library crosses once per load.
- **Text.** Labels have no letter-spacing, so the handoff's tracked kickers set at the font's own. Rounded corners are 9-patch Posters (`UI_rect`). Video draws on its own plane, so the guide's tube paints its corners over it (`images/corners.png`).

## Build, test and sideload

Needs Node 22 or later (`brs-node` needs it; Homebrew's `node` is fine) and, to regenerate the images, Python 3 with Pillow. Everything runs from `roku/`:

```bash
npm install
npm test                          # the Swift parity check, run off-device by brs-cli
npm run build                     # dist/rerun-guide.zip, the sideloadable package
npx bsc --project bsconfig.json   # lint the built package (names, syntax, missing functions)
npm run sim                       # the zip in the browser simulator at http://127.0.0.1:8090/
python3 tools/images.py           # regenerate images/
```

**Sideload to a Roku.** Turn on developer mode once: on the Roku remote press Home 3 times, Up 2 times, then Right, Left, Right, Left, Right; accept the agreement and set a developer password; the Roku restarts. Keep the address and password in an env file outside the repo, never in it:

```bash
set -a; . ~/keys/roku.env; set +a   # ROKU_HOST=192.168.1.30 and ROKU_PASSWORD=…
npm run deploy                      # builds, then installs dist/rerun-guide.zip over the dev channel
```

Or upload `dist/rerun-guide.zip` in a browser at `http://ROKU_HOST` (user `rokudev`). The BrightScript console (prints, crashes, the debugger) is `telnet $ROKU_HOST 8085`.

**Remote control from the Mac** (External Control Protocol, port 8060; since Roku OS 14.1 keypresses need Settings › System › Advanced system settings › Control by mobile apps set to Enabled):

```bash
curl -d '' http://$ROKU_HOST:8060/keypress/Down
curl -d '' "http://$ROKU_HOST:8060/launch/dev?contentid=genre%3AHorror%3Amovies&mediatype=live"
```

**The simulator** (`npm run sim`) runs the package in the BrightScript Simulation Engine (brs-engine 2.6.2 and its SceneGraph extension) in a browser page: arrows, Enter = OK, Backspace = Back. `?keys=wait:3000,left,down,select` scripts the remote, `?contentid=<channel id>&mediatype=live` sends a deep link, and the registry lives in the page's localStorage (`localStorage.clear()` starts over). It is an emulator: its SceneGraph is a beta, it drops keys sent while a new screen builds, it ignores a ContentNode's PlayStart (the app seeks once the stream plays, `startedAtOffset`), and it wraps text a little differently. Check anything that matters on a Roku.

## Remote

| Roku key | Guide | Player | Elsewhere |
|---|---|---|---|
| Arrows | move; the first press takes the remote | Up/Down change channels, Left/Right skip 10 s (the banner's buttons when it's up) | move |
| OK | watch (on now) or Program info | the banner and its buttons; in a break, the next program now | select |
| Back | let go; drifting, exits to the Roku home screen | hides the banner, then back to the guide | back |
| Play/Pause | the program from its beginning | pause and time-shift; in a break, the last program again (a paused break goes back to live) | |
| ⏪ ⏩, Instant replay | | 10 s back or ahead; replay goes back 10 s | |
| `*` | Options | Roku's own menu (certification 4.4) | Options closes |

Roku remotes have no number keys, so the number box isn't on Roku. Channel up/down arrive only from some Roku TV remotes; the player takes them as Up/Down.

## Store build

Before packaging for the Channel Store, set `link_codes=0` in the manifest and raise the version (`major_version`, `minor_version`, `build_version`). With `link_codes=0` the Plex card signs in with the plex.tv password and lists the account's servers, and Jellyfin and Emby go straight to the address and the password: certification 2.2 wants sign-in on the device, with no code typed on another one. Store rules that affect this app, and the submission steps, are in the private store kit (`rerun-guide-private/store/RELEASING.md`, Roku).

There are no house spots on Roku: Roku requires every video ad to run through its ad framework (RAF), and a spot for Soyboi's own product counts as one. The Settings row and the bundled spots stay out of this port.

## Status (2026-11-08)

**Checked off-device:**
- The scheduler passes the Swift parity fixture: 1,912 checks in `npm test`, and the same test fails under the wrong time zone.
- In the browser simulator, the Sample station runs end to end: Welcome, Libraries, the Building board, the guide (drift, preview video, the held grid, paging ahead), Program info, the player (banner, sleep timer, the break's station card), Options, Settings, Channels, Search (Roku's keyboard, results as you type) and Profiles.
- A deep link on a fresh install starts the Sample station and tunes in.
- Jellyfin, against its public demo (`https://demo.jellyfin.org/stable`, user `demo`, no password):
  - Quick Connect issues a code, and the password sign-in works.
  - The libraries, the 7 channels and the guide match the other ports.
  - The preview and the full-screen player both play, joining mid-program.
- plex.tv and Emby Connect each issue a link code.

**Not checked on a real Roku yet:**
- That LongInteger maths wraps, and that ToLocalTime gets local midnight right across DST changes.
- Fonts, the 9-patches, Video with the servers' HLS (Plex fMP4, Emby TS), PlayStart, the autoplay check and the keyboard dialog.
- Launch time and memory, and the guide's speed with a big library: scheduling runs on the render thread.
- A full Plex or Emby sign-in, the library load and playback (no account was used). Plex addresses: `/identity` probes and plex.direct certificates.

**Not on Roku yet (the other ports have them):**
- Display and presentation: the Midnight Movie theme, attract mode and the screensavers, station idents and the sting, channel 99's scramble (its schedule is there), and the paused program's art and the pause bar.
- Playback:
  - Trailers from the server in the breaks, which show the station card.
  - The Audio and Subtitles pickers and the subtitle and audio-language settings.
  - Mark watched on the server is wired but unverified.
- Channels and library: New channel and Make a channel, recently added (the "what's new" channels catch up at the next full load), and LAN discovery.
- Plex servers: finding a moved one again (`recoverPlexAddress`), and the QR code on the Plex link screen.
- The genre-id migration (`GenreIDMigration`), and a Task for scheduling big libraries.
