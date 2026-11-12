/// <reference types="node" />
// The sleep timer (Swift AppModel+Watch, which no Swift or Kotlin unit test can reach: their models need the app): the
// chip's cycle and deadlines, the one-minute toast, the pause, a spot or the Home screen holding it off, what keeps and
// what clears it, and Play after a long pause reloading the stream. The demo lineup at a fixed clock, as in pause-art.
import assert from 'node:assert/strict'
import { after, test } from 'node:test'
import { DemoMediaServer } from '../src/core/DemoServer'
import { ChannelBuilder } from '../src/core/GuideGenerator'
import { AppModel } from '../src/app/AppModel'
import '../src/app/AppModelGuide'
import { SpotOnAir } from '../src/app/AppModelWatch'

const realNow = Date.now
if (!('navigator' in globalThis)) Object.defineProperty(globalThis, 'navigator', { configurable: true, value: { language: 'en-US' } })   // the banner's track lists read it (Node 20 has none)
after(() => { Date.now = realNow })
const setClock = (at: number) => { Date.now = () => at * 1000 }
// The lineup as of a second after the demo library loaded: one of its movies sits exactly on Just Added's 60 day line,
// and a real clock read twice puts it in or out by the millisecond (another shuffle, other programs on at T).
const loaded = DemoMediaServer.items.find(i => i.id === 'm1')!.addedAt! + 6 * 86_400 + 1
const lineup = ChannelBuilder.channelsFrom(ChannelBuilder.automaticChannels(DemoMediaServer.items, 4, 24, 12, loaded), DemoMediaServer.items, loaded)
const T = new Date(2026, 9, 28, 22, 40).getTime() / 1000

/** A model watching `lineup[0]` live, a minute into what's on at T (a whole second, as the tick's). */
function watching() {
  const m = new AppModel()
  m.later = () => {}   // no banner or toast timers
  m.channels = lineup
  const ch = lineup[0], s = m.slotOnAir(ch, T)!, t = s.start + 60
  setClock(t); m.tune(ch.id, 'live')
  return { m, ch, s, t }
}
const tick = (m: AppModel, at: number) => { setClock(at); m.watchTick(at) }
const chip = (m: AppModel) => { const a = m.watchActions(); return a[a.length - 1].label }
/** Read live: an assert on `toastOf(m)` would narrow the field for the rest of the test. */
const toastOf = (m: AppModel) => m.currentToast

test('the chip: Off, End of program, 30, 60, 90 min, Off, each deadline a whole second', () => {
  const { m, s, t } = watching()
  assert.equal(chip(m), 'Sleep · Off')
  m.cycleSleep(); assert.equal(chip(m), 'Sleep · End of program'); assert.equal(m.sleep!.at, Math.ceil(s.itemEnd) - 1)
  m.cycleSleep(); assert.equal(chip(m), 'Sleep · 30 min'); assert.equal(m.sleep!.at, t + 1800)
  m.cycleSleep(); assert.equal(m.sleep!.at, t + 3600)
  m.cycleSleep(); assert.equal(chip(m), 'Sleep · 90 min'); assert.equal(m.sleep!.at, t + 5400)
  m.cycleSleep(); assert.equal(chip(m), 'Sleep · Off'); assert.equal(m.sleep, null)
})

test('Play in a break is "watch it again"; in a paused break it goes back to live', () => {
  const m = new AppModel()
  m.later = () => {}
  m.channels = lineup
  const { ch, s } = lineup.map(ch => ({ ch, s: m.slotOnAir(ch, T)! })).find(({ s }) => s.end - s.itemEnd >= 30)!
  const pauseInBreak = () => { setClock(s.itemEnd + 5); m.tune(ch.id, 'live'); m.togglePause() }   // as the sleep timer does there (a pulled headphone, a lost audio focus)
  pauseInBreak()
  assert.ok(m.playback!.paused && m.watchInfo()!.isBreak)
  setClock(s.itemEnd + 20); m.press('play')   // the break is still on the air: it carries on with the clock
  assert.deepEqual([m.playback!.mode, m.playback!.paused], ['live', false])
  assert.ok(m.watchInfo()!.isBreak, 'still the break, not the program again')
  assert.equal(m.watchInfo()!.position, s.itemEnd + 20 - s.start, 'on the clock, not where it stopped')
  m.press('play')   // not paused now: watch it again
  assert.ok(!m.watchInfo()!.isBreak && m.watchInfo()!.position < 1)
  pauseInBreak()
  setClock(s.end + 60); m.press('play')   // the break is long over: what is on now
  assert.deepEqual([m.playback!.mode, m.playback!.paused, m.watchInfo()!.slot.start], ['live', false, s.end])
})

test('End of program in a break is the next program\'s end', () => {
  const m = new AppModel()
  m.later = () => {}
  m.channels = lineup
  const hit = lineup.map(ch => ({ ch, s: m.slotOnAir(ch, T)! })).find(({ s }) => s.end - s.itemEnd >= 30)!
  setClock(Math.ceil(hit.s.itemEnd) + 5); m.tune(hit.ch.id, 'live')
  assert.ok(m.watchInfo()!.isBreak)
  m.setSleep(0)
  assert.equal(m.sleep!.at, Math.ceil(m.watchInfo()!.next!.itemEnd) - 1)
})

test('one toast a minute before, then the pause and good night, once', () => {
  const { m } = watching()
  m.setSleep(30)
  const at = m.sleep!.at
  tick(m, at - 61); assert.equal(toastOf(m), null)
  tick(m, at - 60); assert.equal(toastOf(m)?.message, 'Sleep timer. One minute left.'); assert.ok(m.sleep!.warned)
  tick(m, at - 59); assert.equal(toastOf(m)!.n, 1)
  tick(m, at)
  assert.equal(m.playback!.paused, true); assert.equal(m.sleep, null); assert.equal(toastOf(m)?.message, 'Sleep timer. Good night.')
  // A pause as Play/Pause makes it: time-shifted, and the place holds.
  assert.equal(m.playback!.mode, 'start'); assert.equal(m.watchInfo(at + 30)!.position, m.watchInfo(at)!.position)
  tick(m, at + 1); assert.equal(toastOf(m)!.n, 2); assert.equal(m.playback!.paused, true)
})

test('paused by hand: the pause stands and the toast says why', () => {
  const { m } = watching()
  m.setSleep(30); const at = m.sleep!.at
  m.togglePause()
  tick(m, at); assert.equal(m.playback!.paused, true); assert.equal(toastOf(m)?.message, 'Sleep timer. Good night.')
})

test('a spot plays out first; a deadline missed by over a minute is dropped; the Home screen holds it', () => {
  const { m } = watching()
  m.setSleep(30); const at = m.sleep!.at
  SpotOnAir.started = at - 10
  tick(m, at); assert.notEqual(m.sleep, null); assert.equal(m.playback!.paused, false)
  SpotOnAir.started = null
  tick(m, at + 1); assert.equal(m.playback!.paused, true)

  const w = watching(); w.m.setSleep(30); const at2 = w.m.sleep!.at
  tick(w.m, at2 + 61); assert.equal(w.m.sleep, null); assert.equal(w.m.playback!.paused, false); assert.equal(toastOf(w.m), null)

  const h = watching(); h.m.setSleep(30); const at3 = h.m.sleep!.at
  void h.m.enteredBackground()
  tick(h.m, at3); assert.notEqual(h.m.sleep, null)
  h.m.returnedToForeground(); tick(h.m, at3 + 1); assert.equal(h.m.playback!.paused, true)
})

test('End of program waits through a pause and moves with a skip or a held return from Home', () => {
  const { m, t } = watching()
  m.setSleep(0); const end = m.sleep!.at, left = end - t
  assert.ok(left > 600)
  // Paused past the old end: no pause, no toast, and the countdown holds. Play moves the end on by the pause.
  m.togglePause(); const text = m.sleepText(t)
  tick(m, end); assert.notEqual(m.sleep, null); assert.equal(toastOf(m), null); assert.equal(m.sleepText(end), text)
  m.togglePause(); assert.equal(m.sleep!.at, end + left)
  m.skip(-10); assert.equal(m.sleep!.at, end + left + 10)
  m.skip(10); assert.equal(m.sleep!.at, end + left)
  // Held behind the Home screen for 5 minutes: the end comes 5 minutes later.
  void m.enteredBackground(); setClock(end + 300); m.returnedToForeground(); assert.equal(m.sleep!.at, end + left + 300)
  tick(m, end + left); assert.equal(m.playback!.paused, false)
  tick(m, end + left + 300)
  assert.equal(m.playback!.paused, true); assert.equal(m.sleep, null); assert.equal(toastOf(m)?.message, 'Sleep timer. Good night.')
})

test('End of program in a time-shifted break ends what live picks up after it, also after Home', () => {
  /** "Watch it now" from a break, `early` seconds before its slot: the next program plays ahead of the clock, so its own
   *  break is time-shifted (one behind the clock is live, `caught-up.test`). In that break, End of program armed. */
  const ahead = (early: number | null) => {
    const m = new AppModel()
    m.later = () => {}
    m.channels = lineup
    const { ch, s } = lineup.map(ch => ({ ch, s: m.slotOnAir(ch, T)! })).find(({ s }) => s.end - s.itemEnd >= 300)!
    const b = m.slotOnAir(ch, s.end)!, c = m.slotOnAir(ch, b.end)!, t0 = early == null ? s.itemEnd + 5 : b.start - early
    setClock(t0); m.tune(ch.id, 'live'); m.startNextFromBreak()
    const t1 = t0 + Math.ceil(b.item.runtime) + 5
    tick(m, t1); assert.ok(m.watchInfo()!.isBreak && !m.watchInfo()!.live)
    m.setSleep(0)
    return { m, ch, b, c, t1, early: b.start - t0 }
  }
  /** The timer goes off in the last second of the program on screen by then (a second before, it is on: the app ticks
   *  every second, and that tick is the one that makes a caught-up program the playback). */
  const goodNight = (m: AppModel) => {
    const at = m.sleep!.at
    tick(m, at - 1); assert.deepEqual([m.playback!.mode, m.playback!.paused], ['live', false])
    tick(m, at)
    assert.equal(m.playback!.paused, true); assert.equal(toastOf(m)?.message, 'Sleep timer. Good night.')
    assert.equal(at, Math.ceil(m.watchInfo()!.slot.itemEnd) - 1)
  }
  // Earlier than its own break is long: the break runs out with the clock still in the program, live picks that up.
  const far = ahead(null)
  assert.ok(far.early > far.b.end - far.b.itemEnd, 'the lineup still has this case')
  assert.equal(far.m.sleep!.at, Math.ceil(far.b.itemEnd) - 1)
  tick(far.m, far.b.end - far.early)   // the break has run the slot's length: live, in the program again
  assert.equal(far.m.playback!.mode, 'live')
  goodNight(far.m)
  assert.ok(!far.m.watchInfo()!.isBreak, 'in its last second, as a viewer watching live gets')
  // 2 min early: the clock gets to the program's end first, the break is the channel's own from there and rolls into
  // the program after it.
  const near = ahead(120)
  assert.equal(near.m.sleep!.at, Math.ceil(near.c.itemEnd) - 1)
  tick(near.m, Math.ceil(near.b.itemEnd)); assert.ok(near.m.watchInfo()!.live && near.m.watchInfo()!.isBreak); assert.equal(near.m.sleep!.at, Math.ceil(near.c.itemEnd) - 1)
  goodNight(near.m)
  // Home for a minute in the time-shifted break, the clock still short of the program's end: held, and it carries on.
  const { m, ch, b, t1 } = ahead(null)
  const at = m.sleep!.at
  void m.enteredBackground(); setClock(t1 + 60); m.returnedToForeground()
  tick(m, t1 + 61)
  assert.deepEqual([m.playback!.paused, m.watchInfo()!.isBreak, m.watchInfo()!.live, toastOf(m)], [false, true, false, null])
  assert.equal(m.watchInfo()!.position, Math.ceil(b.item.runtime) + 5 + 1, 'where it was held')
  assert.equal(m.sleep!.at, at)
  // Home past the next program: on the clock again at once, and End of program is what is on then.
  void m.enteredBackground()
  const back = Math.ceil(m.slotOnAir(ch, b.end)!.itemEnd) + 600
  setClock(back); m.returnedToForeground()
  tick(m, back + 1); tick(m, back + 2)
  assert.equal(m.playback!.paused, false); assert.equal(m.watchInfo()!.live, true); assert.notEqual(m.sleep, null)   // no good night yet
  goodNight(m)
})

test('End of program late for a started-over program that is already over: its own break holds, not what live moved on to', () => {
  const m = new AppModel()
  m.later = () => {}
  m.channels = lineup
  const { ch, s } = lineup.map(ch => ({ ch, s: m.slotOnAir(ch, T)! })).find(({ s }) => s.end - s.itemEnd >= 300)!
  const late = s.end - s.itemEnd + 120   // started over this far behind: it ends 2 min into the next program, no break left
  setClock(s.start + late); m.tune(ch.id, 'start', s.start); m.setSleep(0)
  const at = m.sleep!.at
  assert.equal(at, Math.ceil(s.end + 120) - 1)
  tick(m, at - 1); assert.equal(m.playback!.paused, false)
  tick(m, at + 1)   // the tick of its last second never came: the program is over, and live is on the next one
  assert.equal(toastOf(m)?.message, 'Sleep timer. Good night.')
  assert.deepEqual([m.playback!.paused, m.watchInfo()!.slot.start, m.watchInfo()!.isBreak], [true, s.start, true])
  m.press('play')   // a paused break: back to live
  assert.deepEqual([m.playback!.mode, m.playback!.paused, m.watchInfo()!.slot.start], ['live', false, s.end])
  // The tick on time, the clock a moment on (a tick always runs a little after its own second) and the program over in
  // between: the pause is read at the tick's second, so it lands in the program's last second, not on the next one.
  setClock(s.start + late + 0.02); m.tune(ch.id, 'start', s.start); m.setSleep(0)   // it ends 0.02 s after a whole second
  const last = m.sleep!.at
  assert.equal(last, s.end + 120)
  setClock(last + 0.05); m.watchTick(last)
  assert.equal(toastOf(m)?.message, 'Sleep timer. Good night.')
  assert.deepEqual([m.playback!.paused, m.watchInfo()!.slot.start, m.watchInfo()!.isBreak], [true, s.start, false])
})

test('a timed sleep on a time-shifted program pauses it as Play/Pause does: its place, the banner, the art timer', () => {
  const { m, t } = watching()
  m.togglePause(); setClock(t + 20); m.togglePause()   // 20 s behind, a minute in
  m.bannerVisible = false; m.pauseArtAt = null
  m.sleep = { at: t + 120, minutes: 30, warned: true }
  tick(m, t + 120)
  assert.deepEqual([m.playback!.paused, m.playback!.offset, m.bannerVisible, m.pauseArtAt != null], [true, 160, true, true])
})

test('a timed sleep after a program ended in another program\'s break: what is on holds, paused in place', () => {
  /** Started over so late that it ends a minute into the next program's break: that break is on, reading live. */
  const lateEnd = () => {
    const m = new AppModel()
    m.later = () => {}
    m.channels = lineup
    const { ch, s } = lineup.map(ch => ({ ch, s: m.slotOnAir(ch, T)! })).find(({ s }) => s.end - s.itemEnd >= 300)!
    const b = m.slotOnAir(ch, s.end)!
    assert.ok(b.end - b.itemEnd > 300, 'the lineup still has this case')
    setClock(s.start + (b.itemEnd + 60 - s.itemEnd)); m.tune(ch.id, 'start', s.start)
    tick(m, b.itemEnd + 60); assert.deepEqual([m.watchInfo()!.live, m.watchInfo()!.isBreak, m.watchInfo()!.slot.start], [true, true, b.start])
    return { m, b }
  }
  // Due in that break (a 30 min timer set earlier): the break on screen holds.
  let { m, b } = lateEnd()
  m.sleep = { at: b.itemEnd + 120, minutes: 30, warned: true }
  tick(m, b.itemEnd + 120)
  assert.equal(toastOf(m)?.message, 'Sleep timer. Good night.')
  assert.deepEqual([m.playback!.paused, m.watchInfo()!.slot.start, m.watchInfo()!.isBreak, m.watchInfo()!.position], [true, b.start, true, b.itemEnd + 120 - b.start])
  // Due in the very tick that break rolls into the next program: that program is paused at its first second. The ended
  // program's own card is only for a timer that came due as it ended, not minutes after.
  ;({ m, b } = lateEnd())
  m.sleep = { at: b.end, minutes: 30, warned: true }
  tick(m, b.end)
  assert.deepEqual([m.playback!.paused, m.watchInfo()!.slot.start, m.watchInfo()!.position], [true, b.end, 0])
  // Due a second after it ended, in that break: still the break on screen, not the card of the program that ended.
  ;({ m, b } = lateEnd())
  m.sleep = { at: b.itemEnd + 61, minutes: 30, warned: true }
  tick(m, b.itemEnd + 61)
  assert.deepEqual([m.playback!.paused, m.watchInfo()!.slot.start, m.watchInfo()!.isBreak], [true, b.start, true])
})

test('a timed sleep half a minute after a paused and resumed program ended, with no tick in between: what is on is paused', () => {
  const m = new AppModel()
  m.later = () => {}
  m.channels = lineup
  const { ch, s } = lineup.map(ch => ({ ch, s: m.slotOnAir(ch, T)! })).find(({ s }) => s.end - s.itemEnd >= 300)!
  const b = m.slotOnAir(ch, s.end)!
  setClock(s.start + 60); m.tune(ch.id, 'live'); m.togglePause()   // paused a minute in
  setClock(s.start + 60 + (s.end - s.itemEnd) + 120); m.togglePause()   // for so long that it ends 2 min into the next program
  m.sleep = { at: s.end + 150, minutes: 30, warned: true }
  tick(m, s.end + 150)   // the first tick since (the app was away in a picture-in-picture window): half a minute after its end
  assert.deepEqual([m.playback!.paused, m.watchInfo()!.slot.start, m.watchInfo()!.position], [true, b.start, 150])
})

test('channel up keeps it (End of program follows the program); the guide clears it with a toast, Settings silently', () => {
  const { m } = watching()
  m.setSleep(0)
  m.press('up')
  const info = m.watchInfo()!
  assert.equal(m.sleep!.minutes, 0)
  assert.equal(m.sleep!.at, Math.ceil(info.slot.start + Math.min(info.slot.item.runtime, info.slot.duration)) - 1)
  m.toGuide(m.playback!.channelID); assert.equal(m.sleep, null); assert.equal(toastOf(m)?.message, 'Sleep timer off.')
  const s = watching(); s.m.setSleep(30); s.m.go('settings')
  assert.equal(s.m.sleep, null); assert.equal(toastOf(s.m), null)
})

test('Play after a long pause reloads the stream; the Home screen\'s own reload counts for it, a failed one doesn\'t', () => {
  const { m, t } = watching()
  m.togglePause(); const n = m.tunes
  setClock(t + 10); m.togglePause(); assert.equal(m.tunes, n)
  m.togglePause(); setClock(t + 81); m.togglePause(); assert.equal(m.tunes, n + 1)
  m.togglePause(); void m.enteredBackground(); setClock(t + 200); m.returnedToForeground(); assert.equal(m.tunes, n + 2)
  m.togglePause(); assert.equal(m.tunes, n + 2)   // Play before that reload lands
  m.togglePause(); setClock(t + 300); m.programLoaded()   // a reload lands while paused (a track pick)
  m.togglePause(); assert.equal(m.tunes, n + 2)
  m.togglePause(); setClock(t + 310); m.programLoaded(true)   // a reload fails while paused
  m.togglePause(); assert.equal(m.tunes, n + 3)
})

test('the countdown reads minutes rounded up', () => {
  const { m } = watching()
  m.setSleep(30); const at = m.sleep!.at
  assert.equal(m.sleepText(at - 120), 'Sleep in 2 min')
  assert.equal(m.sleepText(at - 61), 'Sleep in 2 min')
  assert.equal(m.sleepText(at - 60), 'Sleep in 1 min')
  assert.equal(m.sleepText(at - 1), 'Sleep in 1 min')
  assert.equal(m.sleepText(at - 120, true), '2 minutes left')
  assert.equal(m.sleepText(at - 30, true), '1 minute left')
})
