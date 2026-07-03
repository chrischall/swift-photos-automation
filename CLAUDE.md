# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Swift 6 library exposing the Apple Photos library on macOS through one `PhotoService` facade over two transports:

- **PhotoKit** (`PhotoKitStore: PhotoLibraryStore`) — structured search, metadata, export, in-memory JPEG renditions, albums, favorites, import.
- **AppleScript** (`NSAppleScriptRunner: AppleScriptRunner`) — only what PhotoKit cannot do: writing titles/descriptions/keywords and free-text search (`search for`).

Target: macOS 14+. Zero external dependencies. Strict concurrency is on (all public types are `Sendable`).

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
  - `PHOTOS_AUTOMATION_INTEGRATION=1` — PhotoKit-only tests (import, albums, favorites, rendition, export). Needs Photos library access (prompted on first run). No Automation permission required, and nothing hangs.
  - `PHOTOS_AUTOMATION_APPLESCRIPT=1` (additive, on top of the above) — the AppleScript-to-Photos tests: metadata round-trip (title/keywords) and free-text search. Need **Automation → Photos** permission for the test binary. `NSAppleScript` targeting Photos from inside a `swift test` bundle is unreliable — it can hang on the permission prompt or flake with error -1751 (reentrancy) — so these are split behind the second var to keep the standard integration pass hang-free. The library's AppleScript paths themselves work fine from a normal binary (e.g. apple-swift-mcp); the caveat is about the test-bundle environment, not the code.
  - Without the env vars, all of the above are skipped, so CI stays deterministic and prompt-free.

## Architecture

- `PhotoService` (public API, `Sources/PhotosAutomation/PhotoService.swift`) validates inputs, orchestrates the two injected transports, and owns all AppleScript **generation** (static script builders) and **parsing** (static parse helpers) — both unit-testable without AppleScript running.
- `PhotoLibraryStore` protocol isolates PhotoKit; `FakePhotoLibraryStore` (test target) is the unit-test double. `PhotoKitStore` is verified by the integration suite, not unit tests — keep logic there thin and push anything parseable/decidable into `PhotoService` statics.
- `AppleScriptRunner`/`NSAppleScriptRunner` are copied from swift-notes-automation — treat as vendored; don't redesign.

### Non-obvious constraints to respect

1. **Asset IDs**: PhotoKit `localIdentifier` == AppleScript `media item id`. The integration test's title round-trip (`metadataRoundTrip`, AppleScript-gated) is the canary; if it breaks on a macOS update, add id normalization in the script builders.
2. **Every string interpolated into AppleScript must go through `PhotoService.escapeForAppleScript`** (backslashes before quotes).
3. **`NSAppleScript` is non-reentrant inside test bundles** — any suite that runs it live carries `.serialized` and the `PHOTOS_AUTOMATION_APPLESCRIPT` gate on top of the base integration gate (error -1751 flakes otherwise).
4. **No deletion of assets or albums, ever** — PhotoKit deletion of either always shows a blocking confirmation dialog. The integration suite therefore deletes nothing it creates: the imported 1×1 test PNG and the uniquely-named `PhotosAutomationTests-*` album both stay in the library (documented in README; remove by hand).
5. **`performChanges` closures are `@Sendable` and run on an arbitrary queue** — fetch PH objects *inside* the closure; smuggle results out via `Locked<T>`, never captured vars.
6. **Metadata hydration is best-effort**: `asset(id:)` swallows AppleScript failures and leaves title/description/keywords `nil`. Metadata *writes* propagate `AppleScriptError` — consumers catch both error types.

<!-- pr-workflow:v2 -->
## Pull requests & release notes

**Default workflow: branch + PR, even for solo work.** Direct pushes to `main` skip review *and* skip auto-generated release notes — GitHub's `generate_release_notes` (configured in `.github/release.yml`) only picks up merged PRs. Push directly to `main` only when the user explicitly asks for it (e.g. emergency hotfix).

For every PR, apply exactly one label so it lands in the right release-notes section:

| Label                | Section in release notes |
|----------------------|--------------------------|
| `enhancement`        | Features                 |
| `bug`                | Bug Fixes                |
| `security`           | Security                 |
| `refactor`           | Refactor                 |
| `documentation`      | Documentation            |
| `test`               | Tests                    |
| `dependencies`       | Dependencies             |
| `ci` / `github_actions` | CI & Build            |
| *(none / unmatched)* | Other Changes            |
| `ignore-for-release` | Hidden from notes        |

The **PR title MUST be a Conventional Commit**, written user-facing (`fix(scope): …`, `feat(scope): …`), not internal shorthand. Because the repo squash-merges, the PR title *becomes the squash commit's subject line* — the only thing release-please parses to pick the version bump and changelog section. Only `feat` (minor), `fix` (patch), and `!`/`BREAKING CHANGE` (major) cut a release; `perf`/`refactor`/`docs` show in the changelog without bumping; `ci`/`test`/`build`/`chore` are recognised but hidden (see `release-please-config.json` → `changelog-sections`). A title without a conventional type is invisible to release-please — no bump, no changelog line. Prefixes in *individual commits* don't help; squash keeps only the title.

Open with `gh pr create --label <label>` (or `--label ignore-for-release` for chores not worth a line). **Don't run `gh pr merge` yourself** — leave merging to the user. The repo is **squash-only** (no merge commit, no rebase), so don't pass `--merge`/`--rebase`.
