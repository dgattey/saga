[![GitHub version](https://flat.badgen.net/github/tag/dgattey/saga?cache=200)][gh] [![GitHub commits](https://flat.badgen.net/github/commits/dgattey/saga)][gh] [![Last commit](https://flat.badgen.net/github/last-commit/dgattey/saga/main)][gh]

# Saga

A native Swift app (iOS, macOS) for keeping track of what I've read, watched, played, and experienced. The vision is a personal knowledge base with full editing capabilities, synced via Contentful.

## Setup

```bash
./run bootstrap
```

Bootstrap installs the Brewfile (1Password CLI, mise), installs the SwiftLint that `mise.toml` pins, and writes the gitignored `Config.xcconfig` with dev Contentful credentials from the `saga` 1Password vault. Without it, the app builds with placeholder credentials, which is what CI and releases use.

## App architecture

Saga follows an MVVM architecture with SwiftUI views:
- **Features/**: Domain-specific features (Books, Assets, Content)
  - Each feature contains Models, Views, ViewModels, and Services
- **Shared/**: Reusable components, extensions, and utilities
- **Services/**: Core services like persistence (Core Data) and syncing (Contentful)
- Navigation is managed via `NavigationHistory` with a home-based sidebar layout

## Development process

Saga is a plain SwiftPM package with no Xcode project, built with [DylKit](https://github.com/dgattey/dyl-kit)'s `devkit` and `release-kit`. App settings live in `DylApp.toml`: bundle ID, minimum OS, resources and icon to compile, dev credentials, and the release feed. Xcode must be installed and selected (`xcode-select`) for `momc` and `actool`, but you never open it.

```bash
./run dev build        # build/Saga Dev.app (bundle ID com.dylangattey.Saga.dev), ad-hoc signed
./run dev relaunch     # build and open it in the background
./run dev capture      # screenshot the main window into build/captures/
./run dev ios --run    # build/Saga-iOS.app on a headless simulator
./run ui               # iPhone and iPad screenshots of the main screens with fixture books
./run dev checks       # DylApp.toml, SwiftLint, dyl-lint and release checks
./run format           # swift-format with .swift-format (--check to lint only)
swift test             # unit tests
```

`DYLKIT_PATH=/path/to/dyl-kit` builds against a local DylKit checkout instead of its `main` branch.

### Adding new models

When adding a new Core Data model:
1. Create the entity in `Saga.xcdatamodeld`
2. Create the corresponding Swift model file
3. Add the model to `PersistenceModel` enum
4. Mark the class `@objc(EntityName)` so the unqualified `representedClassName` resolves

## Releases

Every merge to `main` that touches the app (`release.inputs` in `DylApp.toml`) releases it with `release-kit`: it plans the version from the latest `v*` tag and the PR's Release info checkbox, bundles and signs `Saga.app`, writes `Saga-<version>.zip` and a signed Sparkle `appcast.xml` with cumulative release notes, checks the result against the live release, pushes the `v<version>` tag, and deploys `saga.gattey.com` with the new feed and zip. Nothing is committed: the feed installed apps poll (`https://saga.gattey.com/appcast.xml`) only exists on the site. Every PR runs the same steps short of publishing.

Production site deploys only come from `release-kit` (Vercel's git deploys of `main` are off in `server/vercel.json`), because a deploy without the live appcast and zips would break updates. Site-only changes deploy through `.github/workflows/site.yml` (`./run release deploy`).

[gh]: https://github.com/dgattey/saga
