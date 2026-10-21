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
and `SyncViewModel`. App code lives under `Saga/Saga/` with feature modules and
shared UI/utilities.

## Commands
- `./run --help` or `run --help` to list scripts
- `run app` (`scripts/build-macos.sh` + launch in background via `open -g -j`, macOS only), `run app -b` (build only), `run app -t` / `run app --test` (`swift test`), `run app -u` / `run app --ui` (iOS Simulator screenshots), `run app -r` (release), `run app -g` (background + exit), `run app -f` (foreground)
- `scripts/build-ios-sim.sh` builds `build/Saga-iOS.app` for the iOS Simulator
- `run checks` (format + lint), `run checks --format`, `run checks --lint`
- `run bootstrap` to set up shell completions for `run`
- `run config` to write `Config.xcconfig` from the environment
- `run version-and-release` for manual release tooling (`package` builds, signs, zips `Saga-<version>.zip`, and generates Sparkle `appcast.xml` via `scripts/generate-appcast.sh` and `scripts/release-notes.sh` with cumulative release notes capped at the last 10 versions); `scripts/verify-release.sh` checks the result against the latest published release; the app's Sparkle feed is `https://saga.gattey.com/appcast.xml`, which the site redirects to the latest GitHub release's appcast (`server/next.config.ts`); releases never commit to `main`, and `scripts/check-site-feed.sh` checks the site serves the expected feed (PR CI against a local `next start`, release CI against the live site before and after publishing)

## Code Style
- Swift uses `swift-format` with `.swift-format` (2-space indentation)
- Prefer `private` helpers and computed subviews to keep `body` concise
- Use `// MARK:` sections to organize larger views/types
- Favor `guard` + early return for invalid state
- Use `@AppStorage` for user settings in views and `@Environment(Type.self)` for shared state
- Log failures with `LoggerService.log` in app code (scripts can use `print`)
- Reserve `fatalError` for unrecoverable setup failures
- Make impossible states unrepresentable

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
`ImageCache`, `NetworkCache`, `CacheConfig`, `RichTextRenderer`, `UpdaterViewModel` (Sparkle automatic updates on macOS),
book cover services (`OpenLibraryAPIService`, `BookcoverAPIService`)
**UI**: `ContentView` entry, `HomeView`/`BooksListView`, `ResponsiveLayout`,
`PersistentScrollView`, `MenuBarCommands`
**Data**: `Saga.xcdatamodeld` + `PersistenceModel` for Core Data entities; register new
entities in both when adding models
**Server**: Hosted on `https://dylangattey.com` (`dgattey/dg`) under `/api/books/goodreads-sync` (Goodreads RSS → Contentful CMA + daily Vercel Cron) and `/api/books/sync` (local `Saga.app` book edits and deletions → Contentful CMA), authenticated via `CryptoKit.HMAC<SHA256>` (`X-Saga-Timestamp` + `X-Saga-Signature`) and Bearer token fallback.

## Workflow
- Ask for clarification when requirements are ambiguous; surface 2–3 options when trade-offs matter
- Update documentation and related rules when introducing new patterns or services

## Testing
- Unit and UI component tests live in `Saga/SagaTests/` and use native `SwiftTesting` (`import Testing`, `@Test`, `#expect`) and `ViewInspector` (`import ViewInspector`).
- Run unit tests with `run app --test` (or `run app -t`), which runs `swift test` without launching the app or hitting Contentful. Tests compile `Saga.xcdatamodeld` with `momc` themselves (`TestCoreDataStack`).
- UI coverage is headless iOS Simulator screenshots: `run app --ui` (`scripts/ui-screenshots.sh`) seeds fixture books (`scripts/ui-fixture-store.swift`) into fresh iPhone and iPad simulators, launches with `--initial-view home|book` and `--appearance light|dark` (`LaunchOptions`, also `SAGA_INITIAL_VIEW` / `SAGA_APPEARANCE`), and checks each launch logged the screen it was asked for. PNGs land in `build/captures/`; CI uploads them as the `ui-screenshots` artifact. Look at them after visual changes. Never launch `build/Saga.app` on a Mac where Saga is installed: it shares the release bundle ID.
- Use `run checks`, `run app -b`, `run app -t`, and `run app --ui` as the standard verification loop.

## Environment
- Pure SwiftPM (`Package.swift`); no Xcode project. Xcode must be installed for `momc`, `actool`, and the SDKs
- `run bootstrap` writes `Config.xcconfig` from 1Password; `run config`
 writes the same file from `CONTENTFUL_SPACE_ID` and `CONTENTFUL_ACCESS_TOKEN` (plus optional `SAGA_API_SECRET`)
- The file is gitignored and optional: `scripts/lib/app-config.sh` falls back to placeholder credentials, which is what CI and releases build with
- **1Password CLI (`op`) rules**:
  - Never call `op` repeatedly across separate shell commands or loops (each shell tool call is a new terminal session and triggers a separate Touch ID prompt).
  - If a secret is needed and not already cached locally in `Config.xcconfig` or `.env.local`, batch every needed `op` read into a single shell command, write them into a gitignored `.env.local` (or `Config.xcconfig`), and source that file on subsequent commands.
  - Never print secret values.
- `swift-format` is listed in the repo `Brewfile` (install with `brew bundle`)
- Validate formatting and linting before final review, and build the app too.

## Special Notes
- Do not mutate files outside the workspace root without explicit approval
- Avoid destructive git operations unless the user requests them directly
- When unsure or need to make a significant decision ASK the user for guidance
