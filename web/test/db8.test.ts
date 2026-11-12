/// <reference types="node" />
// The LG backup (Platform.keepDefaults, DB8): settings and channels come back after a store update, the sign-in never
// goes to DB8, and nothing another app could have put there is trusted: a kind it registered first, or the objects of
// a kind that extends ours.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { defaults } from '../src/app/Persistence'

const ours = 'com.rerunguide.app:1'
const store = new Map<string, string>()
Object.defineProperty(globalThis, 'localStorage', { configurable: true, value: {
  getItem: (k: string) => store.get(k) ?? null,
  setItem: (k: string, v: string) => { store.set(k, v) },
  removeItem: (k: string) => { store.delete(k) },
} })
let calls: { method: string; params: any }[] = []
let reply: (method: string) => object = () => ({ returnValue: true })
class Bridge {
  onservicecallback: ((reply: string) => void) | null = null
  call(uri: string, params: string) {
    const method = uri.slice('luna://com.palm.db/'.length)
    calls.push({ method, params: JSON.parse(params) })
    setTimeout(() => this.onservicecallback?.(JSON.stringify(reply(method))))
  }
}
Object.defineProperty(globalThis, 'window', { configurable: true, value: { webOSSystem: { platformBack() {} }, PalmServiceBridge: Bridge } })
const { Platform } = await import('../src/app/Platform')   // after the fakes: it reads window as it loads
const settle = () => new Promise(done => setTimeout(done, 20))

/** One launch: localStorage holds `local`, DB8's find answers `rows`, and putKind is refused when `squatted`. */
async function launch(local: Record<string, string>, rows: object[], squatted = false) {
  store.clear()
  for (const [k, v] of Object.entries(local)) store.set(k, v)
  calls = []; defaults.mirror = null
  reply = m => m === 'putKind' && squatted ? { returnValue: false, errorCode: -3963, errorText: 'Permission denied' }
    : m === 'find' ? { returnValue: true, results: rows } : { returnValue: true, count: 1 }
  await Platform.keepDefaults()
  await settle()
}

test('a store update brings back settings, never a sign-in, and only from our own kind', async () => {
  await launch({}, [
    { _id: 'a', _kind: ours, key: 'persisted', value: 'P' },
    { _id: 'b', _kind: ours, key: 'deviceID', value: 'D' },
    { _id: 'c', _kind: ours, key: 'kc.token', value: 'T' },                  // an earlier build kept it
    { _id: 'x', _kind: 'com.other.app:1', key: 'persisted', value: 'X' },   // a kind that extends ours
  ])
  assert.equal(store.get('persisted'), 'P')
  assert.equal(store.get('deviceID'), 'D')
  assert.equal(store.get('kc.token'), undefined)
  assert.deepEqual(calls.filter(c => c.method === 'del').map(c => c.params), [{ ids: ['c'], purge: true }])

  calls = []
  defaults.set('kc.token', 'T2'); defaults.set('kc.plexAccount', 'A2'); defaults.set('persisted', 'P2')
  await settle()
  assert.deepEqual(calls.map(c => c.method), ['merge'])
  assert.deepEqual(calls[0].params.props, { value: 'P2' })
})

test('a later launch catches DB8 up from localStorage, tokens left out', async () => {
  await launch({ db8Restored: '1', persisted: 'L', deviceID: 'D', 'kc.token': 'T' },
    [{ _id: 'a', _kind: ours, key: 'persisted', value: 'P' }, { _id: 'b', _kind: ours, key: 'deviceID', value: 'D' }])
  assert.equal(store.get('persisted'), 'L')
  assert.deepEqual(calls.map(c => c.method), ['putKind', 'find', 'merge'])
  assert.deepEqual(calls[2].params.props, { value: 'L' })
  assert.ok(!JSON.stringify(calls).includes('"T"'))
})

test('a kind another app registered first is never read or written', async () => {
  const warn = console.warn
  console.warn = () => {}
  try {
    await launch({}, [{ _id: 'p', _kind: ours, key: 'persisted', value: 'PLANTED' }], true)
  } finally {
    console.warn = warn
  }
  assert.deepEqual(calls.map(c => c.method), ['putKind'])
  assert.equal(store.get('persisted'), undefined)
  assert.equal(store.get('db8Restored'), undefined)
  assert.equal(defaults.mirror, null)
})
