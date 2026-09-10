import SwiftUI

struct CanvasBrushControlsView: View {
    let brushSettings: BrushSettings
    let selectColor: (BrushColor) -> Void
    let updateThickness: (Float) -> Void
    let canUndo: Bool
    let canRedo: Bool
    let undo: () -> Void
    let redo: () -> Void
    let canvasTool: CanvasTool
    let selectTool: (CanvasTool) -> Void
    let hasSelectedStroke: Bool
    let deleteSelectedStroke: () -> Void
    let transformScale: Float
    let transformAngleDegrees: Float
    let beginScaleTransform: () -> Void
    let updateScaleTransform: (Float) -> Void
    let beginRotationTransform: () -> Void
    let updateRotationTransform: (Float) -> Void
    let endTransform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Canvas tool", selection: toolBinding) {
                Text("Draw").tag(CanvasTool.draw)
                Text("Select").tag(CanvasTool.select)
                Text("Erase").tag(CanvasTool.erase)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Canvas tool")
            .accessibilityValue("\(canvasTool.accessibilityName), selected")
            .accessibilityIdentifier("editor.toolPicker")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    undoButton
                    redoButton
                }

                VStack(alignment: .trailing, spacing: 8) {
                    undoButton
                    redoButton
                }
            }

            if canvasTool == .draw {
                drawControls
            } else if canvasTool == .select {
                selectionControls
                if hasSelectedStroke {
                    transformControls
                }
            } else {
                Label("Point at a stroke, then pinch once to erase it.", systemImage: "eraser")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Erase mode")
                    .accessibilityValue("Point at a stroke, then pinch once to erase it")
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .allowsHitTesting(true)
        .accessibilityElement(children: .contain)
    }

    private var transformControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transform").font(.subheadline.weight(.medium))
            Slider(value: scaleBinding, in: 0.25...4.0, step: 0.01, onEditingChanged: { editing in
                if editing { beginScaleTransform() } else { endTransform() }
            })
            .accessibilityLabel("Scale selected stroke")
            .accessibilityValue(String(format: "%.2f times", transformScale))
            .accessibilityIdentifier("editor.scale")
            Slider(value: rotationBinding, in: -180...180, step: 1, onEditingChanged: { editing in
                if editing { beginRotationTransform() } else { endTransform() }
            })
            .accessibilityLabel("Rotate selected stroke")
            .accessibilityValue(String(format: "%.0f degrees", transformAngleDegrees))
            .accessibilityIdentifier("editor.rotation")
        }
    }

    private var drawControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                BrushPreviewView(style: brushSettings.style)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Brush")
                        .font(.headline)
                    Text("\(selectedColorName) • \(CanvasBrushConfiguration.thicknessDescription(brushSettings.style.thickness))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)

                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CanvasBrushConfiguration.colorOptions) { option in
                        colorButton(for: option)
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityLabel("Brush color choices")

            HStack(spacing: 10) {
                Text("Thickness")
                    .font(.subheadline.weight(.medium))

                Slider(
                    value: thicknessBinding,
                    in: Double(CanvasBrushConfiguration.thicknessRange.lowerBound)
                        ... Double(CanvasBrushConfiguration.thicknessRange.upperBound),
                    step: Double(CanvasBrushConfiguration.thicknessStep)
                )
                .tint(uiColor(for: brushSettings.style.color))
                .accessibilityLabel("Brush thickness")
                .accessibilityValue(CanvasBrushConfiguration.thicknessDescription(brushSettings.style.thickness))

                Text(CanvasBrushConfiguration.thicknessDescription(brushSettings.style.thickness))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 88, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var selectionControls: some View {
        if hasSelectedStroke {
            HStack(spacing: 12) {
                Label("Stroke selected", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .accessibilityLabel("One stroke selected")
                Spacer(minLength: 0)
                Button(role: .destructive, action: deleteSelectedStroke) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Delete selected stroke")
                .accessibilityHint("Removes the selected stroke. Undo is available afterward.")
                .accessibilityIdentifier("editor.deleteSelected")
            }
        } else {
            Label("Tap a stroke to select it.", systemImage: "hand.tap")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Selection mode")
                .accessibilityValue("Tap a stroke to select it")
        }
    }

    private var thicknessBinding: Binding<Double> {
        Binding(
            get: { Double(brushSettings.style.thickness) },
            set: { updateThickness(Float($0)) }
        )
    }

    private var scaleBinding: Binding<Double> {
        Binding(get: { Double(transformScale) }, set: { updateScaleTransform(Float($0)) })
    }

    private var rotationBinding: Binding<Double> {
        Binding(get: { Double(transformAngleDegrees) }, set: { updateRotationTransform(Float($0)) })
    }

    private var toolBinding: Binding<CanvasTool> {
        Binding(
            get: { canvasTool },
            set: { selectTool($0) }
        )
    }

    private var selectedColorName: String {
        CanvasBrushConfiguration.colorOptions.first(where: { $0.color == brushSettings.style.color })?.name
            ?? "Custom color"
    }

    private var undoButton: some View {
        Button(action: undo) {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }
        .buttonStyle(.bordered)
        .disabled(!canUndo)
        .accessibilityLabel("Undo last stroke")
        .accessibilityIdentifier("editor.undo")
        .frame(minWidth: 44, minHeight: 44)
    }

    private var redoButton: some View {
        Button(action: redo) {
            Label("Redo", systemImage: "arrow.uturn.forward")
        }
        .buttonStyle(.bordered)
        .disabled(!canRedo)
        .accessibilityLabel("Redo last stroke")
        .accessibilityIdentifier("editor.redo")
        .frame(minWidth: 44, minHeight: 44)
    }

    private func colorButton(for option: CanvasBrushColorOption) -> some View {
        let isSelected = option.color == brushSettings.style.color
        return Button {
            selectColor(option.color)
        } label: {
            ZStack {
                Circle()
                    .fill(uiColor(for: option.color))
                    .frame(width: 38, height: 38)
                Circle()
                    .strokeBorder(.primary.opacity(isSelected ? 0.9 : 0.25), lineWidth: isSelected ? 3 : 1)
                    .frame(width: 42, height: 42)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 1)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.name) brush color")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func uiColor(for color: BrushColor) -> Color {
        Color(
            red: Double(color.red),
            green: Double(color.green),
            blue: Double(color.blue),
            opacity: Double(color.alpha)
        )
    }
}

private extension CanvasTool {
    var accessibilityName: String {
        switch self {
        case .draw: "Draw"
        case .select: "Select"
        case .erase: "Erase"
        }
    }
}

private struct BrushPreviewView: View {
    let style: BrushStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.thinMaterial)
                .frame(width: 54, height: 44)
            Capsule()
                .fill(
                    Color(
                        red: Double(style.color.red),
                        green: Double(style.color.green),
                        blue: Double(style.color.blue),
                        opacity: Double(style.color.alpha)
                    )
                )
                .frame(width: 34, height: max(4, CGFloat(style.thickness * 1_000)))
        }
        .accessibilityLabel("Current brush preview")
        .accessibilityValue("Color and thickness: \(CanvasBrushConfiguration.thicknessDescription(style.thickness))")
    }
}
