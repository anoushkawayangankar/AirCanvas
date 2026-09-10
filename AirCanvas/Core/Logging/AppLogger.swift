import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.aircanvas.app"

    static let application = Logger(subsystem: subsystem, category: "application")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let ar = Logger(subsystem: subsystem, category: "ar")
    static let vision = Logger(subsystem: subsystem, category: "vision")
    static let drawing = Logger(subsystem: subsystem, category: "drawing")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let performance = Logger(subsystem: subsystem, category: "performance")
}
