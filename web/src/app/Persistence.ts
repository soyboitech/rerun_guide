// Web-only: where Android's SharedPreferences ("defaults", the Keychain prefs file), the deviceID file and the library
// cache file live on a TV. localStorage for the small string values (sync, like SharedPreferences), IndexedDB for the
// library cache (several MB, past localStorage's ~5 MB quota). LG deletes both when a store update installs, so on LG
// the settings and channels are copied to DB8 too (`mirror`, Platform.keepDefaults) and come back from it; the sign-in
// isn't (other apps can reach DB8), and the library cache rebuilds from the server. Nothing here runs at module load:
// Node tests import AppModel.ts.

/** `AppModel.defaults` (UserDefaults.standard): localStorage, string values. Every access is guarded: it throws when
 *  storage is disabled, and a write throws when it is full. A failed read is a missing key, a failed write is lost. */
export const defaults = {
  /** LG only: hands each change on to DB8, which keeps the settings keys (Platform.keepDefaults sets it). */
  mirror: null as ((key: string, value: string | null) => void) | null,
  get(key: string): string | null {
    try { return localStorage.getItem(key) } catch { return null }
  },
  set(key: string, value: string): void {
    try { localStorage.setItem(key, value) } catch (e) { console.warn('defaults', key, e) }
    defaults.mirror?.(key, value)
  },
  remove(key: string): void {
    try { localStorage.removeItem(key) } catch { /* nothing stored, nothing to remove */ }
    defaults.mirror?.(key, null)
  },
}

let db: Promise<IDBDatabase> | null = null

function open(): Promise<IDBDatabase> {
  if (db == null) {
    db = new Promise((resolve, reject) => {
      const r = indexedDB.open('rerun', 1)
      r.onupgradeneeded = () => r.result.createObjectStore('cache')
      r.onsuccess = () => resolve(r.result)
      r.onerror = () => reject(r.error)
    })
  }
  return db
}

/** One request in its own transaction, resolved when the transaction commits (so a later write is never overtaken:
 *  IndexedDB runs overlapping readwrite transactions in the order they were created). */
function run<T>(mode: IDBTransactionMode, request: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  return open().then(d => new Promise<T>((resolve, reject) => {
    const tx = d.transaction('cache', mode)
    const r = request(tx.objectStore('cache'))
    tx.oncomplete = () => resolve(r.result)
    tx.onerror = tx.onabort = () => reject(tx.error)
  }))
}

/** The Caches directory (`AppModel.cacheDir`): a key-value store in IndexedDB. */
export const cacheStore = {
  get(key: string): Promise<unknown> { return run('readonly', s => s.get(key)) },
  set(key: string, value: unknown): Promise<void> { return run('readwrite', s => s.put(value, key)).then(() => {}) },
  delete(key: string): Promise<void> { return run('readwrite', s => s.delete(key)).then(() => {}) },
}
