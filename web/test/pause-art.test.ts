/// <reference types="node" />
// The pause rules (Swift AppModel+Watch, which no Swift or Kotlin unit test can reach: their models need the app): the
// progress bar's labels, and the program's art 15 s into a pause. The demo lineup at a fixed clock, as in mark-watched.
import assert from 'node:assert/strict'
import { after, test } from 'node:test'
import { DemoMediaServer } from '../src/core/DemoServer'
import { ChannelBuilder } from '../src/core/GuideGenerator'
import { Channel } from '../src/core/Models'
import { AppModel } from '../src/app/AppModel'
import '../src/app/AppModelGuide'
import { WatchInfo } from '../src/app/AppModelWatch'

const realNow = Date.now
after(() => { Date.now = realNow })
const setClock = (at: number) => { Date.now = () => at * 1000 }
// The lineup as of a second after the demo library loaded: one of its movies sits exactly on Just Added's 60 day line,
// and a real clock read twice puts it in or out by the millisecond (another shuffle, another program on at T).
const loaded = DemoMediaServer.items.find(i => i.id === 'm1')!.addedAt! + 6 * 86_400 + 1
const lineup = ChannelBuilder.channelsFrom(ChannelBuilder.automaticChannels(DemoMediaServer.items, 4, 24, 12, loaded), DemoMediaServer.items, loaded).concat(Channel.scrambled)
const T = new Date(2026, 9, 28, 22, 40).getTime() / 1000

/** A model on the demo lineup, paused a minute into what's on at T (0.4 s past the whole second); `due` is when its art comes. */
function paused(scrambled = false) {
  const m = new AppModel()
  m.later = () => {}   // no banner or toast timers
  m.channels = lineup
  const ch = lineup.find(c => c.isScrambled === scrambled)!
  const s = m.slotOnAir(ch, T)!, t = s.start + 60
  setClock(t + 0.4); m.tune(ch.id, 'live'); m.togglePause()
  m.hideBanner()   // the pause's banner times out after 6 s, long before the art (no timers here)
  return { m, ch, s, t, due: t + 1 + AppModel.pauseArtDelay }
}

test('the bar: m:ss, h:mm:ss, when it ends, and a break keeps the slot times', () => {
  const { ch, s } = paused(), r = s.item.runtime, w = (pos: number) => new WatchInfo(ch, s, pos, true, null).bar(T)
  assert.ok(r > 3735 && s.duration > r)
  assert.equal(w(65).elapsed, '1:05')
  assert.equal(w(3735).elapsed, '1:02:15')
  assert.equal(w(3735).ends, 'Ends 11:35 PM')   // 10:40 PM + the 55:45 left
  assert.deepEqual([w(r).elapsed, w(r).ends], ['9:30', '12:00'])   // the break: the slot's clock times
})

test('the art comes 15 s after the next whole second; Back with it up only puts it away', () => {
  const { m, due } = paused()
  assert.equal(m.pauseArtShown(due - 0.5), false)   // a plain pause + 15 s (t + 15.4) would show it here
  assert.equal(m.pauseArtShown(due), true)
  setClock(due); m.press('back')
  assert.equal(m.screen, 'watch'); assert.equal(m.playback!.paused, true); assert.equal(m.pauseArtShown(due), false)
  m.press('back')
  assert.equal(m.screen, 'guide')
})

test('never on channel 99, so Back there leaves', () => {
  const { m, due } = paused(true)
  assert.equal(m.pauseArtShown(due), false)
  setClock(due); m.press('back')
  assert.equal(m.screen, 'guide')
})

test('a start-over held behind the Home screen shows no art from an earlier pause', async () => {
  const { m, ch, s, t, due } = paused()
  setClock(t); m.tune(ch.id, 'start', s.start); m.togglePause(); m.togglePause()
  setClock(due); await m.enteredBackground()
  assert.equal(m.playback!.paused, true)
  assert.equal(m.pauseArtShown(due), false)
})

test('the banner: none for a show picked in the guide; channel up and typed numbers show it; Back hides it first', () => {
  const m = new AppModel()
  m.later = () => {}
  m.channels = lineup
  const [a, b] = m.visibleChannels
  setClock(m.slotOnAir(b, T)!.start + 60)   // b mid-program, not in a break
  m.tune(a.id, 'live')
  assert.equal(m.bannerVisible, false)   // picked in the guide: the viewer has just read what it is
  m.press('up')
  assert.equal(m.playback!.channelID, b.id); assert.equal(m.bannerVisible, true)   // a change of channel in the player
  m.press('back')
  assert.equal(m.screen, 'watch'); assert.equal(m.bannerVisible, false)
  m.press('back')
  assert.equal(m.screen, 'guide')
  for (const d of String(b.number)) m.pressDigit(Number(d))
  m.commitEntry()
  assert.equal(m.screen, 'watch'); assert.equal(m.bannerVisible, true)   // a typed number names a channel, not what's on it
})
