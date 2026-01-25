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
| `format` | Format and lint all Swift files |
| `version-and-release` | Manage version tags and Github releases |

### Building and running

Builds Saga in Debug mode using `xcodebuild` and launches the resulting app, or you can use Xcode.

```bash
run app              # build quietly and launch
run app --verbose    # show full xcodebuild output
run app --help       # show usage
```

### Formatting and linting

All Swift code is formatted and linted using `swift-format` with the repo config in `.swift-format`.

```bash
run format           # format in place, then lint
run format --help    # show usage
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

## TODO

Syncing data from Contentful to local Core Data storage with read-only views. Editing and two-way sync are in progress.

- [] book layout + edit view
    - [] rating
    - [] editable review
    - [] editable dates
    - [] save changes locally
- [] save local data to server
    - [] upload + create new cover images
    - [] upload + create new books
    - [] update existing books
- [] polish
    - [] trigger new sync call when window gets focus (or some other trigger to regularly get new data)
- [] create new book screen
- [] save scroll position on history

<details>
<summary><b>Later</b></summary>

- [] supporting video games, movies, tv shows
- [] supporting a "what do I watch/play/read" feature
- [] supporting restaurants, trips, live shows
- [] logging how I've spent my time per month (reorg of data)
- [] arbitrary lists
- [] shareable lists (create a deep link to my website?)
- [] search improvements
    - [] cmd-k
    - [] add tags for ratings
    - [] add tags for has review
    - [] add tags for read status
    - [] move to Contentful-side search?
    - [] explore better solutions for search tokens/scope than built in
    - [] highlight title/author hits as you type

</details>

<details>
<summary><b>Done</b></summary>

- [x] connection to Contentful + sync persistence
- [x] local persistence with Core Data
- [x] full data reset via settings
- [x] cache cover images
- [x] render rich text as attributed string
- [x] parse GoodReads CSV upload locally
    - [x] dropzone with determinate progress
    - [x] CSV file parsing
    - [x] fetching cover images
    - [x] better merge new data (ISBN) with dupes
    - [x] fetch isbn where missing
- [x] navigation back and forth
- [x] fix content pane not getting cleared when resetting local data
- [x] fix sort order after import (might be fixed by in-mempry sorting?)
- [x] improve image parsing code to get best images
- [x] add control over image caching + better downsampling

</details>
