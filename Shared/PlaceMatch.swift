import Foundation

/// Decides whether a map search result plausibly is what was searched for.
///
/// Map search returns its nearest loose match even when nothing fits, e.g. a
/// bicycle park in Tokyo for a street address in Kunming. A result counts only
/// when it shares a meaningful word (or, for Chinese, Japanese and Korean
/// text, a few characters) with the query.
enum PlaceMatch {
    static func isRelevant(query: String, name: String, address: String?) -> Bool {
        let result = (name + " " + (address ?? "")).lowercased()
        let q = query.lowercased()

        let ideographs = Set(q.unicodeScalars.filter(isCJK))
        if !ideographs.isEmpty {
            let shared = ideographs.filter { result.unicodeScalars.contains($0) }.count
            if shared >= min(3, ideographs.count) { return true }
        }

        let resultWords = Set(words(result))
        return words(q).contains { resultWords.contains($0) }
    }

    /// Words of three or more letters, minus ones that match almost anything.
    static func words(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !$0.unicodeScalars.contains(where: isCJK) && !genericWords.contains($0) }
    }

    private static let genericWords: Set<String> = ["the", "and", "hotel", "inn", "road", "street", "city", "town", "district"]

    static func isCJK(_ s: Unicode.Scalar) -> Bool {
        s.properties.isIdeographic || (0x3040...0x30FF).contains(s.value) || (0xAC00...0xD7AF).contains(s.value)
    }
}
