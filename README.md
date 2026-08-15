# FiveNet Mobile

FiveNet Mobile is an iPadOS client built with SwiftUI for **FiveNet** roleplay servers.
The app connects to FiveNet instances over gRPC-Web and provides access to the citizen and vehicle database, LiveMap, dispatch center, wiki, documents, jobs, qualifications, calendar, mail, and other modules.

> **Notice:** FiveNet Mobile is a **community project** in the `fivenet-app` organization and is **not directly supported by the FiveNet team**. See [Brand Notice](#brand-notice) and `NOTICE` for details.

## Features

- **Overview** - module grid, profile hero, quick access; alternatively **compact view** ("efficiency layout") with your unit, your assignment, open assignments, and module tiles
- **Citizens / Vehicles** - searchable databases with pagination, WANTED badges, and detail views
- **LiveMap** - map with unit and incident markers, incident heatmap, "My Unit" view, join and leave unit
- **Dispatch** - create and take incidents, incident timeline, units, activity, archive, duty unit
- **Wiki** - pages with table of contents, pins, live search, rich content (Tiptap / HTML)
- **Documents** - search, categories, status segments, actions for close, approve, request, reminder, and delete, plus content editor
- **Jobs** - overview, colleagues with labels, activity, time clock, leadership register, vacation
- **Qualifications** - your own and all qualifications, detail view with content and tutor, request handling and grading
- **Calendar** - month view with vacations and FiveNet calendars, date jump, create appointment
- **Mail** - inbox and archive, search, thread detail, compose and reply
- **Settings** - job props, roles and permissions, audit log, Discord, dispatch, law books, storage, accounts, config, cron
- **Alarm** - red full-screen alarm on incident assignment plus reinforcement alarm
- **Global Search** - cross-module search across citizens, vehicles, incidents, documents, and wiki
- **Live alarm bell**, offline-aware connectivity, map design system

## Compatibility

- Target platform: iOS 26.5+ (SwiftUI, pure Swift, no storyboards)
- Server: FiveNet (https://github.com/fivenet-app/fivenet), self-hosted, or the official demo instance `demo.fivenet.app`

## Build

```sh
xcodebuild -project "FiveNetMobile.xcodeproj" -scheme "FiveNet Mobile" \
  -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/dd build
```

New Swift files are picked up automatically
(`PBXFileSystemSynchronizedRootGroup`, Xcode 16) - just place them under `FiveNet Mobile/UI/`.

## Project Structure

- `FiveNet Mobile/UI/` - SwiftUI views
- `FiveNet Mobile/Generated/Core/` - AppState, gRPC client, error translation
- `FiveNet Mobile/Generated/Protobuf/` - generated Swift Protobuf bindings
  (from the FiveNet proto definitions via `Scripts/generate-protos.sh`)

## Brand Notice

- FiveNet Mobile is a community project in the `fivenet-app` organization.
- It is not an official FiveNet product and is not directly supported by the FiveNet team.
- The name "FiveNet" is used only descriptively to indicate compatibility and functionality.

## License

Code is licensed under the Apache 2.0 license; see [LICENSE](LICENSE).

Licenses of used libraries, code and media can be found in the [`public/licenses/` folder](public/licenses/).

## Acknowledgements

- The FiveNet team and Alexander Trost for the excellent open-source system that made this app possible.
- Apple and the Swift Protobuf authors for the Protobuf runtime and clients.
