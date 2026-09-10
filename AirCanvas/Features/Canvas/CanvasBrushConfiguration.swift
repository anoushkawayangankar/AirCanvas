import Foundation

struct CanvasBrushColorOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let color: BrushColor
}

enum CanvasBrushConfiguration {
    static let colorOptions: [CanvasBrushColorOption] = [
        CanvasBrushColorOption(id: "sky", name: "Sky", color: .defaultColor),
        CanvasBrushColorOption(id: "red", name: "Red", color: .canvasRed),
        CanvasBrushColorOption(id: "orange", name: "Orange", color: .canvasOrange),
        CanvasBrushColorOption(id: "green", name: "Green", color: .canvasGreen),
        CanvasBrushColorOption(id: "violet", name: "Violet", color: .canvasViolet)
    ]

    static let thicknessRange: ClosedRange<Float> = 0.002 ... 0.02
    static let thicknessStep: Float = 0.001

    static func clampedThickness(_ thickness: Float) -> Float {
        guard thickness.isFinite else {
            return BrushSettings.defaultSettings.style.thickness
        }
        return min(max(thickness, thicknessRange.lowerBound), thicknessRange.upperBound)
    }

    static func thicknessDescription(_ thickness: Float) -> String {
        let millimeters = Int((thickness * 1_000).rounded())
        return "\(millimeters) millimeters"
    }
}
