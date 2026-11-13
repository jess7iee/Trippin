import Foundation

/// Decides whether a recommendation was made for a given to-do item.
enum TodoMatch {
    /// `forTodo` is what Claude says the suggestion is for; it should be the to-do
    /// text copied exactly, but may differ in case, punctuation or by a word.
    static func answers(_ forTodo: String, todo: String) -> Bool {
        let trim = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let a = forTodo.lowercased().trimmingCharacters(in: trim)
        let b = todo.lowercased().trimmingCharacters(in: trim)
        guard !a.isEmpty, !b.isEmpty, a != "general" else { return false }
        return a == b || a.contains(b) || b.contains(a)
    }
}
