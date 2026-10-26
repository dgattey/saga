# Agent Guide

## Purpose
Agents act as senior Swift collaborators. Keep responses concise,
clarify uncertainty before coding, and align suggestions with the rules linked below.

## Rule Index
- `rule-loading.mdc` — always load; points to other relevant rules
- `general.mdc` — core engineering principles for Saga
- `view.mdc` — SwiftUI view conventions
- `view-model.mdc` — ViewModel patterns and async work
- `logging.mdc` — LoggerService usage (no `print()` in app code)
- `post-change-checks.mdc` — lint/format/build steps after big changes
- `rules.mdc` — how to author or update rule files

## Repository Overview
Saga is a SwiftUI MVVM app (macOS/iOS) for tracking books and other media.
Data is stored in Core Data and synced via Contentful using `PersistenceService`
and `SyncViewModel`. App code lives under `Sources/Saga/` with feature modules and
shared UI/utilities. It's built with DylKit (`DylCore`, `DylUI`, `DylUpdates`, `devkit`, `release-kit`), configured by `DylApp.toml`.

## Commands
- `swift run devkit build` (`build/Saga Dev.app`, bundle ID `com.dylangattey.Saga.dev`, so it never shares state with an installed Saga), `swift run devkit relaunch` (build + open in the background, never focused), `swift run devkit capture` (screenshot into `build/captures/`), `swift run devkit ios [--run]` (`build/Saga-iOS.app` on a headless simulator), `swift run devkit checks` (DylApp.toml, SwiftLint, dyl-lint, release checks), `swift run devkit verify` (checks + build + tests), `swift run devkit --help`
- `scripts/ui-screenshots.sh` iPhone and iPad screenshots with fixture books (`scripts/ui-fixture-store.swift`)
- `swift format format --in-place --recursive --parallel Sources Tests Package.swift scripts` (`swift format lint --strict --recursive --parallel Sources Tests Package.swift scripts` to lint only) runs `swift format` with `.swift-format`
- `swift test` runs `SagaTests`
- `scripts/bootstrap.sh` writes `Config.xcconfig` from 1Password
- `./scripts/sync-web-icons.sh` regenerates `server/public/` favicons, app icons, `opengraph-image.png`, and `server/web-assets-manifest.json` from `Sources/Saga/AppIcon.icon`; `./scripts/sync-web-icons.sh --check` verifies they are in sync
- `swift run release-kit <step>` is `release-kit`; CI runs it, not you. Releases go through `.github/workflows/dylkit.yml` (calling `dgattey/dyl-kit/.github/workflows/app.yml@v0.6.1`): tags the merge commit and uploads the zip, `appcast.xml`, `release.json`, `history.json`, and site icons to Saga's Vercel Blob store, never a commit to `main`
- The site (`server/`) is `@dylkit/web` configured by `[site]` in `DylApp.toml` via `withDylKit`; Vercel's git integration deploys `main`
- DylKit comes from `github.com/dgattey/dyl-kit` (`from: "0.6.1"`); `@dylkit/web` installs with `pnpm` from the matching release tarball

## Code Style
- Swift uses `swift-format` with `.swift-format` (2-space indentation)
- Prefer `private` helpers and computed subviews to keep `body` concise
- Use `// MARK:` sections to organize larger views/types
- Favor `guard` + early return for invalid state
- Use `@AppStorage` for user settings in views and `@Environment(Type.self)` for shared state
- Log failures with `LoggerService.log` in app code (scripts can use `print`)
- Reserve `fatalError` for unrecoverable setup failures
- Make impossible states unrepresentable
- **Single source of truth (`/poteto-mode`)**: Apply `subtract-before-you-add`, `migrate-callers-then-delete-legacy-apis`, `model-the-domain`, and `minimize-reader-load` — when introducing a new way, migrate all callers and delete the old API/view/helper in the same change; never leave compatibility shims, pass-through wrappers, or parallel implementations

## Architecture & Patterns
- MVVM with SwiftUI views and `@Observable` view models (Core Data `NSManagedObject`s stay `@ObservedObject`)
- Own shared state with `@State` in `SagaApp`, inject it with `.environment(_:)`, read it with `@Environment(Type.self)`, and use `@Bindable` for bindings
- Navigation state is managed via `NavigationHistory` + `SidebarSelection`
- Scroll position persistence uses `ScrollPositionStore`, `ScrollKey`,
  and `PersistentScrollView`
- Caching is handled by `ImageCache` and `NetworkCache`
- Shared animations come from `AnimationSettings.shared`
- Shared UI lives in `Shared/Views`; shared models and utilities in `Shared/*` modules
- App specific UI and models live in `Features/*`, each with their own set of folders for Models, Views, etc.

## Key Integration Points
**Services**: `PersistenceService` (Core Data + Contentful CDA), `GoodreadsSyncService` (HMAC-SHA256 signed client for `https://dylangattey.com/api/books/goodreads-sync` and `https://dylangattey.com/api/books/sync`), `LoggerService`,
`ImageCache`, `NetworkCache`, `CacheConfig`, `RichTextRenderer`, `AppUpdater.shared` (DylUpdates: Sparkle on macOS, inert on iOS),
book cover services (`OpenLibraryAPIService`, `BookcoverAPIService`, unified by `CoverImageResolver.bestCoverURL`),
`CoverImageStore` (dropped/pasted covers in Application Support, stored on `Book.localCoverImageURL`, compressed to ≤1600px JPEG for `coverImageBase64` + `coverImageContentType` uploads),
`BookMutationService` (create/edit/delete books locally, then push to `/api/books/sync`)
**Editing**: `BookContentView` swaps read mode for `BookEditorView` (⌘E); `File > New Book…` (⌘N) and the
sidebar `+` present the same editor in create mode. Edits live in a `BookDraft` until Done, covering both the public `reviewDescription` ("Review") and private freeform `notes` ("Private Notes", indexed by `BookSearchEngine` and the `.hasNotes` token).
**UI**: DylUI's `AppWindow` (main window, palette `SagaPalette`, launch overrides, Check for Updates menu), `SettingsView` (`SettingsPane`, `SettingsHeaderView`, `AppInformationView`, `CreditsView`, `CacheLimitRow`), `ContentView` entry, `HomeView`/`BooksListView` (`NowReadingBarView`, `HomeBookSort` for Home book count and flat/grouped sort modes), `BookEditorialLayout`,
`PersistentScrollView`, `MenuBarCommands`
**Data**: `Saga.xcdatamodeld` for Core Data entities (`Book`, `Asset`); each model maps remote Contentful payloads via `apply(_:)`
**Server**: Hosted on `https://dylangattey.com` (`dgattey/dg`) under `/api/books/goodreads-sync` (Goodreads RSS → Contentful CMA + daily Vercel Cron) and `/api/books/sync` (local `Saga.app` book edits and deletions → Contentful CMA), authenticated via `CryptoKit.HMAC<SHA256>` (`X-Saga-Timestamp` + `X-Saga-Signature`) and Bearer token fallback.

## Workflow
- Ask for clarification when requirements are ambiguous; surface 2–3 options when trade-offs matter
- Update documentation and related rules when introducing new patterns or services
- **Keep `saga.gattey.com` (`server/`) and `dylangattey.com` (`dgattey/dg`) in sync**: Whenever `Sources/Saga/AppIcon.icon`, `Sources/Saga/Assets.xcassets`, or major UI screens change, run `./scripts/sync-web-icons.sh` (and update `server/public/saga-*.png` + `[site]` in `DylApp.toml` when UI designs change), verify with `./scripts/sync-web-icons.sh --check` and `cd server && pnpm test && pnpm typecheck && pnpm build`, and coordinate with `dgattey/dg` (`dylangattey.com`) so favicons and web previews stay in sync.

## Testing
- Unit and UI component tests live in `Tests/SagaTests/` and use native `SwiftTesting` (`import Testing`, `@Test`, `#expect`) and `ViewInspector` (`import ViewInspector`).
- Run unit tests with `swift test`, which runs without launching the app or hitting Contentful. Tests compile `Saga.xcdatamodeld` with `momc` themselves (`TestCoreDataStack`).
- UI coverage is headless iOS Simulator screenshots: `scripts/ui-screenshots.sh` seeds fixture books (`scripts/ui-fixture-store.swift`) into fresh iPhone and iPad simulators, launches with `DYLKIT_INITIAL_VIEW=home|book` and `DYLKIT_APPEARANCE=light|dark` (DylCore `LaunchOverrides.current`), and checks each launch logged the screen it was asked for. PNGs land in `build/captures/`; CI uploads them as the `ui-screenshots` artifact. Look at them after visual changes.
- Use `swift format lint --strict --recursive --parallel Sources Tests Package.swift scripts`, `swift run devkit checks`, `swift run devkit build`, `swift test`, and `scripts/ui-screenshots.sh` as the standard verification loop.

## Environment
- Pure SwiftPM (`Package.swift`, Swift 6 language mode); no Xcode project. Xcode must be installed for `momc`, `actool`, and the SDKs
- `scripts/bootstrap.sh` writes the gitignored `Config.xcconfig` from 1Password. devkit copies its values into the dev app's Info.plist (`[local-values]` in `DylApp.toml`); environment variables with the same names win, and without either the app gets placeholder credentials, which is what CI and releases build with
- **1Password CLI (`op`) rules**:
  - Never call `op` repeatedly across separate shell commands or loops (each shell tool call is a new terminal session and triggers a separate Touch ID prompt).
  - If a secret is needed and not already cached locally in `Config.xcconfig` or `.env.local`, batch every needed `op` read into a single shell command, write them into a gitignored `.env.local` (or `Config.xcconfig`), and source that file on subsequent commands.
  - Never print secret values.
- `swift format` ships with the toolchain; `mise.toml` pins SwiftLint (`mise install`)
- Validate formatting and linting before final review, and build the app too.

## Special Notes
- Do not mutate files outside the workspace root without explicit approval
- Avoid destructive git operations unless the user requests them directly
- When unsure or need to make a significant decision ASK the user for guidance
