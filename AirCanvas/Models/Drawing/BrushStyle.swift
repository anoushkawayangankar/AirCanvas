import Foundation

/// A stable, framework-independent RGBA color representation for persisted strokes.
struct BrushColor: Codable, Equatable, Hashable, Sendable {
    let red: Float
    let green: Float
    let blue: Float
    let alpha: Float

    init(red: Float, green: Float, blue: Float, alpha: Float = 1) throws {
        let components = [red, green, blue, alpha]
        guard components.allSatisfy({ $0.isFinite && (0 ... 1).contains($0) }) else {
            throw BrushColorValidationError.componentOutOfRange
        }

        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    static let defaultColor = BrushColor(uncheckedRed: 0.1, green: 0.8, blue: 1, alpha: 1)
    static let canvasRed = BrushColor(uncheckedRed: 0.96, green: 0.23, blue: 0.22, alpha: 1)
    static let canvasOrange = BrushColor(uncheckedRed: 0.98, green: 0.55, blue: 0.15, alpha: 1)
    static let canvasGreen = BrushColor(uncheckedRed: 0.18, green: 0.72, blue: 0.35, alpha: 1)
    static let canvasViolet = BrushColor(uncheckedRed: 0.56, green: 0.35, blue: 0.95, alpha: 1)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            red: container.decode(Float.self, forKey: .red),
            green: container.decode(Float.self, forKey: .green),
            blue: container.decode(Float.self, forKey: .blue),
            alpha: container.decode(Float.self, forKey: .alpha)
        )
    }

    private init(uncheckedRed red: Float, green: Float, blue: Float, alpha: Float) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

enum BrushColorValidationError: Error, Equatable, Sendable {
    case componentOutOfRange
}

/// The immutable style snapshot retained by a completed stroke.
struct BrushStyle: Codable, Equatable, Hashable, Sendable {
    let color: BrushColor
    let thickness: Float

    init(color: BrushColor, thickness: Float) throws {
        guard thickness.isFinite, thickness > 0 else {
            throw BrushStyleValidationError.invalidThickness
        }

        self.color = color
        self.thickness = thickness
    }

    static let defaultStyle = BrushStyle(uncheckedColor: .defaultColor, thickness: 0.006)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            color: container.decode(BrushColor.self, forKey: .color),
            thickness: container.decode(Float.self, forKey: .thickness)
        )
    }

    private init(uncheckedColor color: BrushColor, thickness: Float) {
        self.color = color
        self.thickness = thickness
    }
}

enum BrushStyleValidationError: Error, Equatable, Sendable {
    case invalidThickness
}

/// Mutable drawing preferences for a future drawing engine or tool state.
/// A completed stroke must copy `style` rather than retain this mutable value.
struct BrushSettings: Equatable, Hashable, Sendable {
    private(set) var style: BrushStyle

    static let defaultSettings = BrushSettings(style: .defaultStyle)

    init(style: BrushStyle) {
        self.style = style
    }

    mutating func update(color: BrushColor? = nil, thickness: Float? = nil) throws {
        style = try BrushStyle(
            color: color ?? style.color,
            thickness: thickness ?? style.thickness
        )
    }
}
