[![GitHub version](https://flat.badgen.net/github/tag/dgattey/saga?cache=200)][gh] [![GitHub commits](https://flat.badgen.net/github/commits/dgattey/saga)][gh] [![Last commit](https://flat.badgen.net/github/last-commit/dgattey/saga/main)][gh]

# Saga

A native Swift app (iOS, macOS) for keeping track of what I've read, watched, played, and experienced. The vision is a personal knowledge base with full editing capabilities, synced via Contentful.

## Setup

```bash
scripts/bootstrap.sh
```

Bootstrap installs the Brewfile (1Password CLI, mise), installs the SwiftLint that `mise.toml` pins, and writes the gitignored `Config.xcconfig` with dev Contentful credentials from the `saga` 1Password vault. Without it, the app builds with placeholder credentials, which is what CI and releases use.

## App architecture

Saga follows an MVVM architecture with SwiftUI views:
- **Features/**: Domain-specific features (Books, Assets, Content, Settings)
  - Each feature contains Models, Views, ViewModels, and Services
- **Shared/**: Reusable components, extensions, and utilities
- **Services/**: Core services like persistence (Core Data) and syncing (Contentful)
- Navigation is managed via `NavigationHistory` with a home-based sidebar layout

## Development process

Saga is a plain SwiftPM package with no Xcode project, built with [DylKit](https://github.com/dgattey/dyl-kit)'s `devkit` and `release-kit`. App settings live in `DylApp.toml`: bundle ID, minimum OS, resources and icon to compile, dev credentials, and the release feed. Xcode must be installed and selected (`xcode-select`) for `momc` and `actool`, but you never open it.

```bash
swift run devkit build        # build/Saga Dev.app (bundle ID com.dylangattey.Saga.dev), ad-hoc signed
swift run devkit relaunch     # build and open it in the background
swift run devkit capture      # screenshot the main window into build/captures/
swift run devkit ios --run    # build/Saga-iOS.app on a headless simulator
scripts/ui-screenshots.sh     # iPhone and iPad screenshots of the main screens with fixture books
swift run devkit checks       # DylApp.toml, SwiftLint, dyl-lint and release checks
swift format format --in-place --recursive --parallel Sources Tests Package.swift scripts
swift test                    # unit tests
```

### Adding new models

When adding a new Core Data model:
1. Create the entity in `Saga.xcdatamodeld`
2. Create the corresponding Swift model file with `apply(_:)` mapping
3. Mark the class `@objc(EntityName)` so the unqualified `representedClassName` resolves

## Releases

Saga releases through `.github/workflows/dylkit.yml`, which calls DylKit's reusable `app.yml` workflow. Each merged PR that touches the app gets a version from the latest `v*` tag and its Release info checkbox, tags the merge commit, and uploads `Saga-<version>.zip`, a signed Sparkle `appcast.xml`, `release.json`, and rendered site icons to Saga's Vercel Blob store. Nothing is committed to `main`.

The download site in `server/` is `@dylkit/web`, configured by `[site]` in `DylApp.toml` via `withDylKit`, and Vercel's git integration deploys it from `main`. `/appcast.xml`, `/download/macos`, and the icon routes serve the latest release from the Blob store.

[gh]: https://github.com/dgattey/saga
