import Foundation

/// Leitet einen knappen Titel aus rohem Capture-Text ab: erste nicht-leere Zeile,
/// sonst die ersten ~6 Wörter. Geteilt von Capture-Notiz-Fallback und ViewModel.
enum RawTextTitle {
    static func derive(from text: String) -> String {
        let firstLine = text
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if !firstLine.isEmpty { return firstLine }

        let words = text.split(whereSeparator: { $0.isWhitespace }).prefix(6)
        return words.joined(separator: " ")
    }
}
