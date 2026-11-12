/// <reference types="node" />
// A started-over program going back to live (Swift AppModel+Watch `watchInfo`, which no Swift or Kotlin unit test can
// reach: their models need the app): it is live again when it has ended and the clock is past its end too, so its break
// ends with the slot and the next program starts on time. The toast, and the playback itself, wait for a program to be
// on: a break stays quiet. The demo lineup at a fixed clock, as in sleep-timer.
import assert from 'node:assert/strict'
import { after, test } from 'node:test'
import { DemoMediaServer } from '../src/core/DemoServer'
import { ChannelBuilder } from '../src/core/GuideGenerator'
import { Slot } from '../src/core/Models'
import { AppModel } from '../src/app/AppModel'
import '../src/app/AppModelGuide'
import '../src/app/AppModelWatch'

const realNow = Date.now
if (!('navigator' in globalThis)) Object.defineProperty(globalThis, 'navigator', { configurable: true, value: { language: 'en-US' } })   // the banner's track lists read it (Node 20 has none)
after(() => { Date.now = realNow })
const setClock = (at: number) => { Date.now = () => at * 1000 }
// The lineup as of a second after the demo library loaded: one of its movies sits exactly on Just Added's 60 day line,
// and a real clock read twice puts it in or out by the millisecond (another shuffle, other programs on at T).
const loaded = DemoMediaServer.items.find(i => i.id === 'm1')!.addedAt! + 6 * 86_400 + 1
const lineup = ChannelBuilder.channelsFrom(ChannelBuilder.automaticChannels(DemoMediaServer.items, 4, 24, 12, loaded), DemoMediaServer.items, loaded)
const T = new Date(2026, 9, 28, 22, 40).getTime() / 1000

/** A model on a channel whose program on at T (`s`) has a break of five minutes or more, and what follows it (`b`). */
function setup() {
  const m = new AppModel()
  m.later = () => {}   // no banner or toast timers
  m.channels = lineup
  const { ch, s } = lineup.filter(c => !c.isScrambled).map(ch => ({ ch, s: m.slotOnAir(ch, T)! })).find(({ s }) => s.end - s.itemEnd >= 300)!
  return { m, ch, s, b: m.slotOnAir(ch, s.end)! }
}
const tick = (m: AppModel, at: number) => { setClock(at); m.watchTick(at) }
/** Read live: an assert on `m.currentToast` would narrow the field for the rest of the test. */
const toastOf = (m: AppModel) => m.currentToast
/** What the screen draws at `at`: [live, in a break, the slot's start]. */
const on = (m: AppModel, at: number) => { const i = m.watchInfo(at)!; return [i.live, i.isBreak, i.slot.start] }

/** `setup`, then `s` held for 20 s a minute in, as a call does: it ends 20 s after its end on the clock. */
function held() {
  const x = setup()
  setClock(x.s.start + 60); x.m.tune(x.ch.id, 'live'); x.m.togglePause(); setClock(x.s.start + 80); x.m.togglePause()
  return x
}

test('held for 20 s: the program ends 20 s late, its break ends with the slot, the next program starts on time and says so', () => {
  const { m, s } = held()
  tick(m, s.itemEnd + 19)
  assert.deepEqual(on(m, s.itemEnd + 19), [false, false, s.start], 'its last second, 20 s behind')
  // What the screen draws from here is the channel's own break, never a time-shifted one.
  assert.deepEqual(on(m, s.itemEnd + 20), [true, true, s.start])
  assert.equal(m.watchInfo(s.itemEnd + 20)!.position, s.itemEnd + 20 - s.start, 'on the clock: 20 s of the break are gone')
  // The break is quiet: no toast, nothing asked to load again. It reads live all the same (the banner offers Start over).
  const tunes = m.tunes
  tick(m, s.itemEnd + 20); tick(m, s.end - 1)
  assert.deepEqual(on(m, s.end - 1), [true, true, s.start]); assert.equal(m.watchActions()[0].label, 'Start over')
  assert.deepEqual([toastOf(m), m.tunes], [null, tunes])
  // The next program from its beginning, and the toast with it: what is on is what is kept from here.
  tick(m, s.end)
  assert.deepEqual(on(m, s.end), [true, false, s.end]); assert.equal(m.watchInfo(s.end)!.position, 0)
  assert.deepEqual([m.playback!.mode, m.playback!.slot?.start, toastOf(m)?.message, toastOf(m)?.n, m.tunes], ['live', s.end, 'Caught up. Back to live.', 1, tunes])
})

test('the break card: "just ended" after a program watched to its end, its clock time for a break joined on the air', () => {
  // Watched 20 s late: its own break reads live, and its card still says the program just ended, to the end of the break.
  const { m, s } = held()
  tick(m, s.itemEnd + 20)
  assert.deepEqual([m.watchInfo()!.live, m.watchInfo()!.isBreak, m.justEnded(m.watchInfo()!)], [true, true, true])
  tick(m, s.end - 1); assert.equal(m.justEnded(m.watchInfo()!), true)
  // Paused there (the sleep timer, headphones) it still just ended; Play goes back on the air, as into any break rejoined,
  // and from there the card gives the clock time.
  m.togglePause(); assert.equal(m.justEnded(m.watchInfo()!), true)
  m.press('play'); assert.deepEqual([m.playback!.mode, m.justEnded(m.watchInfo()!)], ['live', false])
  // Joined on the air: the time it ended at.
  const x = setup()
  setClock(x.s.itemEnd + 30); x.m.tune(x.ch.id, 'live')
  assert.deepEqual([x.m.watchInfo()!.isBreak, x.m.justEnded(x.m.watchInfo()!)], [true, false])
  // That break paused (the sleep timer, headphones) is held in place: "just ended", as it always said, kept slot or not.
  x.m.togglePause(); assert.equal(x.m.justEnded(x.m.watchInfo()!), true)
  x.m.playback = { ...x.m.playback!, slot: null }; assert.deepEqual([x.m.watchInfo()!.slot.start, x.m.justEnded(x.m.watchInfo()!)], [x.s.start, true])
  // Watched so late that it ended in the next program's break: the card is that program's, which nobody watched end.
  const y = setup()
  setClock(y.s.start + (y.b.itemEnd + 60 - y.s.itemEnd)); y.m.tune(y.ch.id, 'start', y.s.start)
  tick(y.m, y.b.itemEnd + 60)
  assert.deepEqual([y.m.watchInfo()!.slot.start, y.m.watchInfo()!.isBreak, y.m.justEnded(y.m.watchInfo()!)], [y.b.start, true, false])
  // Started before it aired: its own time-shifted break, then the channel's own, both seen from the program's end.
  const z = setup()
  setClock(z.b.start - 120); z.m.tune(z.ch.id, 'live'); z.m.startNextFromBreak()
  tick(z.m, z.b.start - 120 + Math.ceil(z.b.item.runtime)); assert.deepEqual([z.m.watchInfo()!.live, z.m.justEnded(z.m.watchInfo()!)], [false, true])
  tick(z.m, Math.ceil(z.b.itemEnd) + 5); assert.deepEqual([z.m.watchInfo()!.live, z.m.watchInfo()!.isBreak, z.m.justEnded(z.m.watchInfo()!)], [true, true, true])
})

test('away for the break, where the tick may still run: the toast waits for the way back', () => {
  const { m, s } = held()
  tick(m, s.itemEnd + 20)
  setClock(s.itemEnd + 30); void m.enteredBackground()
  assert.equal(m.playback!.paused, false, 'a break holds nothing for Home')
  tick(m, s.end + 5)   // behind the Home screen, the next program on
  assert.deepEqual([m.playback!.mode, toastOf(m)], ['start', null])
  setClock(s.end + 60); m.returnedToForeground(); tick(m, s.end + 61)
  assert.deepEqual([m.playback!.mode, m.playback!.slot?.start, toastOf(m)?.message], ['live', s.end, 'Caught up. Back to live.'])
})

test('it ends in the next program\'s break: quiet through that break too, the toast with the program after it', () => {
  const { m, ch, s, b } = setup()
  const late = b.itemEnd + 60 - s.itemEnd   // started over so late that it ends a minute into the next program's break
  assert.ok(b.end - b.itemEnd > 120, 'the lineup still has this case')
  setClock(s.start + late); m.tune(ch.id, 'start', s.start)
  tick(m, b.itemEnd + 59); assert.deepEqual(on(m, b.itemEnd + 59), [false, false, s.start])
  tick(m, b.itemEnd + 60); assert.deepEqual(on(m, b.itemEnd + 60), [true, true, b.start])
  tick(m, b.end - 1); assert.deepEqual([m.playback!.mode, toastOf(m)], ['start', null])
  tick(m, b.end)
  assert.deepEqual(on(m, b.end), [true, false, b.end])
  assert.deepEqual([m.playback!.mode, m.playback!.slot?.start, toastOf(m)?.message], ['live', b.end, 'Caught up. Back to live.'])
})

test('further behind than the break is long: no break left, it joins what is on', () => {
  const { m, ch, s, b } = setup()
  const late = s.end - s.itemEnd + 120   // started over this long after it began: it ends 2 min into the next program
  setClock(s.start + late); m.tune(ch.id, 'start', s.start)
  tick(m, s.end + 119); assert.deepEqual(on(m, s.end + 119), [false, false, s.start])
  assert.equal(m.playback!.markDue, true, 'no server in this file: its mark is owed')
  assert.deepEqual(on(m, s.end + 120), [true, false, b.start])
  assert.equal(m.watchInfo(s.end + 120)!.position, 120)
  // Before the tick makes it the playback, Play/Pause and Home already act on what is on, not on the program that ended.
  setClock(s.end + 120)
  void m.enteredBackground(); assert.equal(m.playback!.paused, false, 'nothing of the old program is held for Home')
  m.returnedToForeground()
  m.skip(10); assert.deepEqual([m.playback!.mode, m.skipCue], ['start', 0], 'Right at the live edge does nothing, the tick still has its toast to show')
  m.togglePause()
  assert.deepEqual([m.playback!.paused, m.playback!.slot?.start, m.playback!.offset, m.playback!.markDue], [true, b.start, 120, false])   // the mark was owed for the program that ended, not for this one
  m.togglePause(); tick(m, s.end + 121)
  assert.deepEqual(on(m, s.end + 121), [false, false, b.start], 'a pause of the next program, as from live')
  // Left alone, the tick makes it the playback: the next program is what is kept now, joined midway.
  const x = setup().m
  setClock(s.start + late); x.tune(ch.id, 'start', s.start)
  const n = x.tunes
  tick(x, s.end + 120)
  assert.deepEqual([x.playback!.mode, x.playback!.slot?.start, x.playback!.fromStart, toastOf(x)?.message], ['live', b.start, false, 'Caught up. Back to live.'])
  assert.equal(x.tunes, n, 'the slot is in the key the player loads by: one load')
})

test('started before it airs: its break is the channel\'s own once the clock gets to the program\'s end', () => {
  const { m, ch, s, b } = setup()
  const t0 = b.start - 120   // "Watch it now", 2 min before its slot
  setClock(t0); m.tune(ch.id, 'live'); m.startNextFromBreak()
  assert.deepEqual(on(m, t0), [false, false, b.start])
  const ended = t0 + Math.ceil(b.item.runtime)   // on screen; on the clock it runs 2 min more
  tick(m, ended); assert.deepEqual(on(m, ended), [false, true, b.start])
  tick(m, Math.ceil(b.itemEnd) - 1); assert.deepEqual(on(m, Math.ceil(b.itemEnd) - 1), [false, true, b.start])
  assert.equal(m.playback!.mode, 'start'); assert.equal(toastOf(m), null)
  tick(m, Math.ceil(b.itemEnd))
  assert.deepEqual(on(m, Math.ceil(b.itemEnd)), [true, true, b.start]); assert.equal(toastOf(m), null)   // the channel's own break now, and quiet
  tick(m, b.end); assert.deepEqual(on(m, b.end), [true, false, b.end])
  assert.deepEqual([m.playback!.mode, toastOf(m)?.message], ['live', 'Caught up. Back to live.'])
})

test('started hours before it airs: after a break as long as its slot\'s, back to what is on now, and live with its next program', () => {
  const { m, ch, s, b } = setup()
  const later = m.slotOnAir(ch, b.end)!   // two programs on: "Watch now" from the guide
  setClock(s.start + 60); m.tune(ch.id, 'start', later.start)
  const ended = s.start + 60 + Math.ceil(later.item.runtime), over = s.start + 60 + (later.end - later.start)
  assert.ok(over < later.start, 'still before its slot')
  tick(m, ended); assert.deepEqual(on(m, ended), [false, true, later.start])
  tick(m, over - 1); assert.deepEqual(on(m, over - 1), [false, true, later.start])
  const now = m.slotOnAir(ch, over)!
  assert.deepEqual([m.watchInfo(over)!.live, m.watchInfo(over)!.slot.start, m.watchInfo(over)!.position], [true, now.start, over - now.start])
  // In this lineup what is on then is in its own break: quiet until its next program.
  assert.ok(m.watchInfo(over)!.isBreak && now.end < later.start, 'the lineup still has this case')
  tick(m, over); assert.deepEqual([m.playback!.mode, toastOf(m)], ['start', null])
  tick(m, now.end)
  // What is on is what is kept now: the slot left behind must not take the channel over at its own time after a library refresh.
  assert.deepEqual([m.playback!.mode, m.playback!.slot?.start, toastOf(m)?.message], ['live', now.end, 'Caught up. Back to live.'])
  // Its own slot comes round on the clock like any other, from its beginning.
  tick(m, later.start); assert.deepEqual(on(m, later.start), [true, false, later.start]); assert.equal(m.watchInfo(later.start)!.position, 0)
})

test('started before it airs by more than its break: the old way out stays, its last minutes again', () => {
  const { m, ch, s, b } = setup()
  const t0 = s.itemEnd + 5, ahead = b.start - t0
  assert.ok(ahead > b.end - b.itemEnd && ahead < b.end - b.start, 'the lineup still has this case')
  setClock(t0); m.tune(ch.id, 'live'); m.startNextFromBreak()
  const out = t0 + (b.end - b.start)   // its break has run as long as the slot's, the clock still inside the program
  tick(m, out - 1); assert.deepEqual(on(m, out - 1), [false, true, b.start])
  assert.deepEqual(on(m, out), [true, false, b.start]); assert.equal(m.watchInfo(out)!.position, out - b.start)
  const tunes = m.tunes
  tick(m, out); assert.deepEqual([m.playback!.mode, m.tunes], ['live', tunes])   // break to program: the key has changed by itself
})

test('a slot with no break to speak of (packed shorts, a runtime with a fraction): behind, the next one is joined late; ahead, its own program again', () => {
  const { m, ch, s } = setup()
  const short = (id: string) => Object.assign(Object.create(Object.getPrototypeOf(s.item)), s.item, { id, runtime: 120.5 }) as typeof s.item
  // p3 is the last of its group and gets what is left: half a second of break, which no whole-second tick sees.
  const t = T, slots = [new Slot(short('p1'), t, t + 120), new Slot(short('p2'), t + 120, t + 240), new Slot(short('p3'), t + 240, t + 361)]
  m.slotOnAir = (_c, at) => slots.find(x => x.start <= at && at < x.end) ?? null
  m.slot = (_c, start) => slots.find(x => Math.abs(x.start - start) < 1) ?? null
  // 30 s behind: p1 is over with its slot's length, not its runtime, and p2 is joined 30 s in.
  setClock(t + 30); m.tune(ch.id, 'start', t)
  tick(m, t + 149); assert.deepEqual(on(m, t + 149), [false, false, t])
  const n = m.tunes
  tick(m, t + 150); assert.deepEqual(on(m, t + 150), [true, false, t + 120]); assert.equal(m.watchInfo(t + 150)!.position, 30)
  assert.deepEqual([m.playback!.mode, m.tunes], ['live', n])   // another slot: its key loads it, once
  // 60 s ahead: p3 from its beginning at t + 180. Over at t + 301 (its slot's length) with the clock 61 s into it: p3
  // again from there. The key the player loads by has not changed, so the tick asks the stream to move.
  setClock(t + 180); m.tune(ch.id, 'start', t + 240)
  tick(m, t + 300); assert.deepEqual(on(m, t + 300), [false, false, t + 240])
  const tunes = m.tunes
  tick(m, t + 301); assert.deepEqual(on(m, t + 301), [true, false, t + 240]); assert.equal(m.watchInfo(t + 301)!.position, 61)
  assert.deepEqual([m.playback!.mode, m.tunes], ['live', tunes + 1])
})

test('a pause holds everything: a paused break stays past its slot, a paused program however late', () => {
  const { m, ch, s } = setup()
  setClock(s.itemEnd + 5); m.tune(ch.id, 'live'); m.togglePause()   // as the sleep timer does in a break
  tick(m, s.end + 600)
  assert.deepEqual([m.playback!.mode, m.playback!.paused], ['start', true]); assert.deepEqual(on(m, s.end + 600), [false, true, s.start])
  assert.equal(toastOf(m), null)
  setClock(s.start + 60); m.tune(ch.id, 'live'); m.togglePause()
  tick(m, s.end + 600)
  assert.deepEqual(on(m, s.end + 600), [false, false, s.start]); assert.equal(m.watchInfo(s.end + 600)!.position, 60)
})

test('ahead of the clock: a skip moves it 10 s, not back to the clock', () => {
  const { m, ch, b } = setup()
  assert.ok(b.item.runtime > 500)
  // The break's "Watch next": `b` starts five minutes before its slot, so it is still five minutes ahead once the slot airs.
  setClock(b.start - 300); m.tune(ch.id, 'start', b.start)
  setClock(b.start + 120)
  assert.equal(m.watchInfo()!.position, 420)
  m.skip(10); assert.deepEqual([m.playback!.mode, m.watchInfo()!.position], ['start', 430], 'Right: 10 s on, still ahead')
  m.skip(-10); m.skip(-10); assert.deepEqual([m.playback!.mode, m.watchInfo()!.position], ['start', 410], 'Left: 10 s back, still ahead')
  m.togglePause(); m.skip(10); assert.deepEqual([m.playback!.paused, m.playback!.offset], [true, 420], 'and paused it stays paused')
})

test('paused within reach of live: Right goes to the live point at most and holds the pause', () => {
  const { m, ch, s } = setup()
  assert.ok(s.item.runtime > 700)
  setClock(s.start + 600); m.tune(ch.id, 'live')
  m.togglePause()
  setClock(s.start + 605); m.skip(10)
  assert.deepEqual([m.playback!.mode, m.playback!.paused, m.playback!.offset], ['start', true, 605])
  setClock(s.start + 606); m.togglePause()   // Play: on from there, a second behind the clock
  assert.deepEqual([m.watchInfo()!.live, m.watchInfo()!.position], [false, 605])
})
