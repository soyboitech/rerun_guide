// Port of android/app Platform.kt: everything LG-, Samsung- or browser-specific, and the only file that touches
// webOSSystem, PalmSystem, PalmServiceBridge, tizen or webapis. Every TV call is guarded: the same bundle runs in a
// desktop browser.
import { useRef } from 'preact/hooks'
import { ClientDevice } from '../core/MediaServer'
import { defaults } from './Persistence'

interface WebOSSystem {
  platformBack(): void
  cursor?: { visibility?: boolean }
}
/** LG's Luna bus, what webOSTV.js's webOS.service.request wraps. */
interface PalmServiceBridge {
  onservicecallback: ((reply: string) => void) | null
  call(uri: string, params: string): void
}
interface Tizen {
  tvinputdevice: { registerKeyBatch(keys: string[], ok?: (() => void) | null, err?: (e: unknown) => void): void }
  application: { getCurrentApplication(): { exit(): void } }
}
interface WebAPIs {
  appcommon: {
    setScreenSaver(state: number, ok?: (() => void) | null, err?: (e: unknown) => void): void
    AppCommonScreenSaverState: { SCREEN_SAVER_OFF: number; SCREEN_SAVER_ON: number }
  }
}

declare global {
  interface Window {
    webOSSystem?: WebOSSystem
    PalmSystem?: WebOSSystem
    PalmServiceBridge?: new () => PalmServiceBridge
    tizen?: Tizen
    /** Samsung's webapis.js, loaded by the Tizen index.html. */
    webapis?: WebAPIs
  }
  /** true in the browser build only (build.mjs `define`): debug launch parameters, seed.json, hls.js. */
  const __DEV__: boolean
  /** appinfo.json's version (build.mjs `define`): Settings › About. */
  const __VERSION__: string
}

export type PlatformKind = 'webos' | 'tizen' | 'browser'

const lg: WebOSSystem | undefined = window.webOSSystem || window.PalmSystem   // webOSSystem from webOS 5, PalmSystem before
const kind: PlatformKind = lg ? 'webos' : window.tizen ? 'tizen' : 'browser'

let pointer = false
let screenSaverOn = true

function attempt(f: () => void) {
  try { f() } catch (e) { console.warn(e) }
}

// LG deletes a packaged app's localStorage on every update (its FAQ); DB8 keeps a copy of these `defaults` keys, one
// object each ({ key, value }, DB8's own `_id`: one of ours could clash with another app's, and DB8 refuses most).
// `private`: uninstalling the app still deletes them. Never the sign-in (kc.*): any app on the TV may register a kind
// that extends ours, and our queries then reach its objects, so an LG update signs the TV out as it always did.
const db8Kind = 'com.rerunguide.app:1'
const kept = ['persisted', 'deviceID']
/** In localStorage only, so a store update deletes it with the rest: this localStorage has been given the DB8 copy. */
const restored = 'db8Restored'
const bridges = new Set<PalmServiceBridge>()   // held until they answer: a bridge nobody holds can be collected first
let db8: Promise<unknown> = Promise.resolve()

/** What the DB8 calls here answer: `count` (merge, del by query), `results` (find). */
interface DB8Reply { count?: number; results?: { _id?: string; _kind?: string; key?: unknown; value?: string }[] }

/** One DB8 call. Rejects with LG's error. */
function luna(method: string, params: object): Promise<DB8Reply> {
  return new Promise((resolve, reject) => {
    const b = new window.PalmServiceBridge!()
    bridges.add(b)
    b.onservicecallback = (reply) => {
      bridges.delete(b)
      try {
        const r = JSON.parse(reply)
        if (r.returnValue) resolve(r)
        else reject(new Error(`${method} ${r.errorCode} ${r.errorText}`))
      } catch (e) { reject(e) }
    }
    b.call('luna://com.palm.db/' + method, JSON.stringify(params))
  })
}

/** Runs `step` after every earlier one has finished. A failed step is logged and resolves undefined. */
function queue<T>(step: () => Promise<T>): Promise<T | undefined> {
  const next = db8.then(step).catch(e => { console.warn('DB8', e); return undefined })
  db8 = next
  return next
}

/** `defaults.mirror`: one write per change, in place (a put only for a key DB8 doesn't hold yet). */
function mirror(key: string, value: string | null) {
  if (kept.indexOf(key) < 0) return
  const query = { from: db8Kind, where: [{ prop: 'key', op: '=', val: key }] }
  if (value == null) queue(() => luna('del', { query, purge: true }))
  else queue(() => luna('merge', { query, props: { value } })
    .then(r => (r.count ?? 0) > 0 ? r : luna('put', { objects: [{ _kind: db8Kind, key, value }] })))
}

/** LG, Samsung and a desktop browser from one bundle. Call `init()` once before the first render. */
export const Platform = {
  kind,
  /** Always a TV on the web: the TV copy and layout everywhere. */
  isTV: true as const,
  /** What the copy calls this device; also the server's device name (ClientDevice.device). */
  device: kind === 'webos' ? 'LG TV' : kind === 'tizen' ? 'Samsung TV' : 'TV',
  /** How the copy says "act on it". */
  verb: 'Press',
  /** The remote's select button as the copy names it. */
  select: kind === 'webos' ? 'OK' : 'Select',

  /** Set by main.tsx: the LG Magic Remote pointer appeared or went away (`pointerVisible()` already reflects it). */
  onPointerChange: null as ((visible: boolean) => void) | null,

  init() {
    // MainActivity's ClientDevice setup. Codecs are fixed per platform: canPlayType is unreliable on TVs, and every 2020+
    // set decodes HEVC Main10 and Dolby Digital (Plus). The browser build is for development: H.264 and AAC only.
    // X-Plex-Platform: Plex answers 400 to "webOS" and "Tizen". "Generic" keeps HEVC and E-AC3 copied into fMP4 HLS (the
    // TVs' native player); "Web" would re-encode them to H.264/AAC in TS (the fallback if fMP4 HEVC fails on a TV).
    ClientDevice.platform = kind === 'browser' ? 'Web' : 'Generic'
    ClientDevice.device = Platform.device
    ClientDevice.videoCodecs = kind === 'browser' ? 'h264' : 'h264,hevc'
    ClientDevice.audioCodecs = kind === 'browser' ? 'aac' : 'aac,ac3,eac3'
    ClientDevice.directPlayAudioCodecs = ClientDevice.audioCodecs
    if (kind === 'tizen') Platform.registerKeys()
    if (lg) {
      pointer = !!(lg.cursor && lg.cursor.visibility)
      document.body.classList.toggle('lg-pointer', pointer)
      document.addEventListener('cursorStateChange', (e) => {
        pointer = !!(e as CustomEvent<{ visibility?: boolean }>).detail?.visibility
        document.body.classList.toggle('lg-pointer', pointer)   // turns on the .hov outline (index.html's CSS)
        if (!pointer) { pointed = null; pointedAt = '' }
        Platform.onPointerChange?.(pointer)
      })
    }
  },

  /** LG, before the model reads `defaults`. A localStorage not yet given the DB8 copy (a fresh install, or a store
   *  update deleted it) takes it, and the copy wins; otherwise DB8 catches up with localStorage (a failed write, values
   *  saved before this existed). Only then does every change go on to DB8. When DB8 fails to answer, or answers too
   *  late for a restore, this session leaves DB8 alone and the next launch restores again (ponytail: a restore waits
   *  3 s at most). So does a putKind that fails: only the kind's owner may put it, and another app may have
   *  registered ours first. */
  async keepDefaults(): Promise<void> {
    const restore = defaults.get(restored) == null
    let late = false
    const ready = queue(() => luna('putKind', { id: db8Kind, owner: 'com.rerunguide.app', private: true,
      indexes: [{ name: 'key', props: [{ name: 'key' }] }] }).then(() => luna('find', { query: { from: db8Kind } }))).then(r => {
      if (r == null || (restore && late)) return
      const saved = new Map<string, string>()
      for (const o of r.results ?? []) {
        if (o._kind !== db8Kind || typeof o.key !== 'string') continue   // a kind extending ours answers our find too
        const id = o._id
        if (kept.indexOf(o.key) >= 0) { if (o.value != null) saved.set(o.key, o.value) }
        else if (id != null) queue(() => luna('del', { ids: [id], purge: true }))   // a sign-in an earlier build kept
      }
      for (const key of kept) {
        const copy = saved.get(key) ?? null
        const value = defaults.get(key)
        if (restore && copy != null) defaults.set(key, copy)
        else if (value !== copy) mirror(key, value)
      }
      if (restore) defaults.set(restored, '1')
      defaults.mirror = mirror
    })
    if (restore) await Promise.race([ready, new Promise(done => setTimeout(done, 3000))])
    late = true
  },

  /** Samsung delivers arrows, OK and Back by itself; media, channel and number keys only once registered. Never Back (its
   *  long press is the system's Exit), Exit or volume. The number keys ("0"…"9", the Smart Remote's on-screen 123 pad too)
   *  are a batch of their own, so a set that refuses one keeps the media keys. */
  registerKeys() {
    const register = (keys: string[]) =>
      attempt(() => window.tizen?.tvinputdevice.registerKeyBatch(keys, null, (e) => console.warn('registerKeyBatch', e)))
    register(['MediaPlayPause', 'MediaPlay', 'MediaPause', 'MediaStop', 'MediaFastForward', 'MediaRewind', 'ChannelUp', 'ChannelDown'])
    register(['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'])
  },

  /** Back at the top level. LG: the system's exit popup (webOS 6+) or the launcher (5). Samsung: quits at once (no exit
   *  confirmation yet: one would go in front of this, as RemoteCapture's `exitApp`). Browser: nothing. */
  exitApp() {
    if (lg) attempt(() => lg.platformBack())
    else if (window.tizen) attempt(() => window.tizen!.application.getCurrentApplication().exit())
  },

  /** Samsung: the screensaver must stay off while video plays (and while channel 99 shows). LG has no API: only
   *  full-screen video holds its screensaver off. */
  setScreenSaver(on: boolean) {
    const ac = window.webapis?.appcommon
    if (!ac || on === screenSaverOn) return
    screenSaverOn = on
    const s = ac.AppCommonScreenSaverState
    attempt(() => ac.setScreenSaver(on ? s.SCREEN_SAVER_ON : s.SCREEN_SAVER_OFF, null, (e) => console.warn('setScreenSaver', e)))
  },

  /** LG: the Magic Remote's pointer is showing. While it is, OK arrives as the pointer's click (Remote ignores key 13). */
  pointerVisible(): boolean {
    return pointer
  },
}

// The touch layer of Platform.kt, always on here: the Magic Remote's pointer is a mouse, and a div with only an onClick
// never takes focus away from the remote. Spread into an element: `<div {...onTouch(() => model.openOptions())}>`.

/** A click on this element runs `action`, and only this: the topmost element wins, as with taps in Compose and SwiftUI. */
export function onTouch(action: () => void): { onClick: (e: MouseEvent) => void } {
  return { onClick: (e) => { e.stopPropagation(); remoteFocus(); action() } }
}

let pointed: EventTarget | null = null   // the target the pointer last moved the focus to
let pointedAt = ''                       // where the pointer was then
let pointerFocus = false                 // the focus was last moved by the pointer (not a key, the wheel or a click)

/**
 * A focusable target: the LG pointer moving onto it moves the remote's focus there (`focus`), the mouse-over state LG's
 * QA checks on every pointer target. Only a real move counts: a list sliding under a still pointer moves nothing.
 * Spread next to the click: `<div {...onTouch(act)} {...onPoint(() => { model.focusIndex = i })}>`.
 */
export function onPoint(focus: () => void): { onMouseMove: (e: MouseEvent) => void } {
  return {
    onMouseMove: (e) => {
      if (!pointer || e.currentTarget === pointed) return
      const at = `${e.clientX},${e.clientY}`
      if (at === pointedAt) return
      pointed = e.currentTarget; pointedAt = at; pointerFocus = true
      focus()
    },
  }
}

/** A key, the wheel or a click: the remote's focus rules again (Remote.ts, onTouch). */
export function remoteFocus(): void { pointerFocus = false; pointed = null }

/** A list's scroll position (or first shown row) that holds still while the pointer moves the focus, so the row under
 *  the pointer doesn't slide away from it; the next key, wheel turn or click puts the list back to following the focus. */
export function useSticky(value: number): number {
  const last = useRef(value)
  if (!pointerFocus) last.current = value
  return last.current
}

/** A click on empty space (a scrim, the picture). Elements on top keep their own clicks (`onTouch`). */
export function backgroundTap(action: () => void): { onClick: () => void } {
  return { onClick: () => action() }
}
