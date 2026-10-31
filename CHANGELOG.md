# Changelog

## [2.0.0](https://github.com/chrischall/swift-photos-automation/compare/v1.2.0...v2.0.0) (2026-10-30)


### ⚠ BREAKING CHANGES

* PhotoService methods throw PhotosError instead of bare PhotoServiceError / AppleScriptError, and AppleScriptRunner conformances must declare `throws(AppleScriptError)`. See README "Migrating from 1.x".

### Features

* adopt typed throws on the public PhotoService API ([#47](https://github.com/chrischall/swift-photos-automation/issues/47)) ([a19909b](https://github.com/chrischall/swift-photos-automation/commit/a19909b74301fbc9df8bd1a19f9e533c19de8914))

## [1.2.0](https://github.com/chrischall/swift-photos-automation/compare/v1.1.0...v1.2.0) (2026-10-30)


### Features

* Live Photo playback, original-resource reads and Subprogress copy progress on Swift 6.4 upcoming features ([#44](https://github.com/chrischall/swift-photos-automation/issues/44)) ([93b453f](https://github.com/chrischall/swift-photos-automation/commit/93b453f3bba1b9c402a89f18bb8b52f907c53377))
* read and write descriptions, keywords and ratings through PhotoKit ([#41](https://github.com/chrischall/swift-photos-automation/issues/41)) ([b2576d8](https://github.com/chrischall/swift-photos-automation/commit/b2576d81d66f919a07e3b69dac94a95194216903))


### Refactor

* mark the copyAlbum convenience overloads [@concurrent](https://github.com/concurrent) ([#46](https://github.com/chrischall/swift-photos-automation/issues/46)) ([238049c](https://github.com/chrischall/swift-photos-automation/commit/238049c6c1bd29ccbd43262ce922c127e5007fb0)), closes [#45](https://github.com/chrischall/swift-photos-automation/issues/45)

## [1.1.0](https://github.com/chrischall/swift-photos-automation/compare/v1.0.0...v1.1.0) (2026-10-30)


### Features

* require macOS 27.2 ([#38](https://github.com/chrischall/swift-photos-automation/issues/38)) ([74dacea](https://github.com/chrischall/swift-photos-automation/commit/74daceaa8d2dc960ec9a05649cb5a35c897faac8))

## [1.0.0](https://github.com/chrischall/swift-photos-automation/compare/v0.4.0...v1.0.0) (2026-10-30)


### ⚠ BREAKING CHANGES

* require macOS 26 ([#36](https://github.com/chrischall/swift-photos-automation/issues/36))

### Features

* require macOS 26 ([#36](https://github.com/chrischall/swift-photos-automation/issues/36)) ([a84ab0f](https://github.com/chrischall/swift-photos-automation/commit/a84ab0fdc4ca9a39bdcde6c726af855d07a43706))

## [0.4.0](https://github.com/chrischall/swift-photos-automation/compare/v0.3.0...v0.4.0) (2026-10-09)


### Features

* **photos:** optional allowedRoot path confinement for export and import ([#32](https://github.com/chrischall/swift-photos-automation/issues/32)) ([4ea1bea](https://github.com/chrischall/swift-photos-automation/commit/4ea1beabb823d09fa2ec3a3f386df7f1469fd67d))


### Bug Fixes

* resolve low-severity audit findings ([#29](https://github.com/chrischall/swift-photos-automation/issues/29)) ([5bd401d](https://github.com/chrischall/swift-photos-automation/commit/5bd401d426b795377945bd68b51212f0479905a8))

## [0.3.0](https://github.com/chrischall/swift-photos-automation/compare/v0.2.0...v0.3.0) (2026-09-29)


### Features

* **photos:** make shared album copies resumable ([#27](https://github.com/chrischall/swift-photos-automation/issues/27)) ([e0b1bb3](https://github.com/chrischall/swift-photos-automation/commit/e0b1bb36531fcf398723168ce8953bee51270eb5))

## [0.2.0](https://github.com/chrischall/swift-photos-automation/compare/v0.1.4...v0.2.0) (2026-09-29)


### Features

* **photos:** copy shared albums into local albums ([#24](https://github.com/chrischall/swift-photos-automation/issues/24)) ([66ce70d](https://github.com/chrischall/swift-photos-automation/commit/66ce70d99ab89d2f4fc4fc29a9e3cb4a1625f05c))

## [0.1.4](https://github.com/chrischall/swift-photos-automation/compare/v0.1.3...v0.1.4) (2026-09-24)


### Bug Fixes

* **export:** trim whitespace from asset ids before exporting originals ([#22](https://github.com/chrischall/swift-photos-automation/issues/22)) ([49ed124](https://github.com/chrischall/swift-photos-automation/commit/49ed12467a6e695cac33feeda563ff3546e409b7))
* keep commas and tabs in metadata, collapse repeated ids, and check import files before importing ([#19](https://github.com/chrischall/swift-photos-automation/issues/19)) ([084709e](https://github.com/chrischall/swift-photos-automation/commit/084709e56091631d24d51ce6aa34f5e60151065a))

## [0.1.3](https://github.com/chrischall/swift-photos-automation/compare/v0.1.2...v0.1.3) (2026-08-15)


### Documentation

* mark the VERSION file superseded in the scaffolding plan and spec ([#13](https://github.com/chrischall/swift-photos-automation/issues/13)) ([c810874](https://github.com/chrischall/swift-photos-automation/commit/c81087479040af72b2c0a0e39ad338df80fdf41c))

## [0.1.2](https://github.com/chrischall/swift-photos-automation/compare/v0.1.1...v0.1.2) (2026-08-09)


### Bug Fixes

* run AppleScript on the main thread so cross-application scripts stop stalling ([#7](https://github.com/chrischall/swift-photos-automation/issues/7)) ([7d63ff4](https://github.com/chrischall/swift-photos-automation/commit/7d63ff4ae2f6d620a6ba09882d8300a40643c3e8))


### Documentation

* reattach the run(source:) doc comment and serialize the new suite ([#10](https://github.com/chrischall/swift-photos-automation/issues/10)) ([80f8166](https://github.com/chrischall/swift-photos-automation/commit/80f8166d6c0f10cc56af7d15b99cc2bbfcea336d))

## [0.1.1](https://github.com/chrischall/swift-photos-automation/compare/v0.1.0...v0.1.1) (2026-07-19)


### Documentation

* replace duplicated fleet policy with a pointer ([#3](https://github.com/chrischall/swift-photos-automation/issues/3)) ([a69d9af](https://github.com/chrischall/swift-photos-automation/commit/a69d9af8d4c331fd01820865f5228ed64137e761))

## 0.1.0 (2026-07-02)

### Features

- Initial release: hybrid PhotoKit + AppleScript library for Apple Photos —
  structured and free-text search, metadata reads/writes (titles,
  descriptions, keywords, favorites), original export, in-memory JPEG
  renditions, album management, and import.
