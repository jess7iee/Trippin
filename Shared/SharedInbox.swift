import Foundation

/// Hands emails from the share extension to the app through the App Group.
enum SharedInbox {
    static let appGroup = "group.com.jess7iee.trippin"
    private static let key = "pendingEmails"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static var isAvailable: Bool { defaults != nil }

    static func add(_ text: String) {
        guard let defaults else { return }
        var items = defaults.stringArray(forKey: key) ?? []
        items.append(text)
        defaults.set(items, forKey: key)
    }

    /// Returns and clears every pending item.
    static func takeAll() -> [String] {
        guard let defaults else { return [] }
        let items = defaults.stringArray(forKey: key) ?? []
        defaults.removeObject(forKey: key)
        return items
    }
}
