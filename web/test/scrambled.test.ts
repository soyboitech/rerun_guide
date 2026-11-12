/// <reference types="node" />
// ScrambledTests.kt.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { DemoMediaServer } from '../src/core/DemoServer'
import { ChannelBuilder, GuideGenerator } from '../src/core/GuideGenerator'
import { stableSort } from '../src/core/Lang'
import { Channel } from '../src/core/Models'
import { AppModel } from '../src/app/AppModel'

/** Automatic numbering steps over 99, so the scrambled channel always has its number to itself. */
test('99 is reserved', () => {
  const numbers = ChannelBuilder.automaticChannels(DemoMediaServer.items).map(it => it.number)
  assert.ok(numbers.indexOf(Channel.scrambledNumber) < 0)
  assert.deepEqual(stableSort(numbers, (a, b) => a - b), numbers, 'numbers stay increasing around the gap')
  assert.equal(new Set(numbers).size, numbers.length)
})

/** Hour-long slots with no trailer break, a few programs to rotate, and nothing the scheduler can't tile. */
test('scrambled channel shape', () => {
  const ch = Channel.scrambled
  assert.equal(ch.number, 99)
  assert.ok(ch.isScrambled)
  assert.equal(ch.definition.trailerBreaks, false)
  assert.ok(ch.items.length >= 4)
  for (const s of GuideGenerator.schedule(ch, 1_800_000_000)) {
    assert.equal(s.duration, 3600, `${s.item.title} should fill exactly one hour`)
    assert.equal(s.duration, s.item.runtime, 'no pad, so never a break on channel 99')
  }
})

/** A rename, a new number and a reset keep its stand-in listings: resolved from its empty rule, it took the whole library. */
test('editing channel 99 keeps its stand-ins', () => {
  const m = new AppModel()
  m.later = () => {}
  m.library = DemoMediaServer.items
  m.channels = AppModel.resolve(m.library, [], new Map(), []).channels
  const standIns = Channel.scrambled.items.map(i => i.id)
  m.updateChannel(Channel.scrambledID, d => d.copy({ name: 'Static', number: 98 }))
  let ch = m.channel(Channel.scrambledID)!
  assert.deepEqual([ch.name, ch.number, ch.items.map(i => i.id)], ['Static', 98, standIns])
  m.resetChannel(Channel.scrambledID)
  ch = m.channel(Channel.scrambledID)!
  assert.deepEqual([ch.name, ch.number, ch.items.map(i => i.id)], ['Channel 99', 99, standIns])
})
