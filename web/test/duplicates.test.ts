/// <reference types="node" />
// DuplicatesTests.kt: the same film or episode in two libraries is one item: once on every channel, counted once, one show.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { Duplicates } from '../src/core/Duplicates'
import { ChannelBuilder } from '../src/core/GuideGenerator'
import { ChannelDefinition, LibrarySection, MediaItem, RuleChip } from '../src/core/Models'
import * as Time from '../src/core/Time'

const film = (id: string, title: string, year: number | null, o: { lib?: string; watched?: boolean; added?: number } = {}) => new MediaItem({
  id, kind: 'movie', title, year, genres: ['Drama'], runtime: 6000, directors: ['Dee Rector'], libraryID: o.lib ?? 'movies', addedAt: o.added,
  watched: o.watched,
})
const ep = (id: string, show: string, sid: string, s: number, e: number, title: string, lib = 'tv', year = 1990) => new MediaItem({
  id, kind: 'episode', title, seriesTitle: show, seriesID: sid, season: s, episode: e, year, genres: ['Comedy'], runtime: 1320, libraryID: lib,
})
const ids = (items: readonly MediaItem[]) => items.map(it => it.id)

/** The first copy stays (it plays); watched if either copy is, added when the first copy was. */
test('film copies', () => {
  const merged = Duplicates.merge([film('m1', 'The Thing', 1982, { added: 1_000 }), film('u1', 'The thing!', 1982, { lib: '4k', watched: true, added: 2_000 })])
  assert.deepEqual(ids(merged), ['m1'])
  assert.equal(merged[0].libraryID, 'movies')
  assert.equal(merged[0].watched, true)
  assert.equal(merged[0].addedAt, 1_000)
  // The 4K copy came first: it stays, and still dates from the older copy.
  const other = Duplicates.merge([film('u1', 'The Thing', 1982, { lib: '4k', added: 2_000 }), film('m1', 'The Thing', 1982, { added: 1_000 })])
  assert.deepEqual(ids(other), ['u1'])
  assert.equal(other[0].addedAt, 1_000)
  // A copy with no date counts as old: a new copy of an undated film doesn't make it new.
  assert.equal(Duplicates.merge([film('m1', 'The Thing', 1982), film('u1', 'The Thing', 1982, { lib: '4k', added: 2_000 })])[0].addedAt, null)
})

/** A copy in a 4K library plays only when no other library has the film; a film only there still airs. */
test('4K library is last resort', () => {
  const sections: LibrarySection[] = [{ id: '4k', title: '4K Movies', kind: 'movies' }, { id: 'movies', title: 'Movies', kind: 'movies' },
    { id: 'uhd', title: 'Films (UHD)', kind: 'movies' }]
  assert.deepEqual(Duplicates.lastResort(sections), new Set(['4k', 'uhd']))
  const items = [film('u1', 'The Thing', 1982, { lib: '4k', watched: true }), film('u2', 'Alien', 1979, { lib: '4k' }), film('m1', 'The Thing', 1982)]
  const merged = Duplicates.merge(items, Duplicates.lastResort(sections))
  assert.deepEqual(ids(merged), ['m1', 'u2'])
  assert.equal(merged[0].watched, true)
})

/** Two cuts are two films; a remake (another year) is another film; with no year there's no telling, so both stay. */
test('what stays apart', () => {
  const items = [film('a', 'Blade Runner', 1982), film('b', 'Blade Runner (The Final Cut)', 1982),
    film('c', 'The Thing', 1982), film('d', 'The Thing', 2011), film('e', 'Home Video', null), film('f', 'Home Video', null)]
  assert.deepEqual(ids(Duplicates.merge(items)), ['a', 'b', 'c', 'd', 'e', 'f'])
})

/** One item listed twice (two chosen libraries sharing it on Emby or Jellyfin) is once. */
test('same item twice', () => {
  const e = ep('e1', 'Cheers', 's1', 1, 1, 'Give Me a Ring Sometime')
  assert.deepEqual(ids(Duplicates.merge([e, film('m', 'Diner', 1982), e])), ['e1', 'm'])
})

/** A show in two libraries is one show: its copies go, and what only the second library has joins the first's show. */
test('show in two libraries', () => {
  const items = [ep('a1', 'Cheers', 's1', 1, 1, 'Give Me a Ring Sometime'), ep('a2', 'Cheers', 's1', 1, 2, 'Sams Women'),
    ep('b1', 'Cheers', 's9', 1, 1, 'Give Me a Ring Sometime', 'tv2'), ep('b2', 'Cheers', 's9', 1, 2, 'Sam\'s Women', 'tv2'),
    ep('b3', 'Cheers', 's9', 1, 3, 'The Tortelli Tort', 'tv2')]
  const merged = Duplicates.merge(items)
  assert.deepEqual(ids(merged), ['a1', 'a2', 'b3'])
  assert.deepEqual(new Set(merged.map(it => it.seriesID)), new Set(['s1']))
  const marathons = ChannelBuilder.automaticChannels(merged, 3).filter(it => it.tag === 'Marathon')
  assert.deepEqual(marathons.map(it => it.name), ['Cheers'])
})

/** Two shows of one name (the UK and US Office) aren't copies of each other: other episode titles, or the same pilot
 *  title years apart. */
test('shows of one name', () => {
  const items = [ep('uk1', 'The Office', 'uk', 1, 1, 'Downsize'), ep('us1', 'The Office', 'us', 1, 1, 'Pilot'),
    ep('sk1', 'Skins', 'skuk', 1, 1, 'Tony', 'tv', 2007), ep('sk2', 'Skins', 'skus', 1, 1, 'Tony', 'tv', 2011)]
  const merged = Duplicates.merge(items)
  assert.deepEqual(ids(merged), ['uk1', 'us1', 'sk1', 'sk2'])
  assert.deepEqual(merged.map(it => it.seriesID), ['uk', 'us', 'skuk', 'skus'])
})

/** A custom marathon made from the second library's copy of a show still airs once that show is merged into the first. */
test('custom marathon follows merged show', () => {
  const items = [ep('a1', 'Cheers', 's1', 1, 1, 'Give Me a Ring Sometime'), ep('b1', 'Cheers', 's9', 1, 1, 'Give Me a Ring Sometime', 'tv2'),
    ep('b2', 'Cheers', 's9', 1, 2, 'Sams Women', 'tv2')]
  const custom = new ChannelDefinition({ id: 'custom:c', number: 50, name: 'Cheers', tag: 'Marathon', rule: [RuleChip.series('s9', 'Cheers')],
    order: 'inOrder', isCustom: true })
  assert.deepEqual(ids(ChannelBuilder.resolve(custom, Duplicates.merge(items))), ['a1', 'b2'])
})

/** Libraries that come interleaved (one recursive query) still make one show, under the id that turned up first. */
test('interleaved show', () => {
  const items = [ep('b1', 'Cheers', 's9', 1, 1, 'Give Me a Ring Sometime', 'tv2'), ep('a1', 'Cheers', 's1', 1, 1, 'Give Me a Ring Sometime'),
    ep('a2', 'Cheers', 's1', 1, 2, 'Sams Women'), ep('b2', 'Cheers', 's9', 1, 2, 'Sam\'s Women', 'tv2'),
    ep('b3', 'Cheers', 's9', 1, 3, 'The Tortelli Tort', 'tv2')]
  const merged = Duplicates.merge(items)
  assert.deepEqual(ids(merged), ['b1', 'a2', 'b3'])
  assert.deepEqual(new Set(merged.map(it => it.seriesID)), new Set(['s9']))
})

/** A title with no letters or digits says nothing about the film: never merged. */
test('empty title', () => {
  assert.deepEqual(ids(Duplicates.merge([film('x', '?', 1990), film('y', '!', 1990)])), ['x', 'y'])
})

/** A library with a 4K copy of every film builds the same lineup as one without, once merged. */
test('lineup counts films once', () => {
  const now = Time.now()
  const films = Array.from({ length: 6 }, (_, i) => film(`f${i}`, `Film ${i}`, 1980 + i))
  const copies = Array.from({ length: 6 }, (_, i) => film(`k${i}`, `Film ${i}`, 1980 + i, { lib: '4k', added: now }))
  const lineup = (items: readonly MediaItem[]) => ChannelBuilder.automaticChannels(items, undefined, undefined, undefined, now)
  assert.notDeepEqual(lineup(films.concat(copies)), lineup(films))
  assert.deepEqual(lineup(Duplicates.merge(films.concat(copies))), lineup(films))
})
