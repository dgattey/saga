# Saga

A native Swift app (iOS, macOS) for keeping track of what I've read, watched, played, and experienced. The vision is a personal knowledge base with full editing capabilities, synced via Contentful.

## Setup

Two manual steps, both one-time setup:

<details>
<summary>Shell completions</summary>

Sets up shell completions in your `.zshrc` for the `run` command. Run once per machine.

```bash
./run bootstrap   # first time (before shell function exists)
source ~/.zshrc   # activate completions
```

After setup, you can use `run` (with tab completion) instead of `./run`.

</details>

<details>
<summary>Secret configuration</summary>

Create a `Config.xcconfig` file at the top level of the app:

1. Create the file (DO NOT add to any Xcode targets)
2. Configure under project → configurations to use it for debug and release
3. Add these contents, replacing values with real data:

```
//
//  Config.xcconfig
//  Saga
//
//  Created by Dylan Gattey on 7/6/25.
//

// Configuration settings file format documentation can be found at:
// https://developer.apple.com/documentation/xcode/adding-a-build-configuration-file-to-your-project

CONTENTFUL_SPACE_ID = your_space_id
CONTENTFUL_ACCESS_TOKEN = your_access_token
```

</details>

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
| `bootstrap` | Set up shell completions for run |
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