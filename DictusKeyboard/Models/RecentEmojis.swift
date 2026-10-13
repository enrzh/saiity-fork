// DictusKeyboard/Models/RecentEmojis.swift
import Foundation
import SyllivraKernel

/// Manages recently used emojis, persisted via App Group UserDefaults.
/// The caller supplies the page capacity so recents never spill into a second
/// vertical page when the keyboard width changes.
enum RecentEmojis {
    private static let key = "recentEmojis"

    static func load(limit: Int) -> [String] {
        Array((AppGroup.defaults.stringArray(forKey: key) ?? []).prefix(max(0, limit)))
    }

    static func add(_ emoji: String, limit: Int) {
        var recents = AppGroup.defaults.stringArray(forKey: key) ?? []
        // Remove duplicate if already present, then prepend
        recents.removeAll { $0 == emoji }
        recents.insert(emoji, at: 0)
        if recents.count > limit {
            recents = Array(recents.prefix(max(0, limit)))
        }
        AppGroup.defaults.set(recents, forKey: key)
    }
}
