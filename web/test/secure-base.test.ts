/// <reference types="node" />
// HTTPRedirectTests.testSignInAsksForHttpsFirst (Swift), for what only the web port has: the https question is a fetch
// that may not follow a redirect, and everything after it is one that may.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { JellyfinClient } from '../src/core/JellyfinClient'
import { HTTP, URLRequest } from '../src/core/MediaServer'
import { PlexAuth } from '../src/core/PlexClient'

test('sign-in asks a typed address over https first, and only the asked address may answer', async () => {
  const real = globalThis.fetch
  const seen: string[] = []
  // tls.test answers as a server. hop.test's https side only points at one, which a real fetch refuses under redirect: 'error'.
  globalThis.fetch = (async (input: unknown, init?: RequestInit) => {
    const url = String(input)
    seen.push(`${init?.redirect} ${url}`)
    if (url.startsWith('https://hop.test') && init?.redirect === 'error') throw new TypeError('Failed to fetch')
    return new Response(/^https:\/\/(tls|hop)\.test/.test(url) ? '{"Id":"s1"}' : 'ok')
  }) as typeof fetch
  try {
    for (const typed of ['http://tls.test:8920/jf', 'http://plain.test', 'http://hop.test']) {
      await JellyfinClient.login(typed, 'u', 'p', 'd', 'jellyfin').catch(() => {})
    }
  } finally {
    globalThis.fetch = real
  }
  assert.deepEqual(seen, [
    'error https://tls.test:8920/jf/System/Info/Public', 'follow https://tls.test:8920/jf/Users/AuthenticateByName',
    'error https://plain.test/System/Info/Public', 'follow http://plain.test/Users/AuthenticateByName',
    'error https://hop.test/System/Info/Public', 'follow http://hop.test/Users/AuthenticateByName',
  ])
})

// HTTPRedirectTests.testHttpsToHttpRedirectIsRefused (Swift). A page cannot stop the redirect itself, only refuse its answer.
test('an answer that came from http to an https request is refused', async () => {
  const real = globalThis.fetch
  let tokened = false
  globalThis.fetch = (async (input: unknown, init?: RequestInit) => {
    if ((init?.headers as { [field: string]: string } | undefined)?.['X-Plex-Token'] != null) tokened = true
    const r = new Response('{"Id":"s1"}')
    // down.test's https side answers with a redirect to its http side, which fetch has followed by the time it returns.
    Object.defineProperty(r, 'url', { value: String(input).replace('https://down.test', 'http://down.test') })
    return r
  }) as typeof fetch
  try {
    await assert.rejects(HTTP.data(new URLRequest('https://down.test/System/Info')), (e: unknown) => e instanceof Error && !(e instanceof TypeError) && e.message === 'insecure redirect')
    assert.equal(await HTTP.data(new URLRequest('https://tls.test/System/Info')), '{"Id":"s1"}')
    assert.equal(await HTTP.data(new URLRequest('http://plain.test/System/Info')), '{"Id":"s1"}')
    // The refusal is not taken for an answer the browser hid: the Plex address probe does not ask again with the token.
    assert.equal(await PlexAuth.bestAddress([{ url: 'https://down.test', local: false }], 'm1', 'test', false, 'server-token'), null)
    assert.equal(tokened, false, 'a token went down the redirect')
  } finally {
    globalThis.fetch = real
  }
})
