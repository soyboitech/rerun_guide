/// <reference types="node" />
// FreshItemsTests.kt, then the open-the-app check that finds them (AppModel.checkRecentlyAdded, the same in all three
// apps; only this model runs without the app).
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { DemoMediaServer } from '../src/core/DemoServer'
import { Duplicates } from '../src/core/Duplicates'
import { ChannelBuilder } from '../src/core/GuideGenerator'
import { Channel, LibrarySection, MediaItem, ServerKind } from '../src/core/Models'
import * as Time from '../src/core/Time'
import { AppModel } from '../src/app/AppModel'

/** A newly added film passed as `fresh` reaches Just Added and New Releases, but not the genre channel it also matches. */
test('fresh items only reach the new channels', () => {
  const now = 1_800_000_000
  const year = Time.localYear(now)
  const film = (id: string, days: number) => new MediaItem({
    id, kind: 'movie', title: id, year, genres: ['Horror'], runtime: 5400, addedAt: now - days * 86_400,
  })
  const library = Array.from({ length: 6 }, (_, i) => film(`old${i}`, 10))
  const fresh = [film('new', 0)]
  const defs = ChannelBuilder.automaticChannels(library, undefined, undefined, undefined, now)
  const ids = (chs: Channel[], id: string) => chs.find(it => it.id === id)?.items.map(it => it.id) ?? []
  const chs = ChannelBuilder.channels(defs, library, fresh, now)
  assert.ok(ids(chs, 'lead:just-added').indexOf('new') >= 0)
  assert.ok(ids(chs, 'lead:new-movies').indexOf('new') >= 0)
  const shelf = chs.find(it => !ChannelBuilder.isFresh(it.definition) && it.items.some(i => i.genres.indexOf('Horror') >= 0))
  assert.ok(shelf)
  assert.ok(!shelf.items.some(it => it.id === 'new'))
  assert.deepEqual(ChannelBuilder.channels(defs, library, [], now).map(it => it.id), ChannelBuilder.channelsFrom(defs, library, now).map(it => it.id))
})

/** A Plex server with a 4K library, as far as the check can tell: counts its section lists, answers `recent`. */
class Server extends DemoMediaServer {
  readonly kind: ServerKind = 'plex'
  lists = 0
  recent: MediaItem[] = []
  async libraries(): Promise<LibrarySection[]> {
    this.lists++
    return [{ id: 'movies', title: 'Movies', kind: 'movies', itemCount: 2 }, { id: '4k', title: '4K Movies', kind: 'movies', itemCount: 1 }]
  }
  async recentlyAdded(): Promise<MediaItem[]> { return this.recent }
}

/** The library list once, not on every open, and a merge only when the newest items change: a 4K copy merged away
 *  isn't new on every open. */
test('the open-the-app check', async () => {
  const film = (id: string, lib: string, title: string, year: number | null = 1982) =>
    new MediaItem({ id, kind: 'movie', title, year, genres: ['Drama'], runtime: 6000, libraryID: lib })
  const m = new AppModel()
  m.later = () => {}
  const server = new Server()
  m.server = server
  m.library = [film('m1', 'movies', 'The Thing'), film('m2', 'movies', 'Diner')]
  const merge = Duplicates.merge
  let merges = 0
  Duplicates.merge = (...a: Parameters<typeof merge>) => { merges++; return merge(...a) }
  try {
    server.recent = [film('k1', '4k', 'The Thing')]
    await m.checkRecentlyAdded()
    await m.checkRecentlyAdded()
    assert.equal(server.lists, 1)
    assert.equal(merges, 2)   // the first check's two; the second saw the same newest items
    assert.equal(m.freshItems.length, 0)
    server.recent = [film('n1', 'movies', 'Tron'), film('k1', '4k', 'The Thing')]
    await m.checkRecentlyAdded()
    assert.deepEqual(m.freshItems.map(it => it.id), ['n1'])
    // A copy the server hasn't matched yet (a file name, no year) is new; once matched, the same item is a copy.
    server.recent = [film('k2', '4k', 'Diner 2160p', null)]
    await m.checkRecentlyAdded()
    assert.deepEqual(m.freshItems.map(it => it.id), ['k2'])
    server.recent = [film('k2', '4k', 'Diner')]
    await m.checkRecentlyAdded()
    assert.equal(m.freshItems.length, 0)
    assert.equal(server.lists, 1)
  } finally {
    Duplicates.merge = merge
  }
})
