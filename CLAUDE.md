# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Swift 6 library exposing the Apple Photos library on macOS through one `PhotoService` facade over two transports:

- **PhotoKit** (`PhotoKitStore: PhotoLibraryStore`) — structured search, metadata (descriptions, keywords, ratings, file sizes — read and write, via the macOS 27 `extendedMetadata` / `PHAssetChangeRequest` APIs, prefetched in bulk), export, in-memory JPEG renditions, albums, favorites, import.
- **AppleScript** (`NSAppleScriptRunner: AppleScriptRunner`) — only what PhotoKit cannot do: titles (read and write) and free-text search (`search for`).

Target: macOS 27.2+, swift-tools-version 6.4, Swift 6 language mode. Zero external dependencies. Strict concurrency is on (all public types are `Sendable`; no `@unchecked Sendable` in library code — use `Synchronization.Mutex`).

## Commands

```bash
swift build                                          # debug build
swift test                                           # pure-Swift tests only — live suites are opt-in
swift test --filter PhotoServiceReadTests            # single suite
PHOTOS_AUTOMATION_INTEGRATION=1 swift test           # + live PhotoKit-only integration suite
PHOTOS_AUTOMATION_INTEGRATION=1 PHOTOS_AUTOMATION_APPLESCRIPT=1 swift test  # + live AppleScript-to-Photos tests
swiftformat . --lint                                 # lint (config in .swiftformat)
```

- Live suites (`PhotoServiceIntegrationTests`, `NSAppleScriptRunnerTests`) are gated by env-var `.disabled(if:)` traits, `.serialized`. Two tiers:
  - `PHOTOS_AUTOMATION_INTEGRATION=1` — PhotoKit-only tests (import, albums, favorites, rendition, export, and the description/keyword/rating round-trip). Needs Photos library access (prompted on first run). No Automation permission required, and nothing hangs.
  - `PHOTOS_AUTOMATION_APPLESCRIPT=1` (additive, on top of the above) — the AppleScript-to-Photos tests: title round-trip and free-text search. Need **Automation → Photos** permission for the test binary. `NSAppleScript` targeting Photos from inside a `swift test` bundle is unreliable — it can hang on the permission prompt or flake with error -1751 (reentrancy) — so these are split behind the second var to keep the standard integration pass hang-free. The library's AppleScript paths themselves work fine from a normal binary (e.g. apple-swift-mcp); the caveat is about the test-bundle environment, not the code.
  - Without the env vars, all of the above are skipped, so CI stays deterministic and prompt-free.

## Architecture

- `PhotoService` (public API, `Sources/PhotosAutomation/PhotoService.swift`) validates inputs, orchestrates the two injected transports, and owns all AppleScript **generation** (static script builders) and **parsing** (static parse helpers) — both unit-testable without AppleScript running.
- `PhotoLibraryStore` protocol isolates PhotoKit; `FakePhotoLibraryStore` (test target) is the unit-test double. `PhotoKitStore` is verified by the integration suite, not unit tests — keep logic there thin and push anything parseable/decidable into `PhotoService` statics.
- `AppleScriptRunner`/`NSAppleScriptRunner` are copied from swift-notes-automation — treat as vendored; don't redesign.

### Non-obvious constraints to respect

1. **Asset IDs**: PhotoKit `localIdentifier` == AppleScript `media item id`. The integration test's title round-trip (`title round-trip via AppleScript`, AppleScript-gated) is the canary; if it breaks on a macOS update, add id normalization in the script builders.
2. **Every string interpolated into AppleScript must go through `PhotoService.escapeForAppleScript`** (backslashes before quotes).
3. **`NSAppleScript` is non-reentrant inside test bundles** — any suite that runs it live carries `.serialized` and the `PHOTOS_AUTOMATION_APPLESCRIPT` gate on top of the base integration gate (error -1751 flakes otherwise).
4. **No deletion of assets or albums, ever** — PhotoKit deletion of either always shows a blocking confirmation dialog. The integration suite therefore deletes nothing it creates: the imported 1×1 test PNG and the uniquely-named `PhotosAutomationTests-*` album both stay in the library (documented in README; remove by hand).
5. **`performChanges` closures are `@Sendable` and run on an arbitrary queue** — fetch PH objects *inside* the closure; smuggle results out via `Locked<T>` (a `Mutex` box; mutate with `withLock`), never captured vars.
6. **Title hydration is best-effort**: `asset(id:)` swallows AppleScript failures and leaves `title` `nil`; description/keywords/rating come from PhotoKit and are unaffected. `setTitle` propagates `AppleScriptError`; `setDescription`/`setKeywords`/`setRating` throw `PhotoServiceError` — consumers catch both error types.
7. **Test names are raw identifiers** (``@Test func `does a thing`()``) — `.swiftformat` targets Swift 6.4, and swiftformat rewrites camelCase test names this way.

<!-- pr-workflow:v3 -->
## Pull requests & release notes

Fleet policy — Conventional-Commit PR titles, labels, the auto-review /
auto-merge ladder, auto-review follow-up issues, PR timing, and release PRs —
lives in `~/.claude/CLAUDE.md`. Don't restate it here; the copies drifted.

Shared technical conventions (publishing, bundling, versioning guards,
write-verification, transport archetypes, testing traps) live in
[`chrischall/workflows`](https://github.com/chrischall/workflows):
`docs/fleet-conventions.md`, plus `README.md` for the CI pipeline contract.

