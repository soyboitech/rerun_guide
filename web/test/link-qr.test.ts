/// <reference types="node" />
// The Plex link screen's square: plex.tv's picture of the PIN, only while there is a live Plex code to scan.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { AppModel } from '../src/app/AppModel'

Object.defineProperty(globalThis, 'window', { configurable: true, value: {} })
await import('../src/app/AppModelOnboarding')   // after the stub: Platform reads window as it loads

test('the square is plex.tv\'s picture of a live Plex code, and nothing else', () => {
  const m = new AppModel()
  m.serviceKind = 'plex'; m.linkCode = 'VDQT'
  assert.equal(m.linkQRImage, 'https://plex.tv/api/v2/pins/qr/VDQT')
  m.linked = true; assert.equal(m.linkQRImage, null)
  m.linked = false; m.authError = 'x'; assert.equal(m.linkQRImage, null)
  m.authError = null; m.linkCode = 'VD/T'; assert.equal(m.linkQRImage, null)
  m.linkCode = '83948'; m.serviceKind = 'emby'; assert.equal(m.linkQRImage, null)
})
