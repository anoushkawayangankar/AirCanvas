# AirCanvas Product Specification

## Purpose

AirCanvas is a production-quality iOS spatial drawing application. It lets people create, edit, save, reopen, and share drawings composed in three-dimensional space. The product must be suitable for iterative TestFlight distribution and eventual App Store submission.

## Supported interaction modes

The app provides equivalent access to essential drawing and project-management functions through accessible touch controls. Hand tracking enhances input when hardware, permissions, and tracking conditions allow; it is never the sole path to essential functionality.

### Touch drawing

Users can draw in an AR scene with touch input, change brush color and thickness, select strokes, delete strokes, undo and redo actions, and save their work.

### Hand drawing

When camera access and hand tracking are available, the app displays a cursor mapped to the tracked fingertip. A pinch begins a stroke and releasing the pinch ends it. Missing landmarks, low-confidence results, or tracking loss must end or pause drawing safely and leave touch controls available.

## Primary user flow

1. The user launches AirCanvas and completes onboarding.
2. The app clearly requests camera permission before AR or hand tracking is used.
3. The user creates a canvas from the project library.
4. The app enters the AR drawing environment when supported and available.
5. The user draws with touch, and later may use fingertip/pinch input.
6. The user adjusts brush settings, selects or deletes strokes, and uses undo or redo.
7. The app autosaves and supports an explicit save path.
8. The user returns to the library and reopens saved canvases.
9. The app attempts to restore each canvas in its prior spatial context; when precise restoration is unavailable it communicates this gracefully and preserves the saved drawing data.
10. The user exports or shares a visual representation of a canvas.

## Functional requirements

- Onboarding explains the app’s AR and camera needs before asking for permission.
- Permission state is observable and recoverable when access changes in Settings.
- New canvases have durable project metadata and a stable identifier.
- AR session, tracking, camera, Vision, persistence, and lifecycle failures produce actionable user-facing state and structured logs.
- Strokes retain sufficient geometry and style data to render, edit, serialize, restore, and export them.
- Rendering must avoid creating one RealityKit entity per sampled point or other unbounded entity growth.
- Drawing samples are throttled, smoothed, and filtered according to configurable drawing-engine rules.
- Hand-pose processing occurs off the main thread, is cancellable, and avoids processing every camera frame unnecessarily.
- Gesture recognition is independent from drawing and rendering concerns.
- Project data is saved outside UserDefaults, with corruption and interrupted-write handling.
- Autosave responds safely to edits, backgrounding, and scene lifecycle changes.
- Essential controls have accessible labels, values, traits, and touch-operable alternatives.

## Quality requirements

- Native implementation preference: Swift, SwiftUI, ARKit, RealityKit, Vision, SwiftData where appropriate, Codable, OSLog, XCTest, and XCUITest.
- No external dependency is added without a documented technical rationale.
- Significant business logic does not live in SwiftUI views.
- Core non-UI logic is independently unit-testable.
- The app supports cancellation, memory awareness, thermal constraints, and reduced-capability devices.

## Out of scope for the first foundation milestone

- Implementing AR drawing, hand tracking, persistence, export, or UI flows.
- Committing to a minimum iOS deployment target before the Xcode project and device support requirements are established.
- Claiming reliable spatial relocalization across all environments; restoration behavior will be designed and validated in its dedicated milestone.
