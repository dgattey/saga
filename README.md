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

## Adding new models
Don't forget to add to `PersistenceModel` after adding a core data model + the model file (and ensure there aren't auto-gen files from the core model).

## TODO
- [x] Connection to Contentful + sync persistence
- [x] Local persistence with Core Data
- [] full data reset via settings
- [] reading more information about books like rich text
- [] move search into sidebar
- [] allow creating data
- [] supporting video games, movies, tv shows
- [] supporting a "what do I watch/play/read" feature

### Later
- [] supporting restaurants, trips, live shows
- [] logging how I've spent my time per month (reorg of data)
- [] arbitrary lists
- [] shareable lists (create a deep link to my website?)

