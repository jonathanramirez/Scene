import Foundation

extension String {
    func matches(_ pattern: String) -> Bool {
        guard let r = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let range = NSRange(startIndex..<endIndex, in: self)
        return r.firstMatch(in: self, options: [], range: range) != nil
    }
}
