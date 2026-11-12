// Port of android/core GuideGenerator.kt: ChannelBuilder, SeededGenerator, `shuffled(using:)`, GuideGenerator and Holiday.
// Kotlin overloads get the README's names: `scheduleRange`, `channelsFrom` / `channelsOf`, `nextBelow`. The calendar is the
// device's time zone (core/Time.ts), so Kotlin's `calendar: ZoneId` parameters are gone.
import { compareValues, stableSort } from './Lang'
import {
  Channel, ChannelDefinition, MediaItem, PlayOrder, ProgramStatus, RuleChip, Slot, StableHash, swiftCompare,
} from './Models'
import * as Time from './Time'
import { Instant } from './Time'

// ---- ChannelBuilder: turns a flat library into channel definitions and resolves definitions back into items ----

type Names = { readonly movies: readonly [string, string]; readonly tv: readonly [string, string]; readonly mixed: readonly [string, string] }
const n = (mn: string, md: string, tn: string, td: string, xn: string, xd: string): Names =>
  ({ movies: [mn, md], tv: [tn, td], mixed: [xn, xd] })

const retroTable = new Map<string, Names>([
  ['action', n('Adrenaline', 'Action films', 'Stunt Hour', 'Action TV', 'Adrenaline', 'Action')],
  ['action & adventure', n('Thrill Ride', 'Action & adventure films', 'Thrill Ride', 'Action & adventure TV', 'Thrill Ride', 'Action & adventure')],
  ['adventure', n('The Matinee', 'Adventure films', 'Wide World', 'Adventure TV', 'The Matinee', 'Adventure')],
  ['animation', n('The Big Cartoon', 'Animated films', 'Toon Block', 'Cartoons', 'Toon Block', 'Animation')],
  ['anime', n('Anime Features', 'Anime films', 'Anime Block', 'Anime', 'Anime Block', 'Anime')],
  ['biography', n('Life Stories', 'Biopics', 'Portraits', 'Biographies', 'Life Stories', 'Biographies')],
  ['children', n('Kids’ Matinee', 'Kids’ films', 'After School', 'Kids’ TV', 'After School', 'Kids')],
  ['kids', n('Kids’ Matinee', 'Kids’ films', 'After School', 'Kids’ TV', 'After School', 'Kids')],
  ['comedy', n('Funny Business', 'Comedy films', 'Studio Audience', 'Sitcoms', 'Studio Audience', 'Comedy')],
  ['crime', n('Mean Streets', 'Crime films', 'Gumshoe', 'Detectives', 'Gumshoe', 'Crime')],
  ['documentary', n('True Stories', 'Documentaries', 'Field Notes', 'Documentary TV', 'True Stories', 'Documentaries')],
  ['drama', n('The Picture Show', 'Drama films', 'Prime Time', 'Drama series', 'Prime Time', 'Drama')],
  ['family', n('Family Hour', 'Family films', 'Family Room', 'Family TV', 'Family Hour', 'Family')],
  ['fantasy', n('Once Upon', 'Fantasy films', 'The Realm', 'Fantasy TV', 'Once Upon', 'Fantasy')],
  ['food', n('Dinner Bell', 'Food', 'Dinner Bell', 'Food TV', 'Dinner Bell', 'Food')],
  ['game show', n('Game Night', 'Game shows', 'Game Night', 'Game shows', 'Game Night', 'Game shows')],
  ['history', n('Days Gone By', 'History films', 'The Archive', 'History TV', 'Days Gone By', 'History')],
  ['holiday', n('Yule Log', 'Holiday films', 'Tinsel Time', 'Holiday TV', 'Yule Log', 'Holiday')],
  ['home and garden', n('Open House', 'Home & garden', 'Open House', 'Home & garden', 'Open House', 'Home & garden')],
  ['horror', n('Fright Night', 'Horror films', 'Chiller', 'Horror TV', 'Fright Night', 'Horror')],
  ['martial arts', n('Kung Fu Theater', 'Martial arts', 'Kung Fu Theater', 'Martial arts', 'Kung Fu Theater', 'Martial arts')],
  ['mini-series', n('The Miniseries', 'Mini-series', 'The Miniseries', 'Mini-series', 'The Miniseries', 'Mini-series')],
  ['music', n('The Jukebox', 'Music films', 'Video Hour', 'Music TV', 'The Jukebox', 'Music')],
  ['musical', n('Showtunes', 'Musicals', 'Showtunes', 'Musicals', 'Showtunes', 'Musicals')],
  ['mystery', n('Whodunit', 'Mystery films', 'Case Files', 'Mystery TV', 'Whodunit', 'Mysteries')],
  ['news', n('Newsroom', 'News', 'Newsroom', 'News', 'Newsroom', 'News')],
  ['reality', n('Real Life', 'Reality TV', 'Real Life', 'Reality TV', 'Real Life', 'Reality TV')],
  ['romance', n('Date Night', 'Romance films', 'Love Lines', 'Romance TV', 'Date Night', 'Romance')],
  ['sci-fi', n('Final Frontier', 'Sci-fi films', 'Space Age', 'Sci-fi TV', 'Space Age', 'Sci-fi')],
  ['science fiction', n('Final Frontier', 'Sci-fi films', 'Space Age', 'Sci-fi TV', 'Space Age', 'Sci-fi')],
  ['soap', n('Daytime', 'Soaps', 'Daytime', 'Soaps', 'Daytime', 'Soaps')],
  ['sport', n('Game Day', 'Sports films', 'Sports Desk', 'Sports TV', 'Game Day', 'Sports')],
  ['sports', n('Game Day', 'Sports films', 'Sports Desk', 'Sports TV', 'Game Day', 'Sports')],
  ['superhero', n('Capes & Cowls', 'Superhero films', 'Secret Identity', 'Superhero TV', 'Capes & Cowls', 'Superheroes')],
  ['suspense', n('Nail Biter', 'Suspense films', 'Held Breath', 'Suspense TV', 'Nail Biter', 'Suspense')],
  ['talk show', n('Late Night', 'Talk shows', 'Late Night', 'Talk shows', 'Late Night', 'Talk shows')],
  ['thriller', n('Edge of Your Seat', 'Thrillers', 'Cliffhanger', 'Thriller TV', 'Edge of Your Seat', 'Thrillers')],
  ['travel', n('Passport', 'Travel films', 'Road Trip', 'Travel TV', 'Passport', 'Travel')],
  ['war', n('The Front', 'War films', 'War Room', 'War TV', 'The Front', 'War')],
  ['western', n('Dusty Trails', 'Westerns', 'The Frontier', 'Western TV', 'Dusty Trails', 'Westerns')],
])

const min = (a: readonly number[]): number => a.reduce((x, y) => Math.min(x, y))
const max = (a: readonly number[]): number => a.reduce((x, y) => Math.max(x, y))
const yearsOf = (items: readonly MediaItem[]): number[] => {
  const out: number[] = []
  for (const i of items) if (i.year != null) out.push(i.year)
  return out
}
const zeroPad = (v: number, width: number): string => String(v).padStart(width, '0')

/**
 * The automatic channel lineup. Up front, when the library has enough for them: New Releases (films from this year and last),
 * New This Season (TV from this year and last), Just Added (anything added in the last 60 days), Unwatched (films the
 * signed-in user hasn't seen), then the classic channels (TV and films from before 1970). After that every genre, theme,
 * marathon, director, actor and year channel, scattered with a fixed seed so the lineup feels like cable, not an
 * alphabetical list, yet is identical on every device.
 * Genre channels get retro names ("Studio Audience", "Gumshoe", "Toon Block"); unknown genres keep their own name.
 * No channel mixes films and TV: a genre gets a films channel with ≥ `minItems` films and a TV channel with
 * ≥ `minItems` episodes, and director, actor and year channels are films. Only the biggest groups make the lineup
 * (`maxSeries` marathons, `maxPeople` directors and actors, 3 years).
 */
function automaticChannels(from: readonly MediaItem[], minItems = 4, maxSeries = 24, maxPeople = 12,
                           now: Instant = Time.now()): ChannelDefinition[] {
  const library = from
  const def = (id: string, name: string, tag: string, rule: readonly RuleChip[], order: PlayOrder = 'shuffle') =>
    new ChannelDefinition({ id, number: 0, name, tag, rule, order })
  const span = (items: readonly MediaItem[]): RuleChip[] => {
    const years = yearsOf(items)
    return years.length === 0 ? [] : [RuleChip.years(Math.trunc(min(years) / 10) * 10, max(years))]
  }
  const count = (rule: readonly RuleChip[]): number => library.filter(i => rule.every(c => matches(c, i, now))).length

  // Lead channels.
  const year = Time.localYear(now)
  const lead: ChannelDefinition[] = []
  const leads: [string, string, string, RuleChip[], PlayOrder][] = [
    ['lead:new-movies', 'New Releases', `Films from ${year - 1}–${year}`, [RuleChip.years(year - 1, year), RuleChip.movies], 'newestFirst'],
    ['lead:new-tv', 'New This Season', `TV from ${year - 1}–${year}`, [RuleChip.years(year - 1, year), RuleChip.tv], 'shuffle'],
    ['lead:just-added', 'Just Added', 'Films new on the server', [RuleChip.addedWithin(60), RuleChip.movies], 'shuffle'],
    ['lead:unwatched', 'Unwatched', 'Films you haven’t seen', [RuleChip.unwatched, RuleChip.movies], 'shuffle'],
    ['lead:just-added-tv', 'Fresh Episodes', 'TV new on the server', [RuleChip.addedWithin(60), RuleChip.tv], 'shuffle'],
    ['lead:classic-tv', 'Front Porch', 'Classic TV, before 1970', [RuleChip.years(1900, 1969), RuleChip.tv], 'shuffle'],
    ['lead:classic-movies', 'The Vault', 'Classic films, before 1970', [RuleChip.years(1900, 1969), RuleChip.movies], 'shuffle'],
  ]
  for (const [id, name, tag, rule, order] of leads) if (count(rule) >= minItems) lead.push(def(id, name, tag, rule, order))

  // Map, never {}: genre/person names like "constructor" and numeric Plex ids would break a plain object.
  const byGenre = new Map<string, MediaItem[]>()
  const bySeries = new Map<string, [string, MediaItem[]]>()
  const byDirector = new Map<string, number>()
  const byActor = new Map<string, number>()
  const byYear = new Map<number, number>()
  for (const item of library) {
    for (const g of item.genres) {
      const list = byGenre.get(g)
      if (list) list.push(item)
      else byGenre.set(g, [item])
    }
    if (item.kind === 'episode') {
      const key = item.seriesID ?? item.seriesTitle
      if (key == null) continue
      const entry = bySeries.get(key)
      if (entry) entry[1].push(item)
      else bySeries.set(key, [item.seriesTitle ?? key, [item]])
    } else {
      for (const d of item.directors) byDirector.set(d, (byDirector.get(d) ?? 0) + 1)
      for (const a of item.actors) byActor.set(a, (byActor.get(a) ?? 0) + 1)
      if (item.year != null) byYear.set(item.year, (byYear.get(item.year) ?? 0) + 1)
    }
  }

  let genres: ChannelDefinition[] = []
  byGenre.forEach((all, g) => {
    if (all.length < minItems) return
    const items = all.filter(it => matches(RuleChip.genre(g), it, now))   // what the channel will really air (kids' titles leave horror)
    const movies = items.filter(it => it.kind === 'movie')
    const eps = items.filter(it => it.kind === 'episode')
    if (movies.length >= minItems) {
      const [mn, md] = retroName(g, 'movies')
      genres.push(def(`genre:${g}:movies`, mn, decadeTag(md, yearsOf(movies)), [RuleChip.genre(g), ...span(movies), RuleChip.movies]))
    }
    if (eps.length >= minItems) {
      const [tn, td] = retroName(g, 'tv')
      genres.push(def(`genre:${g}:tv`, tn, decadeTag(td, yearsOf(eps)), [RuleChip.genre(g), ...span(eps), RuleChip.tv]))
    }
  })
  // Two channels with the same retro name (two genres mapping to one, or a genre missing from the table) get told apart by what's on them.
  const names = new Map<string, number>()
  for (const gd of genres) names.set(gd.name, (names.get(gd.name) ?? 0) + 1)
  genres = genres.map(gd => {
    if ((names.get(gd.name) ?? 0) < 2) return gd
    const kind = gd.rule.some(c => c.kind === 'tv') ? 'TV' : gd.rule.some(c => c.kind === 'movies') ? 'Films'
      : gd.id.split(':').filter(s => s !== '').slice(1)[0] ?? ''
    return gd.copy({ name: gd.name + ` (${kind})` })
  })
  // Themed channels: a keyword search within a few related genres, for what no genre tag covers.
  const themes = [
    def('theme:monsters', 'Creature Feature', 'Monster movies',
      [RuleChip.movies, RuleChip.anyGenre(monsterGenres), RuleChip.keywords(monsterWords)]),
  ].filter(t => count(t.rule) >= minItems)
  const seriesEntries: [string, [string, MediaItem[]]][] = []
  bySeries.forEach((v, k) => { if (v[1].length >= minItems) seriesEntries.push([k, v]) })
  const series = stableSort(seriesEntries, (a, b) => a[1][1].length !== b[1][1].length ? b[1][1].length - a[1][1].length : swiftCompare(a[0], b[0]))
    .slice(0, maxSeries)
    .map(([key, [title]]) => def(`series:${key}`, title, 'Marathon', [RuleChip.series(key, title)], 'inOrder'))
  const top = (counts: Map<string, number>): string[] => {
    const entries: [string, number][] = []
    counts.forEach((c, k) => { if (c >= minItems) entries.push([k, c]) })
    return stableSort(entries, (a, b) => a[1] !== b[1] ? b[1] - a[1] : swiftCompare(a[0], b[0])).slice(0, maxPeople).map(e => e[0])
  }
  const directors = top(byDirector).map(it => def(`director:${it}`, it, 'Director', [RuleChip.director(it), RuleChip.movies]))
  const actors = top(byActor).map(it => def(`actor:${it}`, it, 'Actor', [RuleChip.actor(it), RuleChip.movies]))
  const yearEntries: [number, number][] = []
  byYear.forEach((c, y) => { if (c >= minItems) yearEntries.push([y, c]) })
  const years = stableSort(yearEntries, (a, b) => a[1] !== b[1] ? b[1] - a[1] : compareValues(a[0], b[0])).slice(0, 3)
    .map(([y]) => def(`year:${y}`, 'Class of ’' + zeroPad(y % 100, 2), `Films from ${y}`, [RuleChip.year(y), RuleChip.movies]))

  // Scatter the rest with a fixed seed: same channels → same order on every device and launch.
  const rng = new SeededGenerator('retro-binge-dial')
  const rest = shuffled(stableSort([...genres, ...themes, ...series, ...directors, ...actors, ...years], (a, b) => swiftCompare(a.id, b.id)), rng)
  const all = [...lead, ...rest]
  // Last, so it renumbers nothing: films for the nearest holiday, picked day by day (`Holiday`). The tag stays put: a
  // lineup built on February 1 can still be up on the 2nd.
  if (Holiday.entries.some(h => library.filter(i => Holiday.has(h, i)).length >= Math.max(minItems, Holiday.minFilms))) {
    all.push(def('holiday', 'Holiday Special', 'Films for the nearest holiday', [RuleChip.holiday]))
  }
  const three = BigInt(3)
  let num = 0
  for (let i = 0; i < all.length; i++) {
    num = i === 0 ? 2 : num + 1 + Number(StableHash.fnv1a(all[i].id) % three)
    if (num === Channel.scrambledNumber) num += 1   // 99 belongs to the scrambled channel
    all[i] = all[i].copy({ number: num })
  }
  return all
}

/**
 * Retro channel names for the common genres ("Studio Audience", "Gumshoe"). Returns (name, descriptor);
 * the descriptor becomes the tag with the decade span appended. Unknown genres fall back to the genre itself.
 */
function retroName(genre: string, kind: ChannelBuilder.ShelfKind): readonly [string, string] {
  const e = retroTable.get(genre.toLowerCase())
  if (e != null) return e[kind]
  switch (kind) {
    case 'movies': return [`${genre} Movies`, `${genre} films`]
    case 'tv': return [`${genre} TV`, `${genre} TV`]
    case 'mixed': return [genre, genre]
  }
}

/**
 * Items matching every chip of the rule, in the sequence the channel's `order` wants
 * (`inOrder`: season/episode then year; `newestFirst`: year descending; `shuffle`: library order, shuffled per day by the scheduler,
 * or on the tape with the shows taking turns when it is episodes of two or more shows).
 */
function resolve(definition: ChannelDefinition, library: readonly MediaItem[], now: Instant = Time.now()): MediaItem[] {
  // A marathon whose show's copies were merged under another library's (`Duplicates`) follows it by title.
  // ponytail: a show gone from the library hands its chip to another of the same name, if any; say so if it bites.
  const rule = definition.rule.map(chip => {
    if (chip.kind !== 'series' || library.some(it => it.seriesID === chip.id)) return chip
    const moved = library.find(it => it.seriesTitle === chip.title && it.seriesID != null)?.seriesID
    return moved == null ? chip : RuleChip.series(moved, chip.title)
  })
  const items = library.filter(item => rule.every(c => matches(c, item, now)))
  switch (definition.order) {
    case 'shuffle': return items
    case 'inOrder': return stableSort(items, episodeOrder)
    case 'newestFirst': return stableSort(items, (a, b) => compareValues(b.year ?? 0, a.year ?? 0) || swiftCompare(b.title, a.title))
  }
}

/** In order: season, episode, then year and title. */
function episodeOrder(a: MediaItem, b: MediaItem): number {
  return compareValues(a.season ?? 0, b.season ?? 0) || compareValues(a.episode ?? 0, b.episode ?? 0) ||
    compareValues(a.year ?? 0, b.year ?? 0) || swiftCompare(a.title, b.title)
}

function matches(chip: RuleChip, item: MediaItem, now: Instant = Time.now()): boolean {
  switch (chip.kind) {
    case 'addedWithin': return item.addedAt != null && item.addedAt >= now - chip.days * 86_400
    case 'genre': return item.genres.indexOf(chip.value) >= 0 && !(grownUpGenres.indexOf(chip.value.toLowerCase()) >= 0 && isForKids(item))
    case 'years': return item.year != null && item.year >= chip.from && item.year <= chip.to
    case 'director': return item.directors.indexOf(chip.name) >= 0
    case 'actor': return item.actors.indexOf(chip.name) >= 0
    case 'series': return item.seriesID === chip.id || (item.seriesID == null && item.seriesTitle === chip.title)
    case 'year': return item.year === chip.value
    case 'movies': return item.kind === 'movie'
    case 'tv': return item.kind === 'episode'
    case 'anyGenre': return item.genres.some(g => chip.genres.indexOf(g) >= 0)
    case 'keywords': return mentions(item, chip.words)
    case 'unwatched': return !item.watched
    case 'holiday': return Holiday.isGroundhogDay(item) || Holiday.entries.some(h => Holiday.has(h, item))
  }
}

const letter = /\p{L}/u

/** Genres whose channels stay grown-up: a kids' title tagged with one (the animated Gremlins series is "Horror") is left off. */
const grownUpGenres: readonly string[] = ['horror', 'thriller']

/**
 * Made for children: tagged Children, Kids or Family, rated for kids, or animated without a rating for older viewers
 * (an adult animated horror like Love, Death & Robots is TV-MA and stays).
 * ponytail: US ratings only; another country's rating on an animated title counts as not older.
 */
function isForKids(item: MediaItem): boolean {
  const genres = item.genres.map(g => g.toLowerCase())
  const rating = item.contentRating?.toUpperCase() ?? null
  if (genres.some(g => g === 'children' || g === 'kids' || g === 'family')) return true
  if (rating != null && ['TV-Y', 'TV-Y7', 'TV-Y7-FV', 'TV-G', 'G'].indexOf(rating) >= 0) return true
  return genres.indexOf('animation') >= 0 && !(rating != null && ['TV-14', 'TV-MA', 'PG-13', 'R', 'NC-17'].indexOf(rating) >= 0)
}

/** Word-start, case-insensitive search of the title and overview: "creature" takes "creatures", not "procreature". */
function mentions(item: MediaItem, any: readonly string[]): boolean {
  const text = (item.title + ' ' + (item.overview ?? '')).toLowerCase()
  return any.some(w => {
    if (w === '') return false   // Foundation finds no range for an empty needle (JS indexOf('') is 0: every item would match)
    let from = 0
    for (;;) {
      const r = text.indexOf(w, from)
      if (r < 0) break
      if (r === 0 || !letter.test(String.fromCodePoint(codePointBefore(text, r)))) return true
      from = r + w.length
    }
    return false
  })
}

/** Java `String.codePointBefore`: the code point ending at `i`, stepping back over a surrogate pair. */
function codePointBefore(s: string, i: number): number {
  const pair = i >= 2 ? s.codePointAt(i - 2)! : 0
  return pair > 0xffff ? pair : s.charCodeAt(i - 1)
}

/**
 * The keywords for "Creature Feature": lowercase, word-start prefixes ("werewol" takes werewolf and werewolves).
 * "shark" alone matches loan sharks and shark-infested waters; "great white" is the one that eats people.
 */
const monsterWords: readonly string[] = ['monster', 'kaiju', 'godzilla', 'king kong', 'kong:', 'creature', 'werewol', 'vampire', 'zombie',
  'frankenstein', 'dracula', 'mummy', 'dinosaur', 'great white', 'megalodon', 'gremlin', 'xenomorph',
  'kraken', 'leviathan', 'cryptid', 'sasquatch', 'bigfoot', 'swamp thing']
/** The genres searched for those keywords: Fantasy would add Terabithia and Spirited Away; Action/Adventure adds Jurassic Park and Kong. */
const monsterGenres: readonly string[] = ['Horror', 'Science Fiction', 'Sci-Fi', 'Action', 'Adventure']

const freshIDs = ['lead:new-movies', 'lead:new-tv', 'lead:just-added', 'lead:just-added-tv']

/**
 * The "what's new" channels: New Releases, New This Season, Just Added, and any channel with an "Added in the last N
 * days" chip. They also see the items `MediaServer.recentlyAdded` found since the last full library load.
 */
function isFresh(d: ChannelDefinition): boolean {
  return freshIDs.indexOf(d.id) >= 0 || d.rule.some(c => c.kind === 'addedWithin')
}

/**
 * `channelsFrom(definitions, library, now)`, with `fresh` (newly added items not yet in `library`) given to the `isFresh`
 * channels only: every other channel keeps resolving from `library`, so its lineup for the day holds still until the next
 * full load.
 */
function channels(definitions: readonly ChannelDefinition[], library: readonly MediaItem[], fresh: readonly MediaItem[],
                  now: Instant = Time.now()): Channel[] {
  if (fresh.length === 0) return channelsFrom(definitions, library, now)
  return channelsFrom(definitions.filter(d => !isFresh(d)), library, now)
    .concat(channelsFrom(definitions.filter(isFresh), library.concat(fresh), now))
}

/** Kotlin `channels(definitions, library, now)`: resolve definitions against the library, dropping channels with nothing to air. */
function channelsFrom(definitions: readonly ChannelDefinition[], library: readonly MediaItem[], now: Instant = Time.now()): Channel[] {
  const out: Channel[] = []
  for (const d of definitions) {
    const items = resolve(d, library, now)
    if (items.length > 0) out.push(new Channel(d, items))
  }
  return out
}

/** Kotlin `channels(from, minItems)`. Convenience: automatic channels resolved. Used by tests. */
function channelsOf(from: readonly MediaItem[], minItems = 4): Channel[] {
  return channelsFrom(automaticChannels(from, minItems), from)
}

/** Names with enough in the library to fill an evening, for the "New channel" picker. Sorted by count desc, then name. */
function candidates(kind: ChannelBuilder.CandidateKind, library: readonly MediaItem[], minItems = 3): ChannelBuilder.Candidate[] {
  const counts = new Map<string, [string | null, number]>()
  const bump = (key: string, id: string | null) => {
    const c = counts.get(key)
    counts.set(key, [c?.[0] ?? id, (c?.[1] ?? 0) + 1])
  }
  for (const item of library) {
    switch (kind) {
      case 'director': if (item.kind === 'movie') for (const d of item.directors) bump(d, null); break
      case 'actor': if (item.kind === 'movie') for (const a of item.actors) bump(a, null); break
      case 'series': { const t = item.seriesTitle; if (item.kind === 'episode' && t != null) bump(t, item.seriesID) }
    }
  }
  const out: ChannelBuilder.Candidate[] = []
  counts.forEach(([id, count], name) => { if (count >= minItems) out.push({ name, id, count }) })
  return stableSort(out, (a, b) => a.count !== b.count ? b.count - a.count : swiftCompare(a.name, b.name))
}

function decadeTag(genre: string, years: readonly number[]): string {
  if (years.length === 0) return genre
  const lo = min(years)
  const hi = max(years)
  // "80s" for the 1900s, "2010s" from 2000 on, so "50s–2020s" can't be read as the 1920s.
  const d = (y: number) => y < 2000 ? `${Math.trunc(y % 100 / 10) * 10}s` : `${Math.trunc(y / 10) * 10}s`
  return `${genre}, ` + (Math.trunc(lo / 10) === Math.trunc(hi / 10) ? d(lo) : `${d(lo)}–${d(hi)}`)
}

export const ChannelBuilder = {
  automaticChannels, retroName, resolve, episodeOrder, matches, mentions, monsterWords, monsterGenres, isFresh,
  channels, channelsFrom, channelsOf, candidates, decadeTag,
  CandidateKind: {
    entries: ['director', 'actor', 'series'] as readonly ChannelBuilder.CandidateKind[],
    rawValue(k: ChannelBuilder.CandidateKind): string {
      return k === 'director' ? 'Director' : k === 'actor' ? 'Actor' : 'Show marathon'
    },
  },
}
export namespace ChannelBuilder {
  export type ShelfKind = 'movies' | 'tv' | 'mixed'
  export type CandidateKind = 'director' | 'actor' | 'series'
  export interface Candidate {
    readonly name: string
    readonly id: string | null
    readonly count: number
  }
}

// ---- SeededGenerator: FNV-1a 64 of a string seeding SplitMix64. Stable across processes and devices ----
// 64-bit wrapping maths (Swift &+ / &*, Kotlin ULong) in BigInt, cut back to 64 bits after every add and multiply.

const u64 = (x: bigint): bigint => BigInt.asUintN(64, x)
const zero = BigInt(0)
const golden = BigInt('0x9e3779b97f4a7c15')
const mix1 = BigInt('0xbf58476d1ce4e5b9')
const mix2 = BigInt('0x94d049bb133111eb')
const s27 = BigInt(27)
const s30 = BigInt(30)
const s31 = BigInt(31)
const s64 = BigInt(64)

export class SeededGenerator {
  private state: bigint

  constructor(seed: string) {
    this.state = StableHash.fnv1a(seed)
  }

  next(): bigint {
    this.state = u64(this.state + golden)
    let z = this.state
    z = u64((z ^ (z >> s30)) * mix1)
    z = u64((z ^ (z >> s27)) * mix2)
    return z ^ (z >> s31)
  }

  /** Kotlin `next(upperBound)`, Swift's `RandomNumberGenerator.next(upperBound:)`: Lemire's nearly divisionless method, same draws, same result. */
  nextBelow(upperBound: bigint): bigint {
    if (upperBound === zero) throw new Error('upperBound cannot be zero.')
    let random = this.next()
    let low = u64(random * upperBound)
    if (low < upperBound) {
      const t = u64(zero - upperBound) % upperBound
      while (low < t) {
        random = this.next()
        low = u64(random * upperBound)
      }
    }
    return (random * upperBound) >> s64   // Kotlin's multiplyHighUnsigned: BigInt holds the whole 128-bit product
  }

  /** Swift's `Int.random(in: 0..<until, using:)`. */
  nextInt(until: number): number {
    if (!(until > 0)) throw new Error('Can\'t get random value with an empty range')
    return Number(this.nextBelow(BigInt(until)))
  }
}

/** Swift's `shuffled(using:)`: Fisher–Yates front to back, each swap partner from `Int.random(in: 0..<remaining)`. */
export function shuffled<T>(list: readonly T[], using: SeededGenerator): T[] {
  const result = list.slice()
  let amount = result.length
  let i = 0
  while (amount > 1) {
    const r = using.nextInt(amount)
    amount -= 1
    const t = result[i]
    result[i] = result[i + r]
    result[i + r] = t
    i += 1
  }
  return result
}

// ---- GuideGenerator: deterministic scheduler. Same (lineup, day) → identical schedule on every device, every launch ----

/** Guide grid resolution. Slots are (runtime + `pad`) rounded UP to a multiple of this. */
const blockLength = 30 * 60
/** Breathing room so a 28-minute episode isn't jammed into one block: ceil((runtime + 3 min) / 30 min) blocks. */
const pad = 3 * 60

/**
 * Swift `schedule(lineup:day:calendar:)`: every channel of `lineup` tiling `day` from local midnight to the next local
 * midnight, by channel id. In order channels, and Shuffle channels of two or more shows' episodes (the shows take turns),
 * run on a tape that carries on across midnight through the calendar year (`Tape`, `tileRun`); the others draw a pool per
 * day (`tile`). Channels go in `dependencyOrder`, and each passes over a film or episode that a channel scheduled before
 * it is airing, while anything else will do (`Busy`): a shuffle channel takes its next free item, a turns channel swaps in
 * another show's next episode. So one can still air on two channels at once: an In order channel never gives way; a
 * shuffle channel with nothing free airs the first it passed over, opens with its first item when another channel airs
 * its first two, and re-picks its last slot from aired films before it repeats one; a turns channel airs a packed half
 * hour, or an episode with no partner, where it falls.
 * Nothing airs twice in a row (`repeatKey`), across midnight too, unless the channel has nothing else that fits: an
 * overlap goes before a repeat. Across midnight a few still can (`tile`, `tileRun`): on a small shuffle channel, around
 * programs half a day long or more, and where a turns channel swaps its first episode.
 */
function scheduleLineup(lineup: readonly Channel[], day: Instant): Map<string, readonly Slot[]> {
  const start = Time.startOfDay(day)
  // Tile by time: a DST day is 23 or 25 hours, never assume 48 blocks.
  // (Start of the next day, not 24h on: where a DST change skips midnight, a day starts at 1:00.)
  const next = Time.addDays(start, 1)
  const { year, lengths } = lineup.some(isContinuous) ? dayLengths(start) : { year: 0, lengths: [] as number[] }
  // On December 31, January 1's length: the tapes look ahead to what they open the new year with (`tileRun`).
  const jan1 = year !== 0 && Time.localYear(next) !== year ? Math.round(Time.addDays(next, 1)) - Math.round(next) : null
  const busy = new Busy()
  const out = new Map<string, readonly Slot[]>()
  for (const ch of dependencyOrder(lineup)) {
    const s = scheduleOne(ch, start, next, year, lengths, jan1, busy)
    out.set(ch.id, s); busy.add(s)
  }
  return out
}

/** One channel's day on its own (no other channel in the way). */
function schedule(channel: Channel, day: Instant): Slot[] {
  return (scheduleLineup([channel], day).get(channel.id) ?? []).slice()
}

function scheduleOne(ch: Channel, start: Instant, end: Instant, year: number, lengths: readonly number[], jan1: number | null, busy: Busy): Slot[] {
  if (ch.items.length === 0) return []
  if (isContinuous(ch)) {
    const t = new Tape(ch, year), day = Math.round(end) - Math.round(start)
    const fits = new Map<number, number>()
    for (const l of lengths.concat(day)) if (!fits.has(l)) fits.set(l, t.fit(l))
    return tileRun(t, start, end, stateAt(t, lengths, fits), fits, busy, ch.order === 'shuffle', jan1)
  }
  // A day opens with one of its pool's first two items (`tile`), so tonight's last slot steers clear of both of
  // tomorrow's without scheduling tomorrow; of the first only when the pool has only two, where both would leave
  // it nothing. Not an In order holiday channel: its films are the day's own.
  const tomorrow = pool(ch, end), two = tomorrow.slice(0, 2).map(repeatKey)
  const opens = ch.order === 'inOrder' ? [] : tomorrow.some(it => two.indexOf(repeatKey(it)) < 0) ? two : two.slice(0, 1)
  return tile(pool(ch, start), start, end, opens, busy)
}

// ---- The tape (marathons that keep going, shows taking turns) ----

/** The show an episode belongs to; a film, or an episode with no show, is its own. */
function showKey(item: MediaItem): string {
  return item.seriesID ?? item.seriesTitle ?? item.id
}

/** Episodes of two or more shows: on Shuffle the shows take turns, each in order. */
function takesTurns(ch: Channel): boolean {
  return ch.items.every(it => it.kind === 'episode') && new Set(ch.items.map(showKey)).size >= 2
}

/** Runs on the tape. Never the holiday channel: its films are the day's holiday's. */
function isContinuous(ch: Channel): boolean {
  return !ch.definition.rule.some(c => c.kind === 'holiday') && (ch.order === 'inOrder' || (ch.order === 'shuffle' && takesTurns(ch)))
}

/** Who gives way to whom: In order channels never do, then turns channels, then shuffle and newest first, and last the
 *  "what's new" channels and any with an Unwatched chip: their items are this device's own finds and the signed-in
 *  user's watched state, so a new find or a finished film moves nothing before them. */
function tier(ch: Channel): number {
  return isFresh(ch.definition) || ch.definition.rule.some(c => c.kind === 'unwatched') ? 3 : !isContinuous(ch) ? 2 : ch.order === 'inOrder' ? 0 : 1
}

/** The lineup by (tier, number, id), hidden channels and channel 99 included. What a channel airs can move only the
 *  channels after it, so the ones whose items differ by device or by user go last (`tier`). */
function dependencyOrder(channels: readonly Channel[]): Channel[] {
  return stableSort(channels.map(ch => ({ t: tier(ch), ch })), (a, b) =>
    a.t - b.t || compareValues(a.ch.number, b.ch.number) || swiftCompare(a.ch.id, b.ch.id)).map(e => e.ch)
}

/** The channel's items as one endless tape. In order: the items as they are, round and round. Turns: show A's next
 *  episode, then B's, then C's (shows by name), each show in order, wrapping on its own. */
class Tape {
  readonly items: readonly MediaItem[]
  /** Per item: slot length and packed length (seconds), whether it shares its half hour, its `repeatKey` as a number. */
  readonly len: number[]; readonly part: number[]; readonly short: boolean[]; readonly keyID: number[]
  readonly shows: number[][]; readonly showOf: number[]
  /** Where January 1 starts, this year and next, seeded by the channel and the year. */
  readonly p0: number; readonly nextP0: number
  private readonly keyMin: number[]

  constructor(ch: Channel, year: number) {
    const items = this.items = ch.items
    this.len = items.map(it => slotLength(it))
    this.part = items.map(it => partLength(it))
    this.short = items.map((it, i) => it.runtime * 2 <= this.len[i])   // tile's packing test
    const ids = new Map<string, number>()
    this.keyID = items.map(it => { const k = repeatKey(it); if (!ids.has(k)) ids.set(k, ids.size); return ids.get(k)! })
    this.keyMin = new Array<number>(ids.size).fill(Infinity)
    items.forEach((_, i) => { this.keyMin[this.keyID[i]] = Math.min(this.keyMin[this.keyID[i]], this.len[i]) })
    if (ch.order === 'shuffle') {
      const groups = new Map<string, number[]>()   // in first-seen order
      items.forEach((it, i) => { const k = showKey(it); const g = groups.get(k); if (g) g.push(i); else groups.set(k, [i]) })
      this.shows = stableSort(Array.from(groups.entries()).map(([k, g]) => ({ name: items[g[0]].seriesTitle ?? '', k, g })),
        (a, b) => swiftCompare(a.name, b.name) || swiftCompare(a.k, b.k))
        .map(e => stableSort(e.g, (a, b) => episodeOrder(items[a], items[b])))
    } else this.shows = [items.map((_, i) => i)]
    this.showOf = new Array<number>(items.length).fill(0)
    this.shows.forEach((g, s) => { for (const i of g) this.showOf[i] = s })
    const p0 = (year: number) => Number(StableHash.fnv1a(ch.id + '|' + year) % BigInt(items.length))
    this.p0 = p0(year); this.nextP0 = p0(year + 1)
  }

  /** The item at tape position `p` (≥ 0). */
  at(p: number): number {
    const s = p % this.shows.length, g = this.shows[s]
    return g[Math.trunc(p / this.shows.length) % g.length]
  }

  /** For a day `length` seconds long: how many keys have something that fits it (0: nothing does). */
  fit(length: number): number {
    return this.keyMin.filter(m => m <= length).length
  }
}

/** Where a tape is: the next position, and the key of what aired last (-1: nothing yet). */
interface TapeState { readonly p: number; readonly last: number }

/** One day of the tape: the slots it airs (tape positions: the program, then any packed parts) and where it stops. */
function walk(t: Tape, state: TapeState, day: number, fit: number, collect: boolean): { plan: number[][]; state: TapeState } {
  let p = state.p, last = state.last, used = 0
  const plan: number[][] = []
  if (fit === 0) { const i = t.at(p); return { plan: [[p]], state: { p: p + 1, last: t.keyID[i] } } }   // longer than the whole day: airs cut
  for (;;) {
    const i = t.at(p)
    if (t.len[i] > day) { p += 1; continue }
    if (fit >= 2 && t.keyID[i] === last) { p += 1; continue }
    if (used + t.len[i] > day) break
    const slot = [p]; p += 1; used += t.len[i]; last = t.keyID[i]
    if (t.short[i] && t.items.length > 1) {
      let room = t.len[i] - t.part[i]
      for (;;) {
        const j = t.at(p)
        // Already in this slot: an item comes round every (shows × its show's items) positions, and a slot's are consecutive.
        if (t.part[j] > room || t.keyID[j] === last || slot.length >= t.shows.length * t.shows[t.showOf[j]].length) break
        slot.push(p); room -= t.part[j]; last = t.keyID[j]; p += 1
      }
    }
    if (collect) plan.push(slot)
  }
  return { plan, state: { p, last } }
}

/** The year so far: January 1 starts at `p0`, and every day since walks on from the one before.
 *  ponytail: the chain re-walks the year on every lineup-day call (an estimated 1 ms per channel on a 2020 TV in
 *  December, not measured on one); memoize the furthest (day, p, last) per channel if an Order press stalls. */
function stateAt(t: Tape, lengths: readonly number[], fits: Map<number, number>): TapeState {
  let s: TapeState = { p: t.p0, last: -1 }
  for (const l of lengths) s = walk(t, s, l, fits.get(l)!, false).state
  return s
}

/** The day's year and the length in seconds of each day of it before `dayStart`. */
function dayLengths(dayStart: Instant): { year: number; lengths: number[] } {
  const year = Time.localYear(dayStart)
  const lengths: number[] = []
  for (let d = Time.startOfDay(new Date(year, 0, 1, 12).getTime() / 1000); d < dayStart;) {   // from noon: no zone skips noon
    const n = Time.addDays(d, 1)
    lengths.push(Math.round(n - d)); d = n
  }
  return { year, lengths }
}

/** Swift `tileRun`: tiles the day from the tape at `state`. A turns channel (`swaps`) whose next episode is on another
 *  channel airs another show's next episode from the same round instead; what the tape can't fit before midnight is an
 *  encore of the longest program aired earlier that day, else the last slot runs on. */
function tileRun(t: Tape, start: Instant, end: Instant, state: TapeState, fits: Map<number, number>, busy: Busy, swaps: boolean,
                 jan1: number | null): Slot[] {
  const s0 = Math.round(start), e0 = Math.round(end)
  const w = walk(t, state, e0 - s0, fits.get(e0 - s0)!, true)
  let plan = w.plan
  // What opens tomorrow: the next position. On December 31 (`jan1`: January 1's length) it is what January 1's walk
  // places first, from the new year's `p0` with nothing aired before it; when tonight's plan ends with that too, that
  // part goes. In a packed half hour the part before it keeps the rest of the half hour; a program's gap is filled
  // below with an encore or by the slot before running on (neither repeats it). Not on a day of one entry, and a turns
  // channel's January 1 can swap in another first episode (below).
  let opener = t.keyID[t.at(w.state.p)]
  if (jan1 != null) {
    opener = t.keyID[t.at(walk(t, { p: t.nextP0, last: -1 }, jan1, t.fit(jan1), true).plan[0][0])]
    const tail = plan[plan.length - 1]
    if (plan.length > 1 && fits.get(e0 - s0)! >= 2 && t.keyID[t.at(tail[tail.length - 1])] === opener) {
      if (tail.length > 1) tail.pop(); else plan.pop()
    }
  }
  const key = (i: number) => repeatKey(t.items[i])
  let cursor = s0, prev = -1, idx = 0
  const slots: Slot[] = [], whole: number[] = []
  while (idx < plan.length) {
    let first = t.at(plan[idx][0])
    // ponytail: a packed half hour never swaps, so two turns cartoon channels sharing a short can overlap for a
    // few minutes. Upgrade: swap whole packs.
    if (swaps && plan[idx].length === 1 && busy.conflicts(key(first), Busy.airs(t.items[first], cursor))) {
      const seen = new Set<number>()   // shows with an entry between idx and u
      for (let u = idx + 1; u < plan.length; u++) {
        const showsU = new Set(plan[u].map(q => t.showOf[t.at(q)]))
        if (showsU.has(t.showOf[first])) break   // never past its own show's next episode
        const cand = t.at(plan[u][0])
        if (plan[u].length === 1 && !seen.has(t.showOf[cand]) && t.keyID[cand] !== t.keyID[first] &&
          !busy.conflicts(key(cand), Busy.airs(t.items[cand], cursor))) {
          const q = plan.slice(); q[idx] = plan[u]; q[u] = plan[idx]
          // Each moved entry against what airs before it: the entry before, or for the day's first what the tape
          // placed last yesterday (`state.last`, nothing on January 1). Yesterday's own swaps and encore aside: when
          // it ended in one, this can pass a swap that repeats it across midnight, or refuse a good one, which can
          // leave the blocked episode on two channels.
          const repeats = [idx, idx + 1, u, u + 1].some(x => x < q.length &&
            t.keyID[t.at(q[x][0])] === (x === 0 ? state.last : t.keyID[t.at(q[x - 1][q[x - 1].length - 1])]))
          if (!repeats && !(u === plan.length - 1 && t.keyID[first] === opener)) { plan = q; first = cand; break }
        }
        showsU.forEach(s => seen.add(s))
      }
    }
    const slotEnd = Math.min(cursor + t.len[first], e0)
    const parts = plan[idx].map(q => t.at(q))
    if (parts.length === 1 && slotEnd - cursor === t.len[first]) whole.push(first)
    parts.forEach((i, m) => {
      const partEnd = m === parts.length - 1 ? slotEnd : cursor + t.part[i]
      slots.push(new Slot(t.items[i], cursor, partEnd)); cursor = partEnd
    })
    prev = t.keyID[parts[parts.length - 1]]; idx += 1
  }
  if (cursor < e0) {   // the time the next one didn't fit
    let encore: number | null = null
    for (const i of whole) {
      if (t.len[i] <= e0 - cursor && t.keyID[i] !== prev && t.keyID[i] !== opener && !busy.conflicts(key(i), Busy.airs(t.items[i], cursor))) {
        if (encore == null || t.len[i] > t.len[encore]) encore = i   // the longest, the earliest on ties
      }
    }
    if (encore != null) slots.push(new Slot(t.items[encore], cursor, end))   // its leftover is its break
    else { const l = slots.pop()!; slots.push(new Slot(l.item, l.start, end)) }
  }
  return slots
}

// ---- One program on one channel at a time ----

/** The airing windows of everything placed so far today, by `repeatKey`, in whole epoch seconds. */
class Busy {
  private readonly windows = new Map<string, [number, number][]>()
  /** When `item` would air if it started at `at`. */
  static airs(item: MediaItem, at: number): [number, number] { return [at, at + Math.trunc(item.runtime)] }
  conflicts(key: string, w: [number, number]): boolean {
    const ws = this.windows.get(key)
    return ws != null && ws.some(x => x[0] < w[1] && w[0] < x[1])
  }
  add(slots: readonly Slot[]): void {
    for (const s of slots) {
      const a = Math.round(s.start), k = repeatKey(s.item)
      const w: [number, number] = [a, a + Math.min(Math.round(s.end) - a, Math.trunc(s.item.runtime))]
      const ws = this.windows.get(k)
      if (ws) ws.push(w); else this.windows.set(k, [w])
    }
  }
}

/**
 * What mustn't air twice in a row: the item, or for a film any copy of it (same title and year; a library often
 * holds a 4K copy as a second item). A cut is part of the title, so two cuts are two films. Episodes go by item, so a
 * show's next episode, or the next segment sharing its episode number, still follows.
 * ponytail: keys compare by UTF-16 unit and Swift's by canonical equivalence, so an NFC and an NFD spelling of one title
 * are two films here and one in Swift (`showKey` too: a Map and Set key in `Tape` and `takesTurns`), and that library's
 * schedule differs from Swift's. Upgrade: normalize titles to NFC where MediaItems are built.
 */
function repeatKey(item: MediaItem): string {
  return item.kind === 'movie' ? `film:${item.title}|${item.year ?? 0}` : `item:${item.id}`
}

/**
 * The day's play order, seeded by channel and date. `day` is a local midnight (`Time.startOfDay`). The holiday channel's
 * is the day's holiday's films only.
 */
function pool(channel: Channel, day: Instant): MediaItem[] {
  const { y, m, d } = Time.localYMD(day)
  const rng = new SeededGenerator(channel.id + `|${zeroPad(y, 4)}-${zeroPad(m, 2)}-${zeroPad(d, 2)}`)
  const items = channel.definition.rule.some(c => c.kind === 'holiday') ? Holiday.pick(channel.items, day).films : channel.items
  switch (channel.order) {
    case 'shuffle': return shuffled(items, rng)
    case 'inOrder':
    case 'newestFirst': {
      const r = Number(rng.next() % BigInt(items.length))   // plain modulo, not Lemire: as Swift and Kotlin
      return items.slice(r).concat(items.slice(0, r))
    }
  }
}

/**
 * Tiles [start, end) from `pool` as `schedule` describes. The day opens with `pool[0]`, or `pool[1]` when another channel
 * airs `pool[0]` at `start`, or `pool[0]` anyway when both are aired (an overlap before a repeat); one longer than the
 * whole day counts as one of the two and can't open. `opens`: the `repeatKey`s of tomorrow's two, which the last slot and
 * the packed parts of the last half hour steer clear of while anything else fits. With only two (`opens` is tomorrow's
 * first), or too few for both (three), the last slot steers clear of tomorrow's first only, and repeats if another channel
 * airs that one at midnight; a day of one program keeps its opener whatever tomorrow opens with; and when tomorrow's two
 * are both longer than the day, the first free one that fits opens unforeseen. `opens` is empty on an In order holiday
 * channel, which opens with its first free item. `busy`: what other channels air; an item on one of them is passed over
 * while anything else will do, before any repeat.
 */
function tile(pool: readonly MediaItem[], start: Instant, end: Instant, opens: readonly string[], busy: Busy = new Busy()): Slot[] {
  const slots: Slot[] = []
  let cursor = start
  let next = 0
  while (cursor < end) {
    const previous = slots.length > 0 ? repeatKey(slots[slots.length - 1].item) : null
    let pick: number | null = null
    let blocked: number | null = null
    let again: number | null = null
    for (let k = 0; k < pool.length; k++) {
      if (k === 2 && slots.length === 0 && opens.length > 0 && blocked != null) break   // the day's first slot: one of the first two
      const i = (next + k) % pool.length
      const slotEnd = cursor + slotLength(pool[i])
      if (slotEnd > end) continue
      const key = repeatKey(pool[i])
      if (slots.length === 0 || key !== previous && (slotEnd < end || opens.indexOf(key) < 0)) {
        if (!busy.conflicts(key, Busy.airs(pool[i], Math.round(cursor)))) { pick = i; break }
        if (blocked == null) blocked = i
      } else if (again == null) again = i
    }
    if (pick == null) pick = blocked
    // Only the same thing again fits: fine on a channel with nothing else that could air today (one film, or
    // copies of it). Otherwise it's the end of the day, below.
    const day = end - start
    if (pick == null && again != null && !pool.some(it => repeatKey(it) !== previous && slotLength(it) <= day)) pick = again
    if (pick == null) {
      let last = slots.pop() ?? null
      // A half hour of short programs goes as a whole, so the re-picked slot starts on the half-hour grid.
      while (last != null && (last.start - start) % blockLength !== 0) {
        const before = slots.pop()
        if (before == null) break
        last = before
      }
      if (last != null) {
        const window = end - last.start
        let best = last.item   // fits by construction; a longer one that also fits leaves a shorter break
        const before = slots.length > 0 ? repeatKey(slots[slots.length - 1].item) : null
        if (before != null) {   // (the day's opener itself never changes)
          // The longest that fits and repeats neither the slot before nor tomorrow's openers: one no other channel airs
          // then, else one that one does (an overlap before a repeat). Too few films for that (three): one clear of
          // tomorrow's first at least, which opens unless another channel airs it then. Else the slot as it was.
          const longest = (clear: readonly string[], free: boolean): MediaItem | null => {
            const ok = (it: MediaItem) => repeatKey(it) !== before && clear.indexOf(repeatKey(it)) < 0 &&
              !(free && busy.conflicts(repeatKey(it), Busy.airs(it, Math.round(last!.start))))
            let found: MediaItem | null = ok(last!.item) ? last!.item : null
            for (let k = 0; k < pool.length; k++) {
              const it = pool[(next + k) % pool.length]
              if (slotLength(it) <= window && slotLength(it) > (found != null ? slotLength(found) : 0) && ok(it)) found = it
            }
            return found
          }
          best = longest(opens, true) ?? longest(opens, false) ?? longest(opens.slice(0, 1), false) ?? last.item
        }
        slots.push(new Slot(best, last.start, end))
      } else {
        slots.push(new Slot(pool[next], cursor, end))   // longer than the whole day
      }
      break
    }
    const slotEnd = cursor + slotLength(pool[pick])
    // A short program (15 minutes or less: half its half hour, the pad not counted) doesn't leave the rest of it empty: the next ones in order that
    // fit play right after it, each in its own slot, the way cartoon blocks did. Nothing crosses the half hour.
    const parts = [pool[pick]]
    let used = partLength(pool[pick])
    next = (pick + 1) % pool.length
    if (pool[pick].runtime <= (slotEnd - cursor) / 2) {
      while (pool.length > 1) {
        const it = pool[next]
        if (used + partLength(it) > slotEnd - cursor || parts.some(p => p.id === it.id) ||
          repeatKey(it) === repeatKey(parts[parts.length - 1]) || !(slotEnd < end || opens.indexOf(repeatKey(it)) < 0) ||
          busy.conflicts(repeatKey(it), Busy.airs(it, Math.round(cursor) + used))) break
        parts.push(it); used += partLength(it); next = (next + 1) % pool.length
      }
    }
    for (let n = 0; n < parts.length; n++) {   // the last one keeps whatever is left of the half hour as its break
      const partEnd = n === parts.length - 1 ? slotEnd : cursor + partLength(parts[n])
      slots.push(new Slot(parts[n], cursor, partEnd))
      cursor = partEnd
    }
  }
  return slots
}

/** A packed program's slot: its runtime in whole seconds, so the next one starts as it ends (no break in between). */
function partLength(item: MediaItem): number {
  return Math.max(1, Math.floor(item.runtime))
}

/** Kotlin `schedule(channel, from, to)`: slots on `channel` intersecting [from, to]. Spans days as needed. */
function scheduleRange(channel: Channel, from: Instant, to: Instant): Slot[] {
  const slots: Slot[] = []
  for (let day = Time.startOfDay(from); day < to; day = Time.addDays(day, 1)) slots.push(...schedule(channel, day))
  return slots.filter(it => it.end > from && it.start < to)
}

/** The slot containing `at` on `channel`. */
function slot(on: Channel, at: Instant): Slot | null {
  return schedule(on, at).find(it => it.start <= at && at < it.end) ?? null
}

/**
 * Swift `slot(on:startingAt:)`. The slot by its exact start (what `ProgramKey` stores), if the generator still produces it.
 * Sub-second tolerance so a start that went through JSON (persisted key) still matches.
 */
function slotStartingAt(on: Channel, startingAt: Instant): Slot | null {
  return schedule(on, startingAt).find(it => Math.abs(it.start - startingAt) < 1) ?? null
}

/** later: before start · live: item playing · break: item over, slot not · past: slot over. */
function status(of: Slot, at: Instant): ProgramStatus {
  if (at < of.start) return 'later'
  if (at >= of.end) return 'past'
  return at >= of.itemEnd ? 'break' : 'live'
}

function slotLength(item: MediaItem): number {
  // Channel 99's programs fill their slots exactly: no pad, so the scramble never drops into a station break.
  const padded = item.id.startsWith(Channel.scrambledID) ? item.runtime : item.runtime + pad
  return Math.max(1, Math.ceil(padded / blockLength)) * blockLength
}

export const GuideGenerator = {
  blockLength, pad,
  schedule, scheduleLineup, takesTurns, isContinuous, dependencyOrder, showKey, Tape, dayLengths, repeatKey, pool, tile, partLength, scheduleRange, slot,
  slotStartingAt, status, slotLength,
}

// ---- Holiday: the holiday channel's calendar ----

/** Swift's `Int` division: truncates toward zero. */
const div = (a: number, b: number): number => Math.trunc(a / b)

/**
 * The holiday channel's calendar (US holidays). Each day airs the films of the nearest holiday that has at least
 * `minFilms` of them: the one whose season the day falls in (all October is Halloween, Christmas runs from the day after
 * Thanksgiving), else the one whose season is closest. Groundhog Day is the one-day exception: the film, back to back.
 */
export type Holiday = 'newYear' | 'valentines' | 'stPatricks' | 'easter' | 'july4' | 'halloween' | 'thanksgiving' | 'christmas'
export const Holiday = {
  entries: ['newYear', 'valentines', 'stPatricks', 'easter', 'july4', 'halloween', 'thanksgiving', 'christmas'] as readonly Holiday[],

  rawValue(h: Holiday): string {
    switch (h) {
      case 'newYear': return 'New Year’s'
      case 'valentines': return 'Valentine’s Day'
      case 'stPatricks': return 'St. Patrick’s Day'
      case 'easter': return 'Easter'
      case 'july4': return 'Fourth of July'
      case 'halloween': return 'Halloween'
      case 'thanksgiving': return 'Thanksgiving'
      case 'christmas': return 'Christmas'
    }
  },

  /** Fewer and the holiday sits the year out: four films are about as few as a day can repeat. */
  minFilms: 4,
  groundhogDay: 'Groundhog Day',

  /** Days before the holiday that its season starts. Where two seasons overlap, the nearer holiday has the day. */
  lead(h: Holiday): number {
    switch (h) {
      case 'newYear': return 6            // from the day after Christmas
      case 'valentines': return 13
      case 'stPatricks': case 'easter': case 'july4': return 7
      case 'halloween': return 30         // all October
      case 'thanksgiving': return 27      // all November up to it, even on the 28th
      case 'christmas': return 33         // from the day after Thanksgiving, the 22nd at the earliest
    }
  },

  /** Its month and day in `year`. */
  date(h: Holiday, year: number): { month: number; day: number } {
    switch (h) {
      case 'newYear': return { month: 1, day: 1 }
      case 'valentines': return { month: 2, day: 14 }
      case 'stPatricks': return { month: 3, day: 17 }
      case 'easter': return Holiday.easter(year)
      case 'july4': return { month: 7, day: 4 }
      case 'halloween': return { month: 10, day: 31 }
      case 'thanksgiving': return { month: 11, day: 22 + (11 - Holiday.weekday(year, 11, 1)) % 7 }   // the fourth Thursday
      case 'christmas': return { month: 12, day: 25 }
    }
  },

  /** Word starts in a film's title or overview that make it this holiday's (as `ChannelBuilder.mentions` reads them). */
  words(h: Holiday): readonly string[] {
    switch (h) {
      case 'newYear': return ['new year', 'auld lang syne']
      case 'valentines': return ['valentine']
      case 'stPatricks': return ['st. patrick', 'st patrick', 'saint patrick', 'leprechaun', 'ireland']
      case 'easter': return ['easter bunny', 'easter egg', 'easter parade', 'easter sunday', 'jesus', 'ten commandments', 'ben-hur']
      case 'july4': return ['fourth of july', '4th of july', 'july 4', 'july fourth', 'independence day']
      case 'halloween': return ['halloween', 'trick or treat', 'trick-or-treat']
      case 'thanksgiving': return ['thanksgiving']
      case 'christmas': return ['christmas', 'xmas', 'santa claus', 'north pole', 'yuletide', 'scrooge', 'grinch', 'nutcracker',
        'kris kringle', 'reindeer']
    }
  },

  /** Genres that make a film this holiday's: a date for Valentine's, a scare for Halloween (not a kids' one: `genre`). */
  genres(h: Holiday): readonly string[] {
    switch (h) {
      case 'valentines': return ['Romance']
      case 'halloween': return ['Horror']
      default: return []
    }
  },

  /** A film for this holiday. */
  has(h: Holiday, item: MediaItem): boolean {
    return item.kind === 'movie' && (mentions(item, Holiday.words(h)) || Holiday.genres(h).some(g => matches(RuleChip.genre(g), item)))
  },

  /** Groundhog Day's own film, by its title, any cut of it ("Groundhog Day (Remastered)": `MediaItem.title`). */
  isGroundhogDay(item: MediaItem): boolean {
    const t = item.title.toLowerCase()
    return item.kind === 'movie' && (t === 'groundhog day' || t.startsWith('groundhog day ('))
  },

  /**
   * What the holiday channel airs on `on`'s local day, and its holiday's name: on February 2 the film Groundhog Day if
   * `films` has it, else the nearest holiday's films. All of `films` if no holiday has `minFilms` (then there is no channel).
   */
  pick(films: readonly MediaItem[], on: Instant): { name: string; films: readonly MediaItem[] } {
    const { y, m, d } = Time.localYMD(on)
    if (m === 2 && d === 2) {
      const g = films.filter(Holiday.isGroundhogDay)
      if (g.length > 0) return { name: Holiday.groundhogDay, films: g }
    }
    const today = Holiday.dayNumber(y, m, d)
    // In its season (0), else how far from it; then the nearer holiday (halfway between two seasons, the one just gone:
    // its season ends on its day). No two holidays tie, so nearest first and the first with enough films has the day:
    // only the holidays tried get their films sorted out.
    const key = (h: Holiday): number[] => {
      let best: number[] | null = null
      for (let year = y - 1; year <= y + 1; year++) {
        const md = Holiday.date(h, year)
        const at = Holiday.dayNumber(year, md.month, md.day)
        const start = at - Holiday.lead(h)
        const k = [today < start ? start - today : Math.max(0, today - at), Math.abs(at - today)]
        if (best == null || (k[0] - best[0] || k[1] - best[1]) < 0) best = k
      }
      return best!
    }
    const ranked = Holiday.entries.map(h => ({ h, k: key(h) }))
    for (const { h } of stableSort(ranked, (a, b) => a.k[0] - b.k[0] || a.k[1] - b.k[1])) {
      const mine = films.filter(it => Holiday.has(h, it))
      if (mine.length >= Holiday.minFilms) return { name: Holiday.rawValue(h), films: mine }
    }
    return { name: 'Holiday', films }
  },

  /** Days from 1970-01-01 to a calendar date, as Swift's days_from_civil counts them (Date.UTC reads years 0 to 99 as 19xx). */
  dayNumber(y: number, m: number, d: number): number {
    return Date.UTC(y, m - 1, d) / 86_400_000
  },

  /** 0 = Sunday. */
  weekday(y: number, m: number, d: number): number {
    return new Date(Date.UTC(y, m - 1, d)).getUTCDay()
  },

  /** Western Easter Sunday (the anonymous Gregorian algorithm). */
  easter(y: number): { month: number; day: number } {
    const a = y % 19, b = div(y, 100), c = y % 100, d = div(b, 4), e = b % 4, f = div(b + 8, 25), g = div(b - f + 1, 3)
    const h = (19 * a + b - d - g + 15) % 30, i = div(c, 4), k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7
    const m = div(a + 11 * h + 22 * l, 451)
    const n = h + l - 7 * m + 114
    return { month: div(n, 31), day: n % 31 + 1 }
  },
}
