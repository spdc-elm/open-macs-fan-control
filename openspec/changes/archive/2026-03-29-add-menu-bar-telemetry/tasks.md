## 1. Shared telemetry runtime

- [x] 1.1 Land the shared-runtime extraction from `extract-shared-runtime-core` so the menu bar work targets the new module boundary
- [x] 1.2 Extract a structured telemetry snapshot API from the shared temperature and fan runtime paths
- [x] 1.3 Include aggregate CPU average, aggregate GPU average, fan RPM summaries, and explicit unavailable/stale state in the snapshot model
- [x] 1.4 Update existing CLI probe code to consume the shared snapshot path without changing current terminal behavior

## 2. Menu bar app surface

- [x] 2.1 Add a dedicated macOS menu bar app entrypoint that uses `MenuBarExtra`
- [x] 2.2 Implement the compact menu bar label for CPU average, GPU average, and fan RPM summary values
- [x] 2.3 Implement the expanded menu bar panel with detailed values, unavailable-state messaging, refresh context, and a quit action
- [x] 2.4 Add timer-driven refresh wiring so the menu bar UI updates automatically from the shared telemetry snapshot layer

## 3. Packaging and validation

- [x] 3.1 Choose the post-refactor app host path (for example SwiftPM bundling or Xcode app target) that best fits the shared runtime structure
- [x] 3.2 Add the app-bundle packaging assets and `Info.plist` configuration needed for a menu bar-only app (`LSUIElement`)
- [x] 3.3 Add a repeatable local build/package command that produces a runnable `.app` alongside the existing CLI build
- [x] 3.4 Validate that the CLI still works unchanged and that the menu bar app launches, refreshes telemetry, and handles missing signals gracefully on supported hardware
- [x] 3.5 Document how to build and run the menu bar app for local development
