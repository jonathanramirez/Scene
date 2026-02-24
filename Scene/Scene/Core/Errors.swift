import Foundation

enum AppError: LocalizedError {
    case generic(String)
    case importFailed
    case securityScopedAccessDenied
    case pdfOpenFailed
    case noFileURL

    var errorDescription: String? {
        switch self {
        case .generic(let msg): return msg
        case .importFailed: return "Import failed."
        case .securityScopedAccessDenied: return "Security-scoped access denied."
        case .pdfOpenFailed: return "Could not open PDF."
        case .noFileURL: return "No file URL on document."
        }
    }
}
