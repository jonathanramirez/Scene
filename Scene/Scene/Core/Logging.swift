import Foundation
import OSLog

enum Log {
    static let app = Logger(subsystem: "com.yourcompany.scene", category: "app")
    static let pdf = Logger(subsystem: "com.yourcompany.scene", category: "pdf")
    static let importFlow = Logger(subsystem: "com.yourcompany.scene", category: "import")
    static let parse = Logger(subsystem: "com.yourcompany.scene", category: "parse")
}
