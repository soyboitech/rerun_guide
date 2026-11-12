/// <reference types="node" />
// The 10 s skip as the player sees it (`AppModel.seek`: it seeks inside the stream, no reload) and the clock following
// the picture once the seek is over (`seekLanded`). The demo lineup at a fixed clock, as in caught-up.
import assert from 'node:assert/strict'
import { after, test } from 'node:test'
import { DemoMediaServer } from '../src/core/DemoServer'
import { ChannelBuilder } from '../src/core/GuideGenerator'
import { AppModel } from '../src/app/AppModel'
import '../src/app/AppModelGuide'
import '../src/app/AppModelWatch'

const realNow = Date.now
if (!('navigator' in globalThis)) Object.defineProperty(globalThis, 'navigator', { configurable: true, value: { language: 'en-US' } })
after(() => { Date.now = realNow })
const setClock = (at: number) => { Date.now = () => at * 1000 }
const loaded = DemoMediaServer.items.find(i => i.id === 'm1')!.addedAt! + 6 * 86_400 + 1
const lineup = ChannelBuilder.channelsFrom(ChannelBuilder.automaticChannels(DemoMediaServer.items, 4, 24, 12, loaded), DemoMediaServer.items, loaded)
const T = new Date(2026, 9, 28, 22, 40).getTime() / 1000

/** A model watching live, ten minutes into a program with more than ten minutes left. */
function setup() {
  const m = new AppModel()
  m.later = () => {}   // no banner or toast timers
  m.channels = lineup
  const { ch, s } = lineup.filter(c => !c.isScrambled).map(ch => ({ ch, s: m.slotOnAir(ch, T)! })).find(({ s }) => s.item.runtime > 1300)!
  setClock(s.start + 600); m.tune(ch.id, 'live')
  return { m, ch, s }
}
const position = (m: AppModel) => m.watchInfo()!.position

test('a skip moves the clock and tells the player how far, with no reload', () => {
  const { m, s } = setup()
  const tunes = m.tunes
  const armed: string[] = []
  m.later = k => { armed.push(k) }
  m.skip(-10)
  assert.deepEqual([m.playback!.mode, position(m), m.seek, m.tunes], ['start', 590, { n: 1, moved: -10, stale: false }, tunes])
  assert.ok(armed.length > 0 && !armed.includes('seek'), 'no reload is timed: that is the screen\'s to ask for, when the player cannot seek')
  setClock(s.start + 602); m.skip(-10); m.skip(-10)
  assert.deepEqual([position(m), m.seek], [572, { n: 3, moved: -30, stale: false }], 'a sum: three presses between two looks are 30 s')
  m.skip(10)
  assert.deepEqual([position(m), m.seek.n, m.seek.moved], [582, 4, -20])
  // Clamped at the start: the player hears how far the program really went.
  setClock(s.start + 2); m.tune(m.playback!.channelID, 'start', s.start); setClock(s.start + 6)
  const before = m.seek
  m.skip(-10)
  assert.deepEqual([position(m), m.seek.n - before.n, m.seek.moved - before.moved], [0, 1, -4])
})

test('ahead to within 5 s of live is live, and the picture goes the whole way', () => {
  const { m, s } = setup()
  m.skip(-10); setClock(s.start + 604); m.seekLanded(3)   // the seek stood for 3 s: 13 s behind live
  assert.equal(position(m), 591)
  m.skip(10)
  assert.deepEqual([m.playback!.mode, m.watchInfo()!.live, m.seek.n], ['live', true, 2])
  assert.ok(Math.abs(m.seek.moved - 3) < 1e-9, 'back 10, ahead 13')
  // Further behind than that, ahead is 10 s. Back never lands on live.
  m.skip(-10); m.skip(-10); m.skip(10)
  assert.deepEqual([m.playback!.mode, position(m)], ['start', 594])
  setClock(s.start + 605); m.skip(-10)
  assert.deepEqual([m.playback!.mode, position(m)], ['start', 585])
  // Not even in a program's first seconds, where 0:00 is within 5 s of live.
  setClock(s.start + 3); m.tune(m.playback!.channelID, 'live'); m.skip(-10)
  assert.deepEqual([m.playback!.mode, position(m)], ['start', 0])
})

test("paused, a skip keeps the stream's age: past stalePause the player is told to ask again, and Play still reloads", () => {
  const { m, s } = setup()
  m.togglePause()
  setClock(s.start + 630); m.skip(-10)
  assert.deepEqual([m.seek.stale, m.playback!.startedAt, m.playback!.offset], [false, s.start + 600, 590])
  setClock(s.start + 661); m.skip(-10)
  assert.deepEqual([m.seek.stale, m.playback!.startedAt, m.playback!.offset], [true, s.start + 600, 580])
  const tunes = m.tunes
  m.togglePause()
  assert.equal(m.tunes, tunes + 1, 'the stream is as old as the pause, whatever was skipped meanwhile')
})

test("the clock follows the picture: back by what the seek took, on by what it overshot, never before the program's start", () => {
  const { m, s } = setup()
  m.skip(-10); setClock(s.start + 603)
  m.seekLanded(2); assert.equal(position(m), 591)
  m.seekLanded(-1.5); assert.equal(position(m), 592.5)
  m.seekLanded(500); assert.equal(position(m), 532.5, 'a minute at most')
  // Paused and live are left alone: a paused stream's age is what Play reloads by.
  m.togglePause(); const age = m.playback!.startedAt
  m.seekLanded(5); assert.deepEqual([m.playback!.offset, m.playback!.startedAt], [532.5, age])
  m.tune(m.playback!.channelID, 'live'); m.seekLanded(5); assert.deepEqual([m.watchInfo()!.live, position(m)], [true, 603])
  // At a program's first seconds the clock stops at 0:00.
  m.tune(m.playback!.channelID, 'start', s.start); setClock(s.start + 604)
  m.seekLanded(5); assert.equal(position(m), 0)
})
