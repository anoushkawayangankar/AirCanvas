# AirCanvas Live Demo Script

This is a 2–3 minute demonstration of the real application. Do not enable a fake demo mode, fake hand tracking, or synthetic strokes.

## Before the demo

1. Use a supported iPhone in portrait with a clean camera lens, adequate even light, and a visible textured surface.
2. Open a normal saved canvas that already contains two or three real strokes, or create the content using the ordinary app controls before the audience arrives.
3. Confirm camera permission, normal AR tracking, and a stable hand cursor. Keep the prepared demo canvas local; no seeded content is bundled with AirCanvas.
4. If a fresh-onboarding demo is planned, delete the app and install a normal development build beforehand. Complete no stages in advance.

## 0:00–0:20 — Problem and concept

“Most drawing apps are flat. AirCanvas lets you place and edit strokes in the space around you, while keeping familiar touch controls available for every essential edit.”

Show **My Canvases** briefly, then open the prepared canvas.

## 0:20–0:45 — Enter the spatial canvas

“This is a persistent canvas, not a temporary camera effect. AirCanvas restores its strokes through the normal document and renderer pipeline.”

Show the Draw / Select / Erase control and the current save state. If AR is preparing, say that the app is mapping the space and follow the visible guidance rather than claiming it is ready.

## 0:45–1:15 — Hand tracking and pinch drawing

“The fingertip cursor only appears after the production hand tracker and AR raycast have both produced a valid spatial point. A confirmed pinch begins drawing; releasing it commits a normal stroke.”

Hold one hand in view, let the real cursor appear, pinch, make one short spatial stroke, then release. Do not rush this step: a visible start, movement, and release makes the interaction clear.

## 1:15–1:40 — Selection and Move

Switch to **Select**. Select an existing stroke, pinch it with the hand and move it, then release.

“Selection and movement are stable-ID edits. The live preview starts from the original stroke, so repeated movement does not accumulate drift.”

## 1:40–2:00 — Scale and Rotate

With the stroke still selected, use the visible **Scale** and **Rotate** controls.

“These controls use the same snapshot-based transform and history path as the rest of the editor, so each committed edit can be reversed exactly.”

## 2:00–2:20 — Erase, Delete, and Undo

Switch to **Erase** and point to a stroke. Explain that hover only identifies a candidate; one confirmed pinch removes one target. Then use **Undo** to restore it. Alternatively use **Delete Selected Stroke** and undo it.

“Destructive actions are deliberate and remain recoverable through normal history.”

## 2:20–2:40 — Persistence and canvases

Leave the editor, return to **My Canvases**, show the canvas name and stroke count, then reopen it.

“The work is stored locally with revision-aware autosave and backup recovery. It can also be exported as a versioned AirCanvas document.”

## 2:40–3:00 — Technical conclusion

“AirCanvas is built in Swift with SwiftUI, ARKit, RealityKit, Vision, local persistence, and native accessibility support. The camera and hand-processing path stays on device; touch remains a first-class alternative.”

## Real touch-control fallback

If lighting, tracking, or the room surface makes hand tracking unreliable, say so plainly and use the real touch path:

1. Point out the truthful tracking guidance rather than faking readiness.
2. In **Draw**, drag on the canvas to create a real touch stroke.
3. In **Select**, tap a stroke, drag to move it, then use Scale and Rotate.
4. Demonstrate Delete/Undo and persistence exactly as above.

The fallback demonstrates the product’s accessibility principle: hand interaction adds expression, but it is not required to create, edit, save, or share a canvas.

## Safe demo reset and preparation

- For clean onboarding, delete AirCanvas from the iPhone and install a fresh normal development build. This is the supported reset path.
- For a prepared demo, keep one ordinary local canvas with several real strokes; use My Canvases to rename/open/delete it as needed.
- Do not delete a canvas to “reset” unless it has first been exported or is intentionally disposable.
- Do not install a hidden reset button or staged tutorial content. The demo should use normal product operations.
