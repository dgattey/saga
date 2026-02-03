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
- `run app` (build + launch, macOS only), `run app -b` (build only), `run app -v` (verbose)
- `run checks` (format + lint), `run checks --format`, `run checks --lint`
- `run bootstrap` to set up shell completions for `run`
- `run drop-bot-commits` for version bump conflicts
- `run version-and-release` for manual release tooling

## Code Style
- Swift uses `swift-format` with `.swift-format` (2-space indentation)
- Prefer `private` helpers and computed subviews to keep `body` concise
- Use `// MARK:` sections to organize larger views/types
- Favor `guard` + early return for invalid state
- Use `@AppStorage` for user settings and `@EnvironmentObject` for shared state
- Log failures with `LoggerService.log` in app code (scripts can use `print`)
- Reserve `fatalError` for unrecoverable setup failures
- Make impossible states unrepresentable

## Architecture & Patterns
- MVVM with SwiftUI views and `ObservableObject` view models
- Inject shared state via `@StateObject` in `SagaApp` and `@EnvironmentObject` elsewhere
- Navigation state is managed via `NavigationHistory` + `SidebarSelection`
- Scroll position persistence uses `ScrollPositionStore`, `ScrollKey`,
  and `PersistentScrollView`
- Caching is handled by `ImageCache` and `NetworkCache`
- Shared animations come from `AnimationSettings.shared`
- Shared UI lives in `Shared/Views`; shared models and utilities in `Shared/*` modules
- App specific UI and models live in `Features/*`, each with their own set of folders for Models, Views, etc.

## Key Integration Points
**Services**: `PersistenceService` (Core Data + Contentful), `LoggerService`,
`ImageCache`, `NetworkCache`, `CacheConfig`, `RichTextRenderer`,
book cover services (`OpenLibraryAPIService`, `BookcoverAPIService`)
**UI**: `ContentView` entry, `HomeView`/`BooksListView`, `ResponsiveLayout`,
`PersistentScrollView`, `GlassOverlayModifier`, `MenuBarCommands`
**Data**: `Saga.xcdatamodeld` + `PersistenceModel` for Core Data entities; register new
entities in both when adding models

## Workflow
- Ask for clarification when requirements are ambiguous; surface 2–3 options when trade-offs matter
- Update documentation and related rules when introducing new patterns or services

## Testing
No test targets found. Use `run checks` and a build (`run app -b` or Xcode) as
the standard verification loop.

## Environment
- Requires Xcode + SwiftUI/Combine
- `run bootstrap` writes `Saga/Config/Config.xcconfig` from env vars; set
  `CONTENTFUL_SPACE_ID` and `CONTENTFUL_ACCESS_TOKEN` before running
- `swift-format` is listed in the repo `Brewfile` (install with `brew bundle`)
- Validate formatting and linting before final review, and build the app too.

## Special Notes
- Do not mutate files outside the workspace root without explicit approval
- Avoid destructive git operations unless the user requests them directly
- When unsure or need to make a significant decision ASK the user for guidance
