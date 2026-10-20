[![GitHub version](https://flat.badgen.net/github/release/dgattey/saga?cache=200)][gh] [![GitHub commits](https://flat.badgen.net/github/commits/dgattey/saga)][gh] [![Last commit](https://flat.badgen.net/github/last-commit/dgattey/saga/main)][gh]

# Saga

A native Swift app (iOS, macOS) for keeping track of what I've read, watched, played, and experienced. The vision is a personal knowledge base with full editing capabilities, synced via Contentful.

## Setup

```bash
./run bootstrap   # first time (before shell function exists)
source ~/.zshrc   # activate completions
```

Bootstrap handles all one-time setup:

1. **Installs Brewfile dependencies** (`brew bundle`: 1Password CLI, swift-format)
2. **Authenticates with 1Password** (prompts if needed)
3. **Writes `Config.xcconfig`** with Contentful credentials from the `saga` vault (`CONTENTFUL_SPACE_ID` and `CONTENTFUL_ACCESS_TOKEN` items)
4. **Adds shell completions** to your `.zshrc` for the `run` command

After setup, use `run` (with tab completion) instead of `./run`. Re-run bootstrap any time to refresh credentials.

## App architecture

Saga follows an MVVM architecture with SwiftUI views:
- **Features/**: Domain-specific features (Books, Assets, Content)
  - Each feature contains Models, Views, ViewModels, and Services
- **Shared/**: Reusable components, extensions, and utilities
- **Services/**: Core services like persistence (Core Data) and syncing (Contentful)
- Navigation is managed via `NavigationHistory` with a home-based sidebar layout

## Development process

### Scripts

Swift-based scripts live in `scripts/Sources/` and are run via the `run` wrapper at the repo root. Use `run --help` to see available scripts, or `run <script> --help` for script-specific options.

| Script | Description |
|--------|-------------|
| `app` | Build, launch, or run unit tests |
| `bootstrap` | Set up shell completions and pull secrets from 1Password |
| `config` | Write `Config.xcconfig` from the environment |
| `checks` | Run Swift format and/or lint checks |
| `clean` | Remove build artifacts and SwiftPM build caches |
| `version-and-release` | Manage version tags and Github releases |

### Building and running

Saga is a plain SwiftPM package (`Package.swift` at the repo root); there is no Xcode project.
`scripts/build-macos.sh` runs `swift build`, compiles `Saga.xcdatamodeld` (`momc`) and the asset
catalogs (`actool`), embeds Sparkle, writes `Info.plist`, and ad-hoc signs `build/Saga.app`.
`momc` and `actool` ship with Xcode, so Xcode must be installed and selected (`xcode-select`),
but you never open it.

```bash
run app              # build build/Saga.app (debug) and launch it in the background
run app -b           # build only
run app -r           # release configuration
run app -t           # swift test
run app --help       # show usage
scripts/build-ios-sim.sh [--install]   # build/Saga-iOS.app for the iOS Simulator
```

Build settings live where SwiftPM and the scripts can read them: bundle ID and minimum OS in
`scripts/lib/app-config.sh`, the marketing version in `VERSION`, entitlements in
`Saga.entitlements`, and the Sparkle public key in `sparkle-public-key.txt`.

### Formatting and linting

All Swift code is formatted and linted using `swift-format` with the repo config in `.swift-format`.

```bash
run checks           # format and lint
run checks --format  # format only
run checks --lint    # lint only
run checks --help    # show usage
```

CI runs this on every PR and fails if formatting produces any changes.

### Adding new models

When adding a new Core Data model:
1. Create the entity in `Saga.xcdatamodeld`
2. Create the corresponding Swift model file
3. Add the model to `PersistenceModel` enum
4. Mark the class `@objc(EntityName)` so the unqualified `representedClassName` resolves

## Releases

GitHub Actions automatically compute versions and create releases when PRs merge to `main`:

- PRs include release type checkboxes (Major/Minor/Patch, default Patch) and a `# What changed?` section for release notes
- CI checks run in parallel on PR branches without pushing version bump commits to the branch, avoiding version-file merge conflicts across open PRs
- On merge, `release.yml` computes the next semantic version and Sparkle build number from the latest release tag and PR release type, packages and signs the macOS app, checks it is a valid Sparkle update for the latest published release (`scripts/verify-release.sh`, also run on every PR), updates `appcast.xml` with cumulative versioned release notes (capped at the last 10 versions via `scripts/release-notes.sh` and `scripts/generate-appcast.sh`), and publishes a GitHub Release using the `# What changed?` text as release notes

### Manual management

Shouldn't be necessary, but you can `run version-and-release` for manual version management (see `--help` for subcommands).

[gh]: https://github.com/dgattey/saga
