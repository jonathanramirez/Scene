import Foundation

extension URL {
    func withSecurityScopedAccess<T>(_ work: () throws -> T) throws -> T {
        let ok = startAccessingSecurityScopedResource()
        defer { if ok { stopAccessingSecurityScopedResource() } }
        guard ok else { throw AppError.securityScopedAccessDenied }
        return try work()
    }
}
