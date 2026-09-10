# AirCanvas Release Readiness

Operational checklist for the first TestFlight beta. Status reflects the deferred-distribution finalization on 2026-09-02; it does not claim App Store Connect actions that were not performed locally.

## Deferred distribution status

### Complete now

- Production AppIcon asset catalog and target assignment: **COMPLETE**.
- Development signing, connected-iPhone deployment, Release configuration, privacy/configuration, DEBUG exclusion, document-type audit, and regression tests: **COMPLETE**.

### Deferred until paid Apple Developer Program enrollment

- Apple Distribution signing, distribution-signed archive, App Store Connect, TestFlight, public-store metadata, validation, upload, and post-upload TestFlight validation: **DEFERRED BY USER**.
- This is an intentional distribution decision. It is not a source-code, AppIcon, privacy, Release-configuration, or development-device blocker.

### Future resume procedure

1. In Xcode, open **Settings → Accounts** and confirm the paid Apple Developer Program team.
2. Select the AirCanvas target → **Signing & Capabilities** → select the paid team.
3. Use **Product → Archive**.
4. In Organizer, inspect and validate the Apple Distribution-signed archive.
5. Upload through App Store Connect.
6. Run the preserved TestFlight fresh-install and upgrade smoke tests after Apple processing completes.

## Local product QA and portfolio/demo readiness — AUTOMATED PHASE COMPLETE

- Milestone 32 audits the complete normal product journey, including onboarding, canvas management, drawing/editing, history, persistence, portability, lifecycle, accessibility, performance-policy safeguards, error states, terminology, and user-visible development artifacts.
- Focused Canvas/error-presentation coverage and the full 177-test Simulator regression suite passed. Current Debug generic iOS Simulator and unsigned Release generic iOS-device builds passed.
- The final physical-device QA remains **REQUIRED**. It must use the current Personal-Team development build and normal app workflows; it does not require Apple Distribution signing, TestFlight, or App Store Connect.
- `README.md`, `DEMO_SCRIPT.md`, and `PORTFOLIO_CAPTURE_PLAN.md` are the portfolio/demo operating materials. They describe real inputs and a real touch fallback, never fake tracking, fake strokes, or a hidden demo reset.

## 1. Product identity — PASS

- Display name: `AirCanvas`.
- Product name: `AirCanvas`.

## 2. Version and build — PASS

- Marketing version: `0.1.0`.
- Build number: `1`.
- Keep the marketing version until the product owner elects a new user-facing version. Increment `CURRENT_PROJECT_VERSION` for every TestFlight upload, including rebuilds of the same marketing version.

## 3. Bundle identifier — PASS, OWNER CONFIRMATION REQUIRED

- `com.anoushkawayangankar.AirCanvas` is a stable reverse-DNS identifier and is consistent in Debug and Release.
- Confirm that this App ID belongs to the intended Apple Developer team and exists in App Store Connect before upload.

## 4. Deployment target — PASS

- Minimum iOS version: 17.0.

## 5. Supported devices — PASS

- Distribution target: iPhone only.
- Simulator builds support automated non-spatial checks only; Simulator is intentionally unsupported for live spatial drawing.

## 6. Orientations — PASS

- Portrait only. This matches the validated AR/editor layout.

## 7. Development signing — PASS; Apple Distribution — DEFERRED BY USER

- Project signing style is Automatic and the configured team is `9UC82C3P9G`.
- Development signing uses the user’s Personal Team and Apple Development certificate/profile; connected-iPhone development deployment is confirmed.
- Apple Distribution signing requires paid Apple Developer Program enrollment and is **DEFERRED BY USER**. Do not treat this as a product-code failure.

## 8. Capabilities — PASS

- No app capabilities are enabled in the project configuration.
- Camera access is controlled by its privacy usage description and does not require an entitlement.
- No background modes are declared.

## 9. Entitlements — NOT APPLICABLE

- The project has no entitlements file and no enabled capability entitlement.

## 10. Info.plist permissions — PASS

- `NSCameraUsageDescription`: “AirCanvas uses the camera to track your hand and place drawings in your surroundings.”
- No unused microphone, photos, location, contacts, Bluetooth, motion, or speech permission description is declared.

## 11. Privacy manifest — PASS

- `AirCanvas/Resources/PrivacyInfo.xcprivacy` is included in the application target and was present in the archive.
- It declares no tracking, no tracking domains, and no collected-data types.
- Required-reason declarations cover app-local `UserDefaults` onboarding state (`CA92.1`) and elapsed-time measurement using system uptime (`35F9.1`).

## 12. Data-flow and privacy summary — PASS, OWNER REVIEW REQUIRED

- AR camera frames are consumed on-device by ARKit and Vision for hand tracking; they are not stored as AirCanvas content and source audit found no upload path.
- Hand-pose and spatial-fingertip state is transient and not persisted.
- User-created canvas names, strokes, and optional spatial-map metadata are stored locally in the app sandbox. Exports occur only through an explicit user-initiated share/export action.
- Source audit found no account, advertising, analytics, crash-reporting, cloud, or network SDK.
- The App Store Connect App Privacy questionnaire still requires the product owner’s legal/product confirmation before submission.

## 13. Third-party dependencies — PASS

- No third-party runtime packages or SDKs are configured. Runtime dependencies are Apple system frameworks only.

## 14. Debug-code audit — PASS

- Debug-only profiling and UI-test launch state are gated by `#if DEBUG`.
- Release does not define `DEBUG`; test mocks, previews, and deterministic stress fixtures are not normal user content or Release UI.

## 15. Logging audit — PASS

- Sparse `OSLog` categories remain for production diagnostics.
- DEBUG-only signposts and performance metrics are excluded from Release behavior.
- Dynamic error descriptions are logged with private hashed privacy interpolation; no canvas payload, camera frame, hand landmark, coordinate stream, or file content is logged as public diagnostics.

## 16. App icon and assets — PASS

- `AirCanvas/Assets.xcassets` and `AppIcon.appiconset` exist.
- Debug and Release explicitly assign `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.
- The 1024×1024 iOS AppIcon source compiled successfully in a generic Release iOS-device build.

## 17. `.aircanvas` document type — PASS

- Exported type identifier: `com.aircanvas.document`.
- Extension: `.aircanvas`.
- Info.plist declares the app as an Editor for this exported `public.data`-conforming type.
- Schema version is `1`; malformed and future unsupported versions are rejected with user-facing errors.

## 18. Release tests — PASS

- Milestone 31B full current simulator suite: 174 passed, 0 failed, 0 skipped.
- Includes persistence, import/export, onboarding, accessibility, lifecycle, performance policy, editing, history, and UI navigation coverage.

## 19. Release builds — PASS

- Release Simulator build passed with signing disabled.
- Release generic iOS device build passed with signing disabled.
- Milestone 31B generic iOS Release build also passed with signing enabled; its certificate class is Apple Development, not Apple Distribution.

## 20. Archive — DEFERRED BY USER

- A prior structural archive used Apple Development signing. Distribution archive creation and Organizer validation are intentionally deferred until paid-program enrollment.

## 21. Signed archive — DEFERRED BY USER

- Development-signed device builds are available now. Apple Distribution signing is intentionally deferred and will be resumed through the procedure above.

## 22. App Store Connect prerequisites — DEFERRED BY USER

- Create or confirm the App Store Connect app record for `com.anoushkawayangankar.AirCanvas`.
- Confirm the app record’s name, primary language, SKU, bundle ID, team access, tax/banking agreements as applicable, and export-compliance workflow.

## 23. Privacy policy — DEFERRED BY USER

- No privacy-policy URL is present in the project or supplied release materials.
- Publish an accurate policy and provide its public HTTPS URL in App Store Connect. This checklist is a technical audit, not legal advice.

## 24. Support URL — DEFERRED BY USER

- No support URL is present in the project or supplied release materials.
- Provide an accessible public support/contact URL for the App Store record.

## 25. App Privacy answers — PREPARED, DEFERRED BY USER

- Technical source audit indicates no data collection/transmission, identity linking, or tracking by AirCanvas.
- Camera frames, transient hand data, and local drawing data remain on device according to the audited code path.
- The product owner must confirm these statements and complete App Store Connect’s current questionnaire, including any Apple platform/service behavior outside this source audit.

## 26. Metadata — DEFERRED BY USER

- Prepare App Name, subtitle, description, keywords, primary category, age-rating responses, copyright, optional promotional text, support URL, privacy-policy URL, and review notes.

## 27. Screenshots — DEFERRED BY USER

- Capture portrait iPhone screenshots from a production-capable device: My Canvases, spatial hand drawing, selected-stroke transform controls, erase/editing, and first-run onboarding where useful.
- Do not use Simulator AR screens to represent spatial interaction.

## 28. Review notes — PREPARED

- Suggested technical review note: “AirCanvas uses the camera only to place drawings in the user’s surroundings and track one hand locally. On a supported iPhone, grant camera access, move the phone slowly until tracking is ready, hold one hand in view, then pinch and move to draw. No account or external credentials are required. Non-spatial canvas management and touch controls remain available when spatial drawing is unavailable.”

## 29. TestFlight What to Test and install smoke test — DEFERRED BY USER

### What to Test

- Onboarding, camera permission, AR readiness, hand detection, fingertip cursor, and pinch verification.
- Hand Draw, touch Draw, Select, Move, Scale, Rotate, Erase, Delete, and Undo/Redo.
- Canvas persistence, import/export, accessibility controls, and background/foreground recovery.

1. Install the TestFlight build fresh on a supported iPhone.
2. Complete Welcome, permission education, camera authorization, AR readiness, hand check, pinch check, and first real stroke.
3. Leave and reopen the first canvas; verify autosave and the tutorial stroke.
4. Verify Draw, touch Draw, Select/Move, Scale, Rotate, Erase, Delete, Undo/Redo, canvas switching, export/share, and import.
5. Deny and restore camera permission in Settings; verify safe recovery.
6. For an upgrade build, install over the prior TestFlight build and verify existing canvases, revisions, and exports remain intact.

## 30. Deferred distribution work

### No current development-device technical blockers

- Production AppIcon, development signing, connected-device deployment, Release configuration, privacy audit, document type, and regression suite are complete.

### Deferred until paid-program enrollment

1. Apple Distribution signing and distribution-signed archive.
2. App Store Connect record, validation, upload, privacy/support URLs, metadata, screenshots, and beta details.
3. TestFlight processing and post-upload install smoke tests.

These are **DEFERRED BY USER**, not current codebase failures. No product feature, drawing, AR, Vision, onboarding, accessibility, persistence, performance, AppIcon, or development-device behavior is blocked by this release-engineering audit.
