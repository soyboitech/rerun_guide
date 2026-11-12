/// <reference types="node" />
// Favorites (Swift AppModel, which no Swift or Kotlin unit test can reach: their models need the app): the Favorites
// guide, channel up and down through it in dial order, the guide's focus falling back, and Left out of an emptied guide.
// The demo lineup at a fixed clock (npm test pins Los Angeles time).
import assert from 'node:assert/strict'
import { after, test } from 'node:test'
import { DemoMediaServer } from '../src/core/DemoServer'
import { ChannelBuilder } from '../src/core/GuideGenerator'
import { AppModel } from '../src/app/AppModel'
import '../src/app/AppModelGuide'
import '../src/app/AppModelOverlays'
import '../src/app/AppModelWatch'

const realNow = Date.now
const t = new Date(2026, 9, 28, 22, 40).getTime() / 1000
Date.now = () => t * 1000
after(() => { Date.now = realNow })
const lineup = ChannelBuilder.channelsOf(DemoMediaServer.items)

test('the Favorites guide: starred and not hidden, surfed in dial order, and Left still opens Options once it empties', () => {
  const m = new AppModel()
  m.later = () => {}
  m.channels = lineup
  const [a, b, c, d] = [lineup[1], lineup[2], lineup[4], lineup[7]]
  for (const ch of [a, c, d]) m.setFavorite(ch.id, true)
  m.setHidden(d.id, true)
  m.setGuideFilter('favorites')
  assert.deepEqual(m.visibleChannels.map(ch => ch.id), [a.id, c.id])

  m.tune(a.id, 'live'); m.press('up')
  assert.equal(m.playback!.channelID, c.id)
  m.flip(1); assert.equal(m.playback!.channelID, a.id)   // wraps
  m.flip(-1); assert.equal(m.playback!.channelID, c.id)
  m.tune(b.id, 'live'); m.flip(1); assert.equal(m.playback!.channelID, c.id)   // typed in: the next favorite up the dial
  m.tune(b.id, 'live'); m.flip(-1); assert.equal(m.playback!.channelID, a.id)

  m.toGuide(b.id)
  assert.equal(m.focused, null); assert.equal(m.guideKey()!.channelID, a.id)
  m.focused = m.guideKey(); m.setFavorite(a.id, false)
  assert.equal(m.guideKey()!.channelID, c.id)   // un-starred under the focus: the first favorite left
  m.setFavorite(c.id, false)
  assert.equal(m.visibleChannels.length, 0); assert.equal(m.guideKey(), null); assert.ok(m.noFavorites)
  m.remoteHeld = true; m.press('left')
  assert.equal(m.overlay?.kind, 'options')

  m.setGuideFilter('all'); m.openOptions()
  m.press('down'); m.press('down'); m.press('down'); m.press('select')   // Guide(1) → Favorites(4)
  assert.equal(m.guideFilter, 'favorites')
})
