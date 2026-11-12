/// <reference types="node" />
// ParityTest.kt: the Swift Core's output for the demo library (parity-fixture.json, written by tools/fixturegen against
// RerunGuideCore). The web port must agree value for value, so a channel airs the same thing at the same minute on an
// Apple TV, a Google TV and an LG or Samsung TV.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import { Bouncer } from '../src/core/Bouncer'
import { DemoMediaServer } from '../src/core/DemoServer'
import { Duplicates } from '../src/core/Duplicates'
import { ChannelBuilder, GuideGenerator, Holiday, SeededGenerator, shuffled } from '../src/core/GuideGenerator'
import { toIntOrNull } from '../src/core/Lang'
import { Channel, ChannelDefinition, LibrarySection, MediaItem, PlayOrder, RuleChip, StableHash, TrackSelection } from '../src/core/Models'
import { SpotRotation } from '../src/core/SpotRotation'
import * as Time from '../src/core/Time'

// Read in place, never copied. Same depth from test/ and .test-build/.
const f = JSON.parse(readFileSync(new URL('../../android/core/src/test/resources/parity-fixture.json', import.meta.url), 'utf8'))
process.env.TZ = f.timeZone   // npm test already runs in Los Angeles; this keeps a bare `node --test` honest
const now: number = f.now

/**
 * The demo's addedAt is relative to the wall clock when the library loads; the fixture ran at `now` (give or take
 * minutes), so pin it there or "Just Added" drifts as the days pass. Every third film is watched (m3, m6, ...), as in
 * fixturegen, so Unwatched is checked too.
 */
const lib = DemoMediaServer.items.map(m => {
  if (m.kind !== 'movie') return m
  const n = toIntOrNull(m.id.slice(1))!
  return m.copy({ addedAt: now - n * 6 * 86_400, watched: n % 3 === 0 })
})

type Row = { [k: string]: any }
const slotRows = (slots: readonly { item: MediaItem; start: number; end: number }[]) => slots.map(s => [s.item.id, s.start, s.end])

test('seeded generator: SplitMix64, Lemire, shuffled', () => {
  const g = new SeededGenerator('parity|2026-10-24')
  assert.deepEqual(Array.from({ length: 8 }, () => g.next().toString()), f.seeded)
  const g2 = new SeededGenerator('shuffle-check')
  assert.deepEqual(shuffled(Array.from({ length: 20 }, (_, i) => i), g2), f.shuffle20)
  const g3 = new SeededGenerator('bounded')
  assert.deepEqual(Array.from({ length: 12 }, (_, i) => g3.nextInt((i + 3) * 7)), f.bounded)
})

test('FNV-1a', () => {
  assert.equal(f.fnv1a.length, 5)
  for (const c of f.fnv1a as Row[]) assert.equal(StableHash.fnv1a(c.s).toString(), c.h, c.s)
})

test('demo items', () => {
  const want: Row[] = f.demoItems
  assert.equal(lib.length, want.length)
  want.forEach((w, i) => {
    const m = lib[i]
    assert.deepEqual([m.id, m.kind, m.title, m.runtime, m.year, m.genres, m.seriesID, m.watched],
      [w.id, w.kind, w.title, w.runtime, w.year ?? null, w.genres, w.seriesID ?? null, w.watched])
  })
})

test('automatic channels', () => {
  const want: Row[] = f.automatic
  const defs = ChannelBuilder.automaticChannels(lib, undefined, undefined, undefined, now)
  assert.deepEqual(defs.map(d => d.id), want.map(w => w.id))
  want.forEach((w, i) => {
    const d = defs[i]
    assert.deepEqual([d.number, d.name, d.tag, d.rule.map(RuleChip.label), PlayOrder.rawValue(d.order)],
      [w.number, w.name, w.tag, w.rule, w.order], w.id)
  })
})

test('channels and three days of slots', () => {
  const want: Row[] = f.channels
  const chans = ChannelBuilder.channelsFrom(ChannelBuilder.automaticChannels(lib, undefined, undefined, undefined, now), lib, now)
    .concat(Channel.scrambled)
  assert.deepEqual(chans.map(c => c.id), want.map(w => w.id))
  const today = Time.startOfDay(now)
  const lineupDays = [0, 1, 2].map(d => GuideGenerator.scheduleLineup(chans, Time.addDays(today, d)))   // one pass a day, as the app
  let slotCount = 0
  want.forEach((w, c) => {
    const ch = chans[c]
    assert.deepEqual(ch.items.map(it => it.id), w.items, ch.id)
    assert.equal(w.days.length, 3)
    ;(w.days as Row[]).forEach((wd, d) => {
      const day = Time.addDays(today, d)
      assert.equal(day, wd.day)
      const got = lineupDays[d].get(ch.id) ?? []
      assert.deepEqual(slotRows(got), (wd.slots as Row[]).map(s => [s.item, s.start, s.end]), `${ch.id} day ${d}`)
      slotCount += got.length
    })
  })
  assert.ok(slotCount > 1000)
})

const demoChannels = () => ChannelBuilder.channelsFrom(ChannelBuilder.automaticChannels(lib, undefined, undefined, undefined, now), lib, now)

test('the tape on its own: two marathons and the two-show Comedy TV shelf over both DST changes and New Year', () => {
  const chans = demoChannels()
  for (const w of f.continuity as Row[]) {
    const ch = chans.find(c => c.id === w.id)!
    for (const wd of w.days as Row[]) assert.deepEqual(slotRows(GuideGenerator.schedule(ch, wd.day)), wd.slots, `${ch.id} ${wd.day}`)
  }
})

const turnsChannel = () => Channel.make('turns', 2, 'Turns', (f.turns.items as Row[]).map(r => new MediaItem({ id: r.id, kind: 'episode',
  title: r.title, seriesTitle: r.seriesTitle, seriesID: r.seriesID, season: r.season, episode: r.episode, runtime: r.runtime })))

test('shows taking turns: four shows handed over interleaved', () => {
  const ch = turnsChannel()
  assert.ok(GuideGenerator.takesTurns(ch))
  for (const wd of f.turns.days as Row[]) assert.deepEqual(slotRows(GuideGenerator.schedule(ch, wd.day)), wd.slots, `turns ${wd.day}`)
})

test('one program on one channel at a time: the order channels give way in, their slots, and no overlap in the rows', () => {
  const films = (f.exclusive.films as Row[]).map(r => new MediaItem({ id: r.id, kind: 'movie', title: r.title, year: r.year, runtime: r.runtime }))
  const chans = demoChannels()
  // And the four-show turns channel behind a marathon of nine episodes of its show B (B1 and B2 shared).
  const b = Array.from({ length: 9 }, (_, i) => new MediaItem({ id: `B${i + 1}`, kind: 'episode', title: `B ${i + 1}`, seriesTitle: 'B',
    seriesID: 'B', season: 1, episode: i + 1, runtime: 1320 }))
  const lineup = [Channel.make('x1', 10, 'X1', films), Channel.make('x2', 11, 'X2', films),
    chans.find(c => c.id === 'series:smh')!, chans.find(c => c.id === 'genre:Comedy:tv')!,
    turnsChannel(), Channel.make('series:B', 30, 'B', b, undefined, 'inOrder')]
  assert.deepEqual(GuideGenerator.dependencyOrder(lineup).map(c => c.id), f.exclusive.order)
  const items = new Map(films.concat(...lineup.map(c => c.items)).map(it => [it.id, it] as const))
  for (const wd of f.exclusive.days as Row[]) {
    const got = GuideGenerator.scheduleLineup(lineup, wd.day)
    const byKey = new Map<string, [string, number, number][]>()
    for (const c of wd.channels as Row[]) {
      assert.deepEqual(slotRows(got.get(c.id)!), c.slots, c.id)
      for (const [id, start, end] of c.slots as [string, number, number][]) {
        const it = items.get(id)!, k = GuideGenerator.repeatKey(it), w: [string, number, number] = [c.id, start, Math.min(end, start + it.runtime)]
        const ws = byKey.get(k); if (ws) ws.push(w); else byKey.set(k, [w])
      }
    }
    // The rule itself, over the fixture's own rows: one item's airing windows never overlap on two channels.
    byKey.forEach((ws, k) => ws.forEach((a, i) => ws.slice(i + 1).forEach(b => {
      if (a[0] !== b[0]) assert.ok(!(a[1] < b[2] && b[1] < a[2]), `${k} ${a} ${b}`)
    })))
  }
})

test('packed short programs, in order and shuffled', () => {
  // Short programs sharing a half hour, with fractional runtimes as servers report them.
  const shorts = [130.7, 245.2, 480.4, 540.9, 701.0, 150.0, 453.3, 720.0, 780.0, 1320.0].map((r, i) => new MediaItem({
    id: `s${i}`, kind: 'episode', title: `S${i}`, seriesTitle: 'Shorts', seriesID: 'shorts', season: 1, episode: i + 1, runtime: r,
  }))
  const chans = [Channel.make('shorts', 2, 'Shorts', shorts, undefined, 'inOrder'), Channel.make('shorts-mix', 3, 'Mix', shorts, undefined, 'shuffle')]
  const today = Time.startOfDay(now)
  chans.forEach((ch, c) => {
    for (let d = 0; d < 3; d++) {
      const got = GuideGenerator.schedule(ch, Time.addDays(today, d))
      assert.deepEqual(slotRows(got), f.packed[c][d], `${ch.id} day ${d}`)
    }
  })
})

test('holidays: Easter, Thanksgiving, two years of days for a full and a thin library, and the channel\'s slots', () => {
  const h = f.holidays
  assert.deepEqual([h.easter.length, h.thanksgiving.length], [41, 41])
  for (const [y, m, d] of h.easter as number[][]) assert.deepEqual(Holiday.date('easter', y), { month: m, day: d }, `Easter ${y}`)
  for (const [y, d] of h.thanksgiving as number[][]) assert.equal(Holiday.date('thanksgiving', y).day, d, `Thanksgiving ${y}`)
  const films = (h.films as Row[]).map(w => new MediaItem({
    id: w.id, kind: 'movie', title: w.title, genres: w.genres, runtime: w.runtime, overview: w.overview === '' ? null : w.overview,
  }))
  const thin = films.filter(it => it.id.startsWith('halloween') || it.id.startsWith('christmas'))
  for (const [library, want] of [[films, h.days], [thin, h.thin]] as [MediaItem[], [number, string, string[]][]][]) {
    assert.equal(want.length, 730)
    for (const [day, name, ids] of want) {
      const p = Holiday.pick(library, day)
      assert.deepEqual([p.name, p.films.map(it => it.id)], [name, ids], new Date(day * 1000).toDateString())
    }
  }
  // What the channel itself airs on days the pick narrows (and on the Groundhog Day loop), slot by slot.
  const ch = new Channel(new ChannelDefinition({ id: 'holiday', number: 2, name: 'Holiday Special', tag: '', rule: [RuleChip.holiday] }), films)
  assert.equal(h.slots.length, 7)
  for (const w of h.slots as Row[]) assert.deepEqual(slotRows(GuideGenerator.schedule(ch, w.day)), w.slots, new Date(w.day * 1000).toDateString())
})

test('duplicates: what the merge keeps, in order, with its show, watched and added', () => {
  const items = (f.dedup.input as Row[]).map(w => new MediaItem({
    id: w.id, kind: w.kind, title: w.title, seriesTitle: w.seriesTitle, seriesID: w.seriesID, season: w.season, episode: w.episode,
    year: w.year, runtime: w.kind === 'movie' ? 6000 : 1320, libraryID: w.libraryID, addedAt: w.addedAt, watched: w.watched,
  }))
  assert.deepEqual(Duplicates.merge(items, new Set(f.dedup.lastResort as string[])).map(m => [m.id, m.seriesID, m.watched, m.addedAt]),
    (f.dedup.merged as Row[]).map(w => [w.id, w.seriesID, w.watched, w.addedAt]))
})

test('bouncer, exact doubles', () => {
  const want: number[][] = f.bouncer
  const b = new Bouncer([1920, 1080], [400, 400], undefined, [300, 200])
  const got: number[][] = []
  for (let i = 1; i <= 60 * 60 * 3; i++) {
    b.step(1 / 60)
    if (i % 600 === 0) got.push([b.time, b.x, b.y, b.vx, b.vy, b.corners])
  }
  assert.equal(got.length, want.length)
  got.forEach((g, i) => { for (let k = 0; k < 6; k++) assert.ok(g[k] === want[i][k], `sample ${i} field ${k}: ${g[k]} vs ${want[i][k]}`) })
})

test('spot rotation', () => {
  const rot = new SpotRotation()
  assert.deepEqual([...['a', 'b', 'a', 'c', 'd', 'd'], ...Array.from({ length: 30 }, (_, i) => `n${i + 1}`)].map(id => rot.next(id)), f.spotRotation)
})

/** Not from the fixture: what the app persists comes back equal (missing keys → defaults). PlexAddress is PlexClient's test. */
test('persisted JSON round trip', () => {
  const rt = (o: object) => JSON.parse(JSON.stringify(o))
  const def = new ChannelDefinition({
    id: 'c', number: 7, name: 'N', tag: 'T', order: 'newestFirst', trailerBreaks: false, isCustom: true, tuneMode: 'start',
    rule: [RuleChip.genre('G'), RuleChip.years(1900, 1969), RuleChip.director('D'), RuleChip.actor('A'), RuleChip.series('s', 'S'),
      RuleChip.year(1985), RuleChip.movies, RuleChip.tv, RuleChip.addedWithin(60), RuleChip.anyGenre(['x', 'y']), RuleChip.keywords(['k'])],
  })
  assert.deepEqual(ChannelDefinition.fromJson(rt(def.toJson())), def)
  assert.deepEqual(ChannelDefinition.fromJson({ id: 'c' }), new ChannelDefinition({ id: 'c', number: 0, name: '', tag: '', rule: [] }))
  for (const m of lib.concat(Channel.scrambled.items)) assert.deepEqual(MediaItem.fromJson(rt(m.toJson())), m)
  const t = new TrackSelection('2', TrackSelection.Subtitle.track('5'))
  assert.deepEqual(TrackSelection.fromJson(rt(t.toJson())), t)
  assert.deepEqual(TrackSelection.fromJson(rt(new TrackSelection().toJson())), new TrackSelection())
  const s: LibrarySection = { id: '1', title: 'Movies', kind: 'movies', itemCount: 3 }
  assert.deepEqual(LibrarySection.fromJson(rt(LibrarySection.toJson(s))), s)
})
