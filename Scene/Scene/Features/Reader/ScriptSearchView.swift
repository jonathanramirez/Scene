import SwiftUI

struct PDFSearchHighlight: Equatable, Identifiable {
    let id = UUID()
    let query: String
    let pageIndex: Int
    let occurrenceIndex: Int
}

struct ScriptSearchMatch: Identifiable, Equatable {
    let id: String
    let query: String
    let pageIndex: Int
    let occurrenceIndex: Int
    let snippet: String
}

struct ScriptSearchView: View {
    let document: ScriptDocument
    let onSelectMatch: (ScriptSearchMatch) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var pages: [PDFSearchPage] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List {
                if isLoading && pages.isEmpty {
                    loadingRow
                } else if let loadError {
                    errorRow(loadError)
                } else if trimmedQuery.isEmpty {
                    emptyPrompt
                } else if results.isEmpty {
                    noResults
                } else {
                    ForEach(results) { match in
                        Button {
                            onSelectMatch(match)
                            dismiss()
                        } label: {
                            resultRow(match)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Search Script")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "PDF text…")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: document.id) {
                await loadPDFText()
            }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [ScriptSearchMatch] {
        guard !trimmedQuery.isEmpty else { return [] }
        let pageMatches = pages.flatMap { matches(in: $0, query: trimmedQuery) }
        return Array(pageMatches.prefix(120))
    }

    private func loadPDFText() async {
        guard pages.isEmpty, !isLoading else { return }
        guard let url = document.resolvedFileURL else {
            loadError = AppError.fileMissing.localizedDescription
            return
        }

        isLoading = true
        loadError = nil
        do {
            let extracted = try await Task.detached(priority: .userInitiated) {
                try PDFTextExtractor.textByPage(url: url)
            }.value
            pages = extracted.map { PDFSearchPage(pageIndex: $0.pageIndex, text: $0.text) }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func matches(in page: PDFSearchPage, query: String) -> [ScriptSearchMatch] {
        let text = page.text
        let nsText = text as NSString
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var foundMatches: [ScriptSearchMatch] = []
        var searchRange = NSRange(location: 0, length: nsText.length)
        var occurrenceIndex = 0

        while searchRange.length > 0 {
            let matchRange = nsText.range(of: query, options: options, range: searchRange)
            guard matchRange.location != NSNotFound else { break }

            foundMatches.append(
                ScriptSearchMatch(
                    id: "\(page.pageIndex)-\(matchRange.location)-\(matchRange.length)-\(query)",
                    query: query,
                    pageIndex: page.pageIndex,
                    occurrenceIndex: occurrenceIndex,
                    snippet: snippet(from: text, matchRange: matchRange)
                )
            )
            occurrenceIndex += 1

            let nextLocation = matchRange.location + max(matchRange.length, 1)
            guard nextLocation <= nsText.length else { break }
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }

        if foundMatches.isEmpty,
           page.normalizedText.contains(normalized(query)) {
            return [
                ScriptSearchMatch(
                    id: "\(page.pageIndex)-normalized-\(query)",
                    query: query,
                    pageIndex: page.pageIndex,
                    occurrenceIndex: 0,
                    snippet: collapsedWhitespace(text).prefixString(maxLength: 180)
                )
            ]
        }

        return foundMatches
    }

    private func snippet(from text: String, matchRange: NSRange) -> String {
        guard let range = Range(matchRange, in: text) else {
            return collapsedWhitespace(text).prefixString(maxLength: 180)
        }

        let leadingDistance = text.distance(from: text.startIndex, to: range.lowerBound)
        let trailingDistance = text.distance(from: range.upperBound, to: text.endIndex)
        let lowerOffset = min(leadingDistance, 90)
        let upperOffset = min(trailingDistance, 120)
        let lower = text.index(range.lowerBound, offsetBy: -lowerOffset)
        let upper = text.index(range.upperBound, offsetBy: upperOffset)
        let prefix = lower == text.startIndex ? "" : "…"
        let suffix = upper == text.endIndex ? "" : "…"
        return prefix + collapsedWhitespace(String(text[lower..<upper])) + suffix
    }

    @ViewBuilder
    private func resultRow(_ match: ScriptSearchMatch) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Page \(match.pageIndex + 1)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                Spacer()
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(highlightedText(match.snippet))
                .font(.subheadline)
                .lineLimit(4)
        }
        .padding(.vertical, 4)
    }

    private func highlightedText(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard !trimmedQuery.isEmpty else { return attributed }

        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex {
            let range = attributed[searchStart...].range(of: trimmedQuery, options: .caseInsensitive)
            guard let range else { break }
            attributed[range].backgroundColor = .orange.opacity(0.3)
            attributed[range].foregroundColor = .orange
            searchStart = range.upperBound
        }
        return attributed
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading PDF text")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }

    private func errorRow(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }

    private var emptyPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Search the PDF text.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }

    private var noResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No matches for \"\(trimmedQuery)\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }

    private func normalized(_ text: String) -> String {
        collapsedWhitespace(text)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func collapsedWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct PDFSearchPage {
    let pageIndex: Int
    let text: String

    var normalizedText: String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

private extension String {
    func prefixString(maxLength: Int) -> String {
        guard count > maxLength else { return self }
        return String(prefix(maxLength)) + "…"
    }
}
