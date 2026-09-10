# AirCanvas Portfolio Capture Plan

Capture real content on a supported portrait iPhone in an evenly lit, textured room. Camera/AR images should come from the physical device, never the Simulator. Use a clean canvas name and real user-created strokes; do not include debug overlays, private filenames, or unrelated notifications.

## Visual story

**Problem → Interaction → Engineering → Reliability → Accessibility → Result**

The finished portfolio should show more than screenshots: it should explain why spatial hand input has a touch fallback, how a real pipeline becomes persistent artwork, and how the product handles failure/recovery safely.

## Required captures

| # | Capture | What must be visible | Story purpose |
|---|---|---|---|
| 1 | My Canvases | A clean library, create action, meaningful canvas names/metadata | Problem / organization |
| 2 | First-run onboarding | Welcome and camera education before the system prompt | Clear first-launch intent |
| 3 | AR readiness | The live camera with material-backed mapping guidance | Honest spatial preparation |
| 4 | Hand cursor | Real fingertip cursor over the physical scene | Hand tracking + raycast |
| 5 | Pinch drawing clip | Pinch, short movement, release, and the real resulting stroke | Interaction |
| 6 | Finished spatial artwork | Two or more spatial strokes at visible depth | Result |
| 7 | Selected stroke | Textual selected state plus visible selection feedback | Editing clarity |
| 8 | Move clip | A hand or touch move preview followed by release | Stable translation |
| 9 | Scale control | Selected stroke with the accessible Scale slider/value | Accessible transform |
| 10 | Rotation control | Selected stroke with the accessible Rotate slider/value | Accessible transform |
| 11 | Erase/Delete and Undo | Candidate or selected delete, followed by Undo restoration | Destructive-action safety |
| 12 | Touch alternative | A real touch-drawn or touch-moved stroke | Inclusive fallback |
| 13 | Persistence | Leave/reopen the canvas with the same real artwork | Reliability |
| 14 | Export/import | `.aircanvas` share/export and the imported result in My Canvases | Portability |
| 15 | Accessibility | Large Dynamic Type or VoiceOver-focused controls in a normal product screen | Inclusive UX |
| 16 | Architecture/code | The pipeline diagram or concise relevant source view, with no secrets | Engineering judgment |

## Suggested video sequence

1. **0–10 seconds:** My Canvases and the product purpose.
2. **10–35 seconds:** cursor → pinch → one spatial stroke.
3. **35–60 seconds:** Select → Move → Scale → Rotate.
4. **60–80 seconds:** Erase/Delete → Undo.
5. **80–100 seconds:** leave/reopen and export/import.
6. **100–120 seconds:** touch fallback and the architecture/privacy conclusion.

## Capture quality checklist

- Use portrait framing and hide personal notifications.
- Keep text readable; camera-overlay instructions must remain legible against the live scene.
- Show actual app state transitions, not stills presented as interactions.
- For hand clips, use slow, deliberate movements and show release where a commit matters.
- For fallback clips, use real touch controls; never simulate successful hand tracking.
- Use one polished prepared canvas, but state that it is ordinary local user content.
- Capture Light and Dark Mode separately only when each supports a distinct portfolio point.

## Portfolio narrative prompts

- **Problem:** How can spatial drawing stay practical when hand tracking is unavailable or unwanted?
- **Interaction:** How does a confirmed pinch become a committed Stroke?
- **Engineering:** Why do AR, Vision, rendering, and the persistence model have separate ownership?
- **Reliability:** What prevents stale Vision results, duplicate interactions, data loss, or destructive hover behavior?
- **Accessibility:** What can a touch-only or VoiceOver user do instead?
- **Result:** What survives reopening, export/import, and an ordinary editing session?

## Apple Developer Academy positioning

Use the capture set to discuss Apple-native development, human-computer interaction, computer vision, spatial interaction, accessibility, privacy-aware local processing, testing, and performance engineering. Keep claims factual: AirCanvas is a local-device project; TestFlight/App Store distribution remains intentionally deferred until paid-program enrollment.
