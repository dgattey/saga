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
- `./run dev build` (`build/Saga.app`), `./run dev relaunch` (build + open in the background, never focused), `./run dev capture` (screenshot into `build/captures/`), `./run dev ios [--run]` (`build/Saga-iOS.app` on a headless simulator), `./run dev checks` (DylApp.toml, SwiftLint, dyl-lint, release checks), `./run dev --help`
- `./run ui` iPhone and iPad screenshots with fixture books (`scripts/ui-screenshots.sh`)
- `./run format` (`--check` to lint only) runs `swift format` with `.swift-format`
- `swift test` runs `SagaTests`
- `./run bootstrap` writes `Config.xcconfig` from 1Password
- `./run release <step>` is `release-kit` (version, bundle, sign, appcast, check [--live], publish, deploy); CI runs it, not you. Releases never commit to `main`: `publish` pushes the `v<version>` tag and deploys the site with the appcast and zip. The Sparkle feed `https://saga.gattey.com/appcast.xml` exists only on the site, so production deploys go through `release-kit` (Vercel git deploys of `main` are off; `site.yml` runs `./run release deploy` for `server/` changes)
- DylKit is cloned from scone-os into `.dylkit/` until `dgattey/dyl-kit` exists; set `DYLKIT_PATH` to use another checkout of its `Packages/DylKit`

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
`ImageCache`, `NetworkCache`, `CacheConfig`, `RichTextRenderer`, `AppUpdater.shared` (DylUpdates: Sparkle on macOS, inert on iOS),
book cover services (`OpenLibraryAPIService`, `BookcoverAPIService`)
**UI**: DylUI's `AppWindow` (main window, palette `SagaPalette`, launch overrides, Check for Updates menu) and `SettingsWindow`/`SettingsView` with `SettingsPage.saga`, `ContentView` entry, `HomeView`/`BooksListView`, `ResponsiveLayout`,
`PersistentScrollView`, `MenuBarCommands`
**Data**: `Saga.xcdatamodeld` + `PersistenceModel` for Core Data entities; register new
entities in both when adding models
**Server**: Hosted on `https://dylangattey.com` (`dgattey/dg`) under `/api/books/goodreads-sync` (Goodreads RSS → Contentful CMA + daily Vercel Cron) and `/api/books/sync` (local `Saga.app` book edits and deletions → Contentful CMA), authenticated via `CryptoKit.HMAC<SHA256>` (`X-Saga-Timestamp` + `X-Saga-Signature`) and Bearer token fallback.

## Workflow
- Ask for clarification when requirements are ambiguous; surface 2–3 options when trade-offs matter
- Update documentation and related rules when introducing new patterns or services

## Testing
- Unit and UI component tests live in `Tests/SagaTests/` and use native `SwiftTesting` (`import Testing`, `@Test`, `#expect`) and `ViewInspector` (`import ViewInspector`).
- Run unit tests with `swift test`, which runs without launching the app or hitting Contentful. Tests compile `Saga.xcdatamodeld` with `momc` themselves (`TestCoreDataStack`).
- UI coverage is headless iOS Simulator screenshots: `./run ui` (`scripts/ui-screenshots.sh`) seeds fixture books (`scripts/ui-fixture-store.swift`) into fresh iPhone and iPad simulators, launches with `--initial-view home|book` and `--appearance light|dark` (DylCore `LaunchOverrides.saga`, also `SAGA_INITIAL_VIEW` / `SAGA_APPEARANCE`), and checks each launch logged the screen it was asked for. PNGs land in `build/captures/`; CI uploads them as the `ui-screenshots` artifact. Look at them after visual changes. Never launch `build/Saga.app` on a Mac where Saga is installed: it shares the release bundle ID.
- Use `./run format --check`, `./run dev checks`, `./run dev build`, `swift test`, and `./run ui` as the standard verification loop.

## Environment
- Pure SwiftPM (`Package.swift`, Swift 6 language mode); no Xcode project. Xcode must be installed for `momc`, `actool`, and the SDKs
- `./run bootstrap` writes the gitignored `Config.xcconfig` from 1Password. devkit copies its values into the dev app's Info.plist (`[local-values]` in `DylApp.toml`); environment variables with the same names win, and without either the app gets placeholder credentials, which is what CI and releases build with
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
