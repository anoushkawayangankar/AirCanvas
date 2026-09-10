import Foundation

enum CanvasLaunch: Hashable {
    case new
    case existing(UUID)
}

enum AppRoute: Hashable {
    case canvas(CanvasLaunch)
    case myCanvases
    case settings
}
