// Builds the Roku channel: `node build.mjs build` (dist/rerun-guide.zip, the sideloadable package), `test` (the Swift
// parity check and the core tests, run off-device by brs-cli), `deploy` (build, then sideload to the Roku at ROKU_HOST
// with its developer password in ROKU_PASSWORD).
import fs from 'node:fs'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { createRequire } from 'node:module'

const roku = path.dirname(fileURLToPath(import.meta.url))
const repo = path.join(roku, '..')
const dist = path.join(roku, 'dist')
const staging = path.join(dist, 'pkg')
const outFile = 'rerun-guide.zip'
const require = createRequire(import.meta.url)

/** The channel's own files, then the fonts from App/Fonts (they exist once in the repo, as for the web build). */
function stage() {
  fs.rmSync(staging, { recursive: true, force: true })
  fs.mkdirSync(staging, { recursive: true })
  for (const f of ['manifest', 'source', 'components', 'images']) {
    const from = path.join(roku, f)
    if (fs.existsSync(from)) fs.cpSync(from, path.join(staging, f), { recursive: true })
  }
  const fonts = path.join(staging, 'fonts')
  fs.mkdirSync(fonts, { recursive: true })
  for (const f of fs.readdirSync(path.join(repo, 'App/Fonts')).filter(f => f.endsWith('.ttf'))) {
    fs.copyFileSync(path.join(repo, 'App/Fonts', f), path.join(fonts, f))
  }
}

async function build() {
  stage()
  const { RokuDeploy } = require('roku-deploy')
  await new RokuDeploy().createPackage({ rootDir: staging, files: ['**/*'], outDir: dist, outFile, retainStagingDir: true })
  console.log(path.join(dist, outFile))
}

async function deploy() {
  const host = process.env.ROKU_HOST, password = process.env.ROKU_PASSWORD
  if (!host || !password) {
    console.error('Set ROKU_HOST (the Roku\'s IP address) and ROKU_PASSWORD (its developer mode password).')
    process.exit(2)
  }
  await build()
  const { RokuDeploy } = require('roku-deploy')
  const r = await new RokuDeploy().publish({ host, password, outDir: dist, outFile })
  console.log(r.message)
}

/** brs-cli runs the BrightScript tests in Node: the fixture's folder is mounted as ext1:, the zone pinned to the fixture's. */
function test() {
  const major = Number(process.versions.node.split('.')[0])
  if (major < 22) {
    console.error(`brs-cli needs Node 22 or later (this is ${process.version}).`)
    process.exit(2)
  }
  const cli = path.join(path.dirname(require.resolve('brs-node/package.json')), 'bin/brs.cli.js')
  const core = path.join(roku, 'components/core')
  const coreFiles = fs.readdirSync(core).filter(f => f.endsWith('.brs')).map(f => path.join(core, f))
  const fixture = path.join(repo, 'android/core/src/test/resources')
  let failed = false
  for (const t of fs.readdirSync(path.join(roku, 'test')).filter(f => f.endsWith('.brs'))) {
    const r = spawnSync(process.execPath, [cli, '--no-sg', '-x', fixture, ...coreFiles, path.join(roku, 'test', t)], {
      env: { ...process.env, TZ: 'America/Los_Angeles' }, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
    })
    const lines = (r.stdout + r.stderr).split('\n').filter(l => /^(PASS|FAIL)/.test(l))
    for (const l of lines) console.log(`${t}: ${l}`)
    if (r.status !== 0 || lines.length === 0 || lines.some(l => l.startsWith('FAIL'))) {
      failed = true
      if (lines.length === 0) console.log(`${t}: no result\n${(r.stdout + r.stderr).slice(-2000)}`)
    }
  }
  process.exit(failed ? 1 : 0)
}

/** Development only: dist/rerun-guide.zip in the BrightScript Simulation Engine (brs-engine, in the browser) at
 *  http://127.0.0.1:8090/. The engine's worker needs SharedArrayBuffer, so the page is served cross-origin isolated. */
async function sim() {
  await build()
  const out = path.join(dist, 'sim')
  fs.rmSync(out, { recursive: true, force: true })
  fs.mkdirSync(path.join(out, 'lib'), { recursive: true })
  const lib = (pkg, f) => path.join(path.dirname(require.resolve(`${pkg}/package.json`)), 'lib', f)
  for (const f of ['brs.api.js', 'brs.worker.js']) fs.copyFileSync(lib('brs-engine', f), path.join(out, 'lib', f))
  fs.copyFileSync(lib('brs-scenegraph', 'brs-sg.js'), path.join(out, 'lib', 'brs-sg.js'))
  // The device's common: volume (fonts, certificates, sounds), the SceneGraph extension's edition.
  fs.mkdirSync(path.join(out, 'assets'))
  fs.copyFileSync(path.join(path.dirname(require.resolve('brs-scenegraph/package.json')), 'assets/common.zip'), path.join(out, 'assets/common.zip'))
  fs.copyFileSync(path.join(roku, 'sim/index.html'), path.join(out, 'index.html'))
  const http = await import('node:http')
  const types = { '.html': 'text/html', '.js': 'text/javascript', '.zip': 'application/zip' }
  http.createServer((req, res) => {
    const name = decodeURIComponent(new URL(req.url, 'http://x').pathname).replace(/^\/$/, '/index.html')
    // The zip straight from dist/, so `npm run build` and a reload show a change.
    const file = name === '/' + outFile ? path.join(dist, outFile) : path.join(out, name)
    if (!file.startsWith(dist) || !fs.existsSync(file)) { res.writeHead(404); res.end(); return }
    res.writeHead(200, {
      'Content-Type': types[path.extname(file)] ?? 'application/octet-stream',
      'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'credentialless',
      'Cache-Control': 'no-store',
    })
    fs.createReadStream(file).pipe(res)
  }).listen(8090, '127.0.0.1', () => console.log('http://127.0.0.1:8090/'))
}

const modes = { build, test, deploy, sim }
const mode = modes[process.argv[2]]
if (!mode) {
  console.error('usage: node build.mjs build|test|deploy')
  process.exit(2)
}
await mode()
