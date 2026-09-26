import Foundation

/// Finds, parses and caches level files.
///
/// Every `level_*.json` in the levels directory is a level; they are ordered by file name,
/// so adding `level_011.json` adds a level without touching code.
public final class LevelCatalog {
    public enum Source: Equatable {
        /// JSON files shipped inside the GameCore resource bundle.
        case bundled
        /// Any directory, e.g. the source tree for hot reload in the simulator.
        case directory(URL)
    }

    public let source: Source
    public private(set) var files: [URL] = []
    private var cache: [Int: Level] = [:]

    public init(source: Source = .bundled) throws {
        self.source = source
        try rescan()
    }

    public var count: Int { files.count }

    /// Parsed level, cached after the first load so restarts never touch the disk.
    public func level(at index: Int) throws -> Level {
        if let cached = cache[index] { return cached }
        guard files.indices.contains(index) else {
            throw LevelError("catalog", "no level at index \(index)")
        }
        let url = files[index]
        let level: Level
        do {
            level = try Self.decode(Data(contentsOf: url))
        } catch {
            throw LevelError(url.lastPathComponent, "\(error)")
        }
        cache[index] = level
        return level
    }

    public func allLevels() throws -> [Level] {
        try (0..<count).map(level(at:))
    }

    /// Drops the cache and rescans the directory (debug hot reload).
    public func reload() throws {
        cache.removeAll()
        try rescan()
    }

    private func rescan() throws {
        guard let dir = directory else {
            throw LevelError("catalog", "levels directory not found")
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        files = names
            .filter { $0.hasPrefix("level_") && $0.hasSuffix(".json") }
            .sorted()
            .map { dir.appendingPathComponent($0) }
    }

    public var directory: URL? {
        switch source {
        case .bundled: return Self.bundledDirectory
        case .directory(let url): return url
        }
    }

    public static var bundledDirectory: URL? {
        Bundle.module.url(forResource: "Levels", withExtension: nil)
    }

    /// `Levels/` in the source checkout. Exists when running from Xcode on the simulator
    /// or from `swift test`; used for hot reload and by tooling.
    public static var sourceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // World
            .deletingLastPathComponent() // GameCore
            .appendingPathComponent("Levels", isDirectory: true)
    }

    public static func decode(_ data: Data) throws -> Level {
        try JSONDecoder().decode(Level.self, from: data)
    }

    /// Stored solution for a level, if one exists (`Levels/solutions/<id>.txt`).
    public func solution(for levelID: String) -> InputReplay? {
        guard let dir = directory else { return nil }
        let url = dir.appendingPathComponent("solutions/\(levelID).txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return try? InputReplay(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
