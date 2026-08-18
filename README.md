# FiveNet Mobile

FiveNet Mobile is an iPadOS client built with SwiftUI for **FiveNet** roleplay servers.
The app connects to FiveNet instances over gRPC-Web and provides access to the citizen and vehicle database, LiveMap, dispatch center, wiki, documents, jobs, qualifications, calendar, mail, and other modules.

> **Notice:** FiveNet Mobile is a **community project** in the `fivenet-app` organization and is **not directly supported by the FiveNet team**. See [Brand Notice](#brand-notice) and `NOTICE` for details.

## Features

- **Overview** - module grid, profile hero, quick access; alternatively **compact view** ("efficiency layout") with your unit, your assignment, open assignments, and module tiles; the quick access row is **editable** (reorder, add/remove modules and tab targets, persisted per server)
- **Screensaver** - optional animated screensaver that engages after a configurable idle delay; enable/disable and the delay are configurable in the system settings (`Settings.bundle`), and any interaction dismisses it
- **Citizens / Vehicles** - searchable databases with pagination, WANTED badges, and detail views; the citizen profile has a **hiring check** tab ("Einstellungsprüfung") that bundles a citizen's police relevance: wanted status, open fines, points, jail history, wanted vehicles and linked documents (configurable via system settings)
- **LiveMap** - map with unit and incident markers, incident heatmap layer, "My Unit" view, join and leave unit, **long-press on the map to create an incident at the pressed location**, unit badges with outline rings, tile **disk caching**
- **Dispatch** - create and take incidents, incident timeline, units, activity, archive, duty unit; join/take actions are gated on being **on duty**
- **Wiki** - pages with table of contents, pins, live search, rich content (Tiptap / HTML); **readable tables** that fill the content width with proportional columns, zebra striping and clearly visible separators
- **Documents** - search, categories, status segments, actions for close, approve, request, reminder, and delete, plus a block-based **inline content editor** that preserves existing non-Tiptap content
- **Jobs** - overview, colleagues with labels, activity, time clock, leadership register, vacation; **colleague statistics** tab with a count-over-time chart (requires FiveNet v2026.8.1); **job groups** (v2026.8.1) with members, rules, manual members, leaders, exclusions and group activity
- **Qualifications** - your own and all qualifications, detail view with content and tutor, request handling and grading
- **Calendar** - month view with vacations and FiveNet calendars, date jump, create appointment
- **Mail** - inbox and archive, search, thread detail, compose and reply
- **Settings** - job props, roles and permissions, audit log, Discord, dispatch, law books, storage, accounts, config, cron
- **Alarm** - red full-screen alarm on incident assignment plus reinforcement alarm ("Verstärkung benötigt" for all units except the requester) with a live alarm bell
- **Global Search** - cross-module search across citizens, vehicles, incidents, documents, and wiki
- **Reliability** - fast connection establishment (~2 s) with automatic reconnect, transient stream errors suppressed, offline-aware connectivity, and a viewed-content cache for previously opened wiki/document content
- **Design system** - consistent card layout, heroes, badges, tab selectors and spacing across all modules

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

- [@PhilTec-Philip](https://github.com/PhilTec-Philip) for creating and developing the community project.
- The FiveNet team and Alexander Trost for the excellent open-source system that made this app possible.
- Apple and the Swift Protobuf authors for the Protobuf runtime and clients.
