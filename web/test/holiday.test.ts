/// <reference types="node" />
// HolidayTests.swift. The holiday channel: each day the nearest holiday's films, Groundhog Day back to back on February 2,
// and a lineup that keeps every other channel's number. The calendar is Los Angeles (npm test sets TZ).
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { DemoMediaServer } from '../src/core/DemoServer'
import { ChannelBuilder, GuideGenerator, Holiday } from '../src/core/GuideGenerator'
import { Channel, ChannelDefinition, MediaItem, RuleChip } from '../src/core/Models'
import * as Time from '../src/core/Time'

process.env.TZ = 'America/Los_Angeles'
const date = (y: number, m: number, d: number, h = 12): number => new Date(y, m - 1, d, h).getTime() / 1000
const film = (id: string, title: string, overview: string | null = null, genres: string[] = []) =>
  new MediaItem({ id, kind: 'movie', title, genres, runtime: 5400, overview })

/** Four films for every holiday, by its words alone (no genre or year: they would add shelves of their own), and Groundhog Day. */
const films: MediaItem[] = []
for (const [name, overview] of [['newYear', 'A party on New Year’s Eve.'], ['valentines', 'A Valentine’s card goes astray.'],
  ['stPatricks', 'A leprechaun wants his gold back.'], ['easter', 'The Easter Bunny is missing.'],
  ['july4', 'Fireworks on the Fourth of July.'], ['halloween', 'Trick or treat on the wrong street.'],
  ['thanksgiving', 'Home for Thanksgiving.'], ['christmas', 'Santa Claus is stuck in the chimney.']]) {
  for (let i = 0; i < 4; i++) films.push(film(`${name}${i}`, `Film ${i}`, overview))
}
films.push(film('ghd', 'Groundhog Day'))
const pick = (y: number, m: number, d: number, from: readonly MediaItem[] = films) => Holiday.pick(from, date(y, m, d)).name

test('dates', () => {
  assert.deepEqual([2025, 2026, 2027].map(y => Holiday.date('easter', y).month * 100 + Holiday.date('easter', y).day), [420, 405, 328])
  assert.deepEqual([2025, 2026, 2027].map(y => Holiday.date('thanksgiving', y).day), [27, 26, 25])
  assert.equal(Holiday.dayNumber(1970, 1, 1), 0)
  assert.equal(Holiday.dayNumber(2026, 11, 3), 20_760)
  assert.equal(Holiday.weekday(2026, 11, 3), 2)   // a Tuesday
})

test('seasons', () => {
  assert.equal(pick(2026, 10, 1), 'Halloween')
  assert.equal(pick(2026, 10, 31), 'Halloween')
  assert.equal(pick(2026, 11, 1), 'Thanksgiving')
  assert.equal(pick(2025, 11, 1), 'Thanksgiving')   // with Thanksgiving on the 27th
  assert.equal(pick(2025, 10, 31), 'Halloween')
  assert.equal(pick(2026, 11, 26), 'Thanksgiving')
  assert.equal(pick(2026, 11, 27), 'Christmas')   // the day after Thanksgiving
  assert.equal(pick(2025, 11, 23), 'Thanksgiving')   // Thanksgiving 2025 is the 27th; Christmas's season overlaps
  assert.equal(pick(2026, 12, 25), 'Christmas')
  assert.equal(pick(2026, 12, 26), 'New Year’s')
  assert.equal(pick(2027, 1, 1), 'New Year’s')
  assert.equal(pick(2027, 2, 1), 'Valentine’s Day')
  assert.equal(pick(2027, 2, 14), 'Valentine’s Day')
  assert.equal(pick(2027, 3, 17), 'St. Patrick’s Day')
  assert.equal(pick(2027, 3, 28), 'Easter')
  assert.equal(pick(2027, 7, 4), 'Fourth of July')
  assert.equal(pick(2027, 7, 5), 'Fourth of July')   // between seasons: the nearest one
  assert.equal(pick(2027, 9, 10), 'Halloween')
})

test('Groundhog Day', () => {
  assert.equal(pick(2027, 2, 2), 'Groundhog Day')
  assert.deepEqual(Holiday.pick(films, date(2027, 2, 2)).films.map(it => it.id), ['ghd'])
  assert.equal(pick(2027, 2, 2, films.filter(it => it.id !== 'ghd')), 'Valentine’s Day')   // without the film, the season
  assert.equal(pick(2027, 2, 3), 'Valentine’s Day')
  // The day is the film again and again, with its break between.
  const ch = new Channel(new ChannelDefinition({ id: 'holiday', number: 2, name: 'Holiday Special', tag: '', rule: [RuleChip.holiday] }),
    films)
  const slots = GuideGenerator.schedule(ch, date(2027, 2, 2))
  assert.deepEqual(Array.from(new Set(slots.map(s => s.item.id))), ['ghd'])
  assert.equal(slots[0]?.start, Time.startOfDay(date(2027, 2, 2)))
  assert.equal(slots.length, 12)
  // A cut of the film counts too.
  assert.equal(pick(2027, 2, 2, films.filter(it => it.id !== 'ghd').concat(film('ghd4k', 'Groundhog Day (Remastered)'))), 'Groundhog Day')
  // The day after is Valentine's again.
  assert.ok(GuideGenerator.schedule(ch, date(2027, 2, 3)).every(s => s.item.id.startsWith('valentines')))
})

/** A holiday with too few films sits out: its days go to the nearest one that has enough. */
test('thin holidays sit out', () => {
  const some = films.filter(it => !it.id.startsWith('thanksgiving')).concat(film('tg', 'Pieces of April', 'Thanksgiving dinner.'))
  assert.equal(pick(2026, 11, 10, some), 'Halloween')
  assert.equal(pick(2026, 11, 20, some), 'Christmas')
  const two = films.filter(it => it.id.startsWith('halloween') || it.id.startsWith('christmas'))
  assert.equal(pick(2027, 6, 1, two), 'Halloween')
  assert.equal(pick(2027, 2, 2, two), 'Christmas')
})

/** Romance is Valentine's and horror Halloween's, but not a kids' horror (the `genre` rule's own exception). */
test('genres', () => {
  assert.ok(Holiday.has('valentines', film('r', 'R', null, ['Romance'])))
  assert.ok(Holiday.has('halloween', film('h', 'H', null, ['Horror'])))
  assert.ok(!Holiday.has('halloween', film('k', 'K', null, ['Horror', 'Family'])))
  assert.ok(Holiday.has('halloween', film('k2', 'K2', 'A Halloween night out.', ['Horror', 'Family'])))
  assert.ok(!Holiday.has('christmas', new MediaItem({ id: 'e', kind: 'episode', title: 'A Christmas Special', runtime: 1500 })))   // films only
  assert.ok(!Holiday.has('easter', film('w', 'W', 'Eastern Europe, 1946.')))   // Easter's words are phrases
  assert.ok(!Holiday.has('halloween', film('j', 'J', 'A jack-of-all-trades.')))
  assert.ok(Holiday.has('christmas', film('é', 'É', 'Noël: «Christmas»')))   // after a two-byte non-letter
  assert.ok(!Holiday.has('christmas', film('ü', 'Ü', 'Noëlëchristmas')))   // after a two-byte letter
})

/** The channel goes last, so no other channel's number moves, and only when some holiday has enough films. */
test('lineup', () => {
  const now = date(2026, 12, 1)
  const base = DemoMediaServer.items.filter(it => it.genres.indexOf('Horror') < 0)   // the demo's horror is Halloween's
  const plain = ChannelBuilder.automaticChannels(base, undefined, undefined, undefined, now)
  assert.ok(!plain.some(d => d.id === 'holiday'))
  const festive = ChannelBuilder.automaticChannels(base.concat(films), undefined, undefined, undefined, now)
  const h = festive[festive.length - 1]
  assert.deepEqual([h.id, h.name, h.tag], ['holiday', 'Holiday Special', 'Films for the nearest holiday'])
  assert.deepEqual(h.rule, [RuleChip.holiday])
  assert.deepEqual(h.rule.map(RuleChip.label), ['Nearest holiday'])
  const before = new Map(plain.map(d => [d.id, d.number] as [string, number]))
  for (const d of festive) if (before.has(d.id)) assert.equal(d.number, before.get(d.id), d.id)
  const gap = h.number - festive[festive.length - 2].number
  assert.ok(gap >= 1 && gap <= 3)
  const ch = ChannelBuilder.channelsFrom([h], base.concat(films), now)[0]
  assert.equal(ch.items.length, films.length)   // every holiday's films, Groundhog Day too; the day picks
  assert.ok(!ch.items.some(it => it.kind === 'episode'))
  // Saved as Swift's synthesized Codable writes it, like `unwatched`.
  assert.equal(JSON.stringify(h.rule.map(RuleChip.toJson)), '[{"holiday":{}}]')
  assert.deepEqual(JSON.parse('[{"holiday":{}}]').map(RuleChip.fromJson), h.rule)
})
