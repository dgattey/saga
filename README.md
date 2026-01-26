# Saga

A native Swift app (iOS, macOS) for keeping track of what I've read, watched, played, and experienced. The vision is a personal knowledge base with full editing capabilities, synced via Contentful.

## Setup

```bash
./run bootstrap   # first time (before shell function exists)
source ~/.zshrc   # activate completions
```

Bootstrap handles all one-time setup:

1. **Installs 1Password CLI** via Homebrew (if not present)
2. **Authenticates with 1Password** (prompts if needed)
3. **Writes `Saga/Config/Config.xcconfig`** with Contentful credentials from the `saga` vault (`CONTENTFUL_SPACE_ID` and `CONTENTFUL_ACCESS_TOKEN` items)
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
| `app` | Build and launch the app |
| `bootstrap` | Set up shell completions and pull secrets from 1Password |
| `drop-bot-commits` | Drop version bump commits on branch and rebase onto main |
| `checks` | Run Swift format and/or lint checks |
| `version-and-release` | Manage version tags and Github releases |

### Building and running

Builds the macOS app in Debug mode using `xcodebuild` and launches the resulting app, or you can use Xcode.

```bash
run app              # build quietly and launch
run app --verbose    # show full xcodebuild output
run app --help       # show usage
```

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
4. Ensure Xcode isn't generating auto-gen files for the entity

## Releases

GitHub Actions automatically bump versions on PRs and create releases on merge:

- PRs include release type checkboxes (Major/Minor/Patch, default Patch) and a `# What changed?` section for release notes
- On PR open/edit, the workflow reads the base version from `main`, computes the next version, sets the build number, and commits the bump
- On merge, it creates a GitHub Release using the `# What changed?` text as release notes

### Version conflicts

If there are multiple branches, each with their own version bump, then one merges, there will be a
conflict in `project.pbxproj`. To fix, `run drop-bot-commits` to remove bot-authored version bumps
and rebase onto `origin/main`. Force pushing the branch should then recreate a new version bump
commit and you're good.

### Manual management

Shouldn't be necessary, but you can `run version-and-release` for manual version management (see `--help` for subcommands).