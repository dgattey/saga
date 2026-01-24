# Saga

This is a work in progress app for syncing data to and from Contentful via a Sync API, to a native Swift app (iOS, macOS). Eventually will offer editing capabilities + be an app for keeping track of what I've read/seen/been to/etc.

To set up:
1. Create a `Config.xcconfig` file at the top level of the app, and DO NOT add to any targets
2. Configure under project -> configurations to use it for debug and release
3. Here are the contents, where you replace the values with real data:
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

## Release automation
This repo uses GitHub Actions to bump versions on PRs and create releases on merge.

### How it works
- PR template (`.github/pull_request_template.md`) includes:
  - `# What changed?` section for release notes
  - `# Release info` checkboxes (Major/Minor/Patch)
  - A release info block inserted between `<!-- release-metadata-start -->` and `<!-- release-metadata-end -->` after the first action run
- On PR open/edit/sync (`.github/workflows/pr-version-bump.yml`):
  - Reads the base version/build from `main` (so reruns are idempotent).
  - Determines release type from the PR checkboxes (default Patch).
  - Sets build number to `max(baseBuild + 1, PR updated_at epoch seconds)` so edits refresh it and it always increases.
  - Updates `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Saga/Saga.xcodeproj/project.pbxproj`.
  - Commits the bump into the PR branch and updates the metadata block in the PR body.
- On merge (`.github/workflows/release-on-merge.yml`):
  - Reads the version/build from the merged code.
  - Creates a GitHub Release tagged `vX.Y.Z`.
  - Uses only the text under `# What changed?` (up to `# Release type`) as the release notes.

### Script used by workflows
All parsing and updates are centralized in `scripts/versioning.swift`:
- `read` reads current version/build from the Xcode project.
- `bump` computes the next version/build and updates the project file.
- `pr-info` parses release type and PR updated timestamp from the GitHub event.
- `update-metadata` rewrites the PR body metadata block.
- `extract-notes` pulls the release notes from the PR body.

## Adding new models
Don't forget to add to `PersistenceModel` after adding a core data model + the model file (and ensure there aren't auto-gen files from the core model).

## TODO
- [] book layout + edit view
    - [] rating
    - [] editable review
    - [] editable dates
    - [] save changes locally
- [] figure out why The Color Purple, Transcendant Kingdom, Remembrance of Earth's Past, Chamber of Secrets, Deathly Hallows, Order of Phoenix, da vinci code, amulet of samarkand all didn't parse cover images right
- [] save local data to server
    - [] upload + create new cover images
    - [] upload + create new books
    - [] update existing books
- [] polish
    - [] trigger new sync call when window gets focus (or some other trigger to regularly get new data)
    - [] fix sort order after import (might be fixed by in-mempry sorting?)
    - [] fix content pane not getting cleared when resetting local data
- [] create new book screen

### Later
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

### Done
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
