import Foundation

/// Minimal key-value storage so progress can be tested without touching `UserDefaults`.
public protocol KeyValueStore: AnyObject {
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: KeyValueStore {}

public final class InMemoryKeyValueStore: KeyValueStore {
    private var storage: [String: Any] = [:]

    public init() {}

    public func data(forKey defaultName: String) -> Data? {
        storage[defaultName] as? Data
    }

    public func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }
}

public struct LevelRecord: Codable, Equatable, Sendable {
    public var deaths = 0
    public var completions = 0
    /// Fastest completion in seconds.
    public var bestTime: Double?

    public init() {}

    public var isCompleted: Bool { completions > 0 }
}

public struct Progress: Codable, Equatable, Sendable {
    /// Number of playable levels (level index < unlockedCount).
    public var unlockedCount = 1
    public var totalDeaths = 0
    public var levels: [String: LevelRecord] = [:]

    public init() {}
}

/// Persists unlocked levels, deaths and best times as one JSON blob.
public final class ProgressStore {
    public static let defaultKey = "trick-tiles.progress.v1"

    private let store: KeyValueStore
    private let key: String
    public private(set) var progress: Progress

    public init(store: KeyValueStore = UserDefaults.standard, key: String = ProgressStore.defaultKey) {
        self.store = store
        self.key = key
        if let data = store.data(forKey: key), let saved = try? JSONDecoder().decode(Progress.self, from: data) {
            progress = saved
        } else {
            progress = Progress()
        }
    }

    public var unlockedCount: Int { progress.unlockedCount }
    public var totalDeaths: Int { progress.totalDeaths }

    public func isUnlocked(levelIndex: Int) -> Bool {
        levelIndex < progress.unlockedCount
    }

    public func record(forLevel id: String) -> LevelRecord {
        progress.levels[id] ?? LevelRecord()
    }

    public func recordDeath(levelID: String) {
        progress.levels[levelID, default: LevelRecord()].deaths += 1
        progress.totalDeaths += 1
        save()
    }

    public func recordCompletion(levelIndex: Int, levelID: String, time: Double, levelCount: Int) {
        var record = progress.levels[levelID, default: LevelRecord()]
        record.completions += 1
        record.bestTime = min(record.bestTime ?? .infinity, time)
        progress.levels[levelID] = record
        progress.unlockedCount = max(progress.unlockedCount, min(levelIndex + 2, max(levelCount, 1)))
        save()
    }

    /// Unlocks every level (debug menu).
    public func unlockAll(levelCount: Int) {
        progress.unlockedCount = max(progress.unlockedCount, levelCount)
        save()
    }

    public func reset() {
        progress = Progress()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(progress) {
            store.set(data, forKey: key)
        }
    }
}
