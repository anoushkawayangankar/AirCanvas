/// The interaction mode currently active in the Canvas editor.
enum CanvasTool: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case draw
    case select
    case erase
}
