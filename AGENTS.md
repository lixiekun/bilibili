# Repository Guidelines

## Project Structure & Module Organization
- `bilibili/` holds all SwiftUI sources: `bilibiliApp.swift` wires the app entry, `ContentView.swift` orchestrates navigation, `RecommendationViewModel.swift` owns data fetching, `VideoItem.swift` models payloads, and `Assets.xcassets` stores shared art.
- `bilibiliTests/` contains module-scoped tests written with the `Testing` framework; mirror production file names (e.g., `ContentViewTests.swift`) when adding coverage.
- `Packages/` is reserved for Swift Package dependences; add reusable utilities here instead of polluting the app target.

## Build, Test, and Development Commands
- `open bilibili.xcodeproj` launches the project in Xcode for day-to-day SwiftUI and RealityKit work.
- `xcodebuild -scheme bilibili -destination 'platform=visionOS Simulator,name=Apple Vision Pro' build` performs a CI-friendly build.
- `xcodebuild -scheme bilibiliTests -destination 'platform=visionOS Simulator,name=Apple Vision Pro' test` runs the full test suite headlessly; prefer this in automation.
- Use `swift package resolve` whenever modifying `Packages/` to refresh lockfiles before committing.

## Coding Style & Naming Conventions
- Follow Swift 5.9 defaults: 4-space indentation, `UpperCamelCase` for types/protocols, `lowerCamelCase` for functions, properties, and test names.
- Keep view structs lightweight and extract reusable rows (see `VideoRow`) when a view exceeds ~80 lines.
- Annotate concurrency intent explicitly (`@MainActor`, `@StateObject`) and prefer async/await over completion handlers.
- Run Xcode's "Format File" or `swift-format` (if configured) before pushing; avoid trailing whitespace.

## Testing Guidelines
- Write scenario-focused tests using `@Test` functions; name them `<Unit>_<Condition>_<Expectation>` for clarity.
- Stub network responses for `RecommendationViewModel` by injecting `URLProtocol` fakes rather than hitting the live Bilibili API.
- Aim for meaningful coverage on parsing (e.g., `VideoItem` decoding) and UI state transitions (loading, error, success).

## Commit & Pull Request Guidelines
- Follow the existing history: short, present-tense summaries (`Add recommendation list layout`) with optional scope after a colon.
- Each PR should describe the problem, the solution, simulator targets validated, and reference any tracked issue.
- Attach screenshots or screen recordings for visual tweaks, and link to logs from `xcodebuild` for build-system changes.

## Security & Configuration Tips
- Never hardcode personal API tokens; keep `RecommendationViewModel` URLs configurable (e.g., plist entry or compiler flag).
- Scrub logs before commit—debug `print` statements dumping full JSON should stay behind `#if DEBUG` guards only.
