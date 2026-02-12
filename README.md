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
3. **Writes `Saga/Config/Config.xcconfig`** with Contentful credentials from the `saga` vault: `CONTENTFUL_DELIVERY_API_KEY`, `CONTENTFUL_DELIVERY_PREVIEW_API_KEY`, `CONTENTFUL_MANAGEMENT_ACCESS_TOKEN`, `CONTENTFUL_SPACE_ID` (item names AS IS)
4. **Adds shell completions** to your `.zshrc` for the `run` command

After setup, use `run` (with tab completion) instead of `./run`. Re-run bootstrap any time to refresh credentials.

### Content Management Token

Two-way sync requires a Content Management API token. Bootstrap pulls it from the `saga` vault item `CONTENTFUL_MANAGEMENT_ACCESS_TOKEN`. Add that item (value = your CMA token from Contentful → Settings → API keys → Content management tokens) and re-run `run bootstrap` if needed.

**The app will crash at startup if this token is missing when two-way sync is used.**

## App architecture

Saga follows an MVVM architecture with SwiftUI views:
- **Features/**: Domain-specific features (Books, Assets, Content)
  - Each feature contains Models, Views, ViewModels, and Services
- **Shared/**: Reusable components, extensions, and utilities
- **Services/**: Core services like persistence (Core Data) and syncing (Contentful)
- Navigation is managed via `NavigationHistory` with a home-based sidebar layout

### Contentful Sync Architecture

Saga uses a bidirectional sync architecture with Contentful:

**Pull (Contentful → CoreData)**
- Uses [ContentfulPersistence.swift](https://github.com/contentful/contentful-persistence.swift) with delta sync tokens
- Only fetches changes since last sync (efficient)
- Automatically maps Contentful entries/assets to CoreData entities

**Push (CoreData → Contentful)** *(requires management token)*
- Uses the [Content Management API](https://www.contentful.com/developers/docs/references/content-management-api/)
- Automatically detects local CoreData changes via `NSManagedObjectContextDidSaveNotification`
- Debounces and batches changes for efficiency
- Uploads assets (images) with full lifecycle: upload → process → publish
- Uses "latest-wins" conflict resolution based on `updatedAt` timestamps

Saving to CoreData automatically triggers sync when two-way sync is enabled.

## Development process

### Scripts

Swift-based scripts live in `scripts/Sources/` and are run via the `run` wrapper at the repo root. Use `run --help` to see available scripts, or `run <script> --help` for script-specific options.

| Script | Description |
|--------|-------------|
| `app` | Build, launch, or run UI tests |
| `bootstrap` | Set up shell completions and pull secrets from 1Password |
| `drop-bot-commits` | Drop version bump commits on branch and rebase onto main |
| `checks` | Run Swift format and/or lint checks |
| `version-and-release` | Manage version tags and Github releases |

### Building and running

Builds the macOS app in Debug mode using `xcodebuild` and launches the resulting app, or you can use Xcode.

```bash
run app              # build quietly and launch
run app --verbose    # show full xcodebuild output
run app --ui-test    # run XCUITest UI tests + screenshots
run app --help       # show usage
```

### UI testing (macOS)

UI tests run with XCUITest via `xcodebuild test` (xctest runner) and export screenshots to
`build/UITestScreenshots/<branchHash>/`.

macOS requires granting Accessibility and Screen Recording permissions to the test runner
(Xcode or `xcodebuild`). These permissions cannot be limited to a single target app, but the
tests only interact with Saga and capture Saga's window content.

### Hot Reload (Development)

Hot reload is enabled via the [Inject](https://github.com/krzysztofzablocki/Inject) library. To use it:

1. **Install InjectionIII** from the [Mac App Store](https://apps.apple.com/us/app/injectioniii/id1380446739) or build from [source](https://github.com/johnno1962/InjectionIII)
2. **Run the app** in Xcode (Debug build)
3. **Launch InjectionIII** and select the Saga project folder when prompted
4. **Edit any Swift file** and save - the UI will automatically refresh

Hot reload is applied universally via `.hotReloadable()` at the WindowGroup level, so all views automatically get hot reload support without individual modifications. No per-view setup required.

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

[gh]: https://github.com/dgattey/saga
