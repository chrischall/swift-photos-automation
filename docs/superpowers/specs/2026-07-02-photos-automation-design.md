# swift-photos-automation — Design

**Date:** 2026-07-02
**Status:** Approved

## Purpose

A Swift library for reading and writing the Apple Photos library on macOS, to be consumed by the `apple-swift-mcp` MCP server as a sibling of `swift-notes-automation` and `swift-mail-automation`. Supported operation areas: read/search the library, export photo data (files and in-memory), organize (albums, favorites, titles/descriptions/keywords), and import.

## Package & repo shape

- `swift-tools-version: 6.0`, `platforms: [.macOS(.v14)]`, Swift 6 strict concurrency.
- Single library product **`PhotosAutomation`**, flat layout: `Sources/PhotosAutomation/*.swift`, `Tests/PhotosAutomationTests/*.swift`.
- Zero external dependencies (matches swift-notes-automation).
- Standard repo scaffolding: MIT LICENSE (Chris Hall), README with badges (CI, SPI, MIT) and Install / Quickstart / API table / Permissions / Testing sections, `.spi.yml` (DocC for `PhotosAutomation`), `.swiftformat` (swift 6.0, 120 col, patternlet hoist, wrap disabled), `CLAUDE.md`, ~~`VERSION`~~ (see correction below), `CHANGELOG.md`, release-please config, `.github/workflows` (ci / release-please / auto-merge / pr-auto-review / claude) on `macos-15` via the `chrischall/workflows` reusable pipeline, dependabot, Conventional-Commit PR titles.

> **Correction (2026-08-15):** the `VERSION` file listed above was never
> load-bearing and has since been deleted (#12). release-please is configured
> `release-type: simple`, whose updater targets `version.txt` — not `VERSION`
> — so the file never moved off its seed value while
> `.release-please-manifest.json` tracked every release correctly. Four repos
> in this fleet were scaffolded with it and all four went stale. **Do not
> create it when reusing this spec.**


## Architecture — hybrid with two transports

```
PhotoService (Sendable struct, all ops async throws)
 ├── PhotoLibraryStore (protocol)  ← PhotoKitStore | FakePhotoLibraryStore
 │     structured search, metadata, export, import, albums, favorites
 └── AppleScriptRunner (protocol)  ← NSAppleScriptRunner | FakeAppleScriptRunner
       (copied verbatim from siblings)
       only: set title/description/keywords + free-text search
```

Split by what each API is good at:

- **PhotoKit** (`PHPhotoLibrary`, `PHAsset`, `PHAssetResource`, `PHImageManager`, change requests): list albums, fetch/filter assets (date range, media type, favorites, album), asset metadata, export originals, in-memory resized JPEG, create albums, add/remove album members, set favorite, import files.
- **AppleScript** (via `NSAppleScript`, wrapped in `Task.detached` exactly like the siblings): the two things PhotoKit cannot do — **writing titles/descriptions/keywords** and **free-text search** (Photos' `search for` command matches titles, keywords, and detected content).
- Photos' AppleScript `media item id` equals PhotoKit's `localIdentifier`, so a single asset ID works across both transports.

### Components

| Unit | Kind | Responsibility |
|---|---|---|
| `PhotoService` | `Sendable` struct | Public API; input validation; orchestrates store + runner |
| `PhotoLibraryStore` | protocol (`Sendable`) | Abstract PhotoKit operations |
| `PhotoKitStore` | struct/actor | Concrete PhotoKit implementation |
| `AppleScriptRunner` / `NSAppleScriptRunner` | protocol / struct | AppleScript transport, copied from siblings |
| `PhotoAsset`, `PhotoAlbum` | value types | `Equatable, Hashable, Identifiable, Sendable` |
| `PhotoSearchCriteria` | value type | dateRange, mediaType, favoritesOnly, albumId, limit |

## Public API

```swift
PhotoAsset  // id (localIdentifier), originalFilename, creationDate, mediaType,
            // isFavorite, pixelWidth/pixelHeight, latitude/longitude,
            // title?, itemDescription?, keywords?
PhotoAlbum  // id, title, assetCount

PhotoService:
  listAlbums() -> [PhotoAlbum]
  listAssets(albumId:limit:) -> [PhotoAsset]
  search(criteria: PhotoSearchCriteria) -> [PhotoAsset]   // PhotoKit predicates
  searchText(_:limit:) -> [PhotoAsset]    // AppleScript `search for`, hydrated via PhotoKit
  asset(id:) -> PhotoAsset
  exportOriginals(ids:to: URL) -> [URL]   // files, incl. video
  imageData(id:maxDimension:) -> Data     // in-memory JPEG for MCP base64
  createAlbum(title:) -> PhotoAlbum
  add(ids:toAlbum:) / remove(ids:fromAlbum:)
  setFavorite(id:_:)
  setTitle(id:_:) / setDescription(id:_:) / setKeywords(id:_:)   // AppleScript
  importFiles(urls:albumId:) -> [PhotoAsset]
```

Guard-clause input validation throws `.invalidInput` before touching either transport (empty ids, empty queries, limit <= 0, nonexistent import URLs).

## Error handling

- Transport: `AppleScriptError { case compile(String); case runtime(String) }` — verbatim from siblings.
- Domain: `PhotoServiceError { case invalidInput(String); case notFound(String); case permissionDenied; case operationFailed(String) }`.
- All `Error, Equatable, Sendable` with `LocalizedError` conformance. `permissionDenied` surfaces PhotoKit's explicit authorization state distinctly (the most common setup failure).

## Testing

- Swift Testing (`@Suite` / `@Test` / `#expect`).
- Unit: `FakePhotoLibraryStore` + `FakeAppleScriptRunner` (record calls, replay FIFO responses); internal `static` script-generation and parse helpers tested via `@testable import`.
- Integration: opt-in via `PHOTOS_AUTOMATION_INTEGRATION=1` using the shared `.disabled(if:)` trait pattern, so CI stays deterministic and prompt-free.
- **Cleanup caveat:** PhotoKit asset deletion always shows a user confirmation dialog, so integration tests cannot fully self-clean assets. They create uniquely-prefixed *albums* (silently deletable), reuse existing library assets for read tests, and the import test leaves its tiny (1px PNG) test image in the library — documented in the README.

## Permissions

Full Photos library access (TCC, `PHAuthorizationStatus`). README documents:

- `swift test` integration runs require the invoking terminal to be granted Photos access.
- `apple-swift-mcp` needs `NSPhotoLibraryUsageDescription` added to its embedded Info.plist (it already uses the `-sectcreate __TEXT __info_plist` linker trick — one-line follow-up there).

## Out of scope

- The `PhotoTool` MCP wrapper, registration in `AppleMCPMain.swift`, and the git-URL dependency bump in `apple-swift-mcp` — follow-up work in the server repo after this library's first tagged release.
- Asset deletion (requires user confirmation dialog; not useful for an MCP server).
- Smart album creation, Live Photos editing, iCloud shared albums.
