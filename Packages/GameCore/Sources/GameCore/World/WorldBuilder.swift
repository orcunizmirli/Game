import Foundation

/// Problems found while turning level JSON into a world.
public struct LevelError: Error, Equatable, CustomStringConvertible {
    public let levelID: String
    public let message: String

    public init(_ levelID: String, _ message: String) {
        self.levelID = levelID
        self.message = message
    }

    public var description: String { "\(levelID): \(message)" }
}

/// Builds a fresh `World` from a parsed `Level`. Called on every (re)start.
public enum WorldBuilder {
    public static func build(_ level: Level) throws -> World {
        let issues = validate(level)
        if let first = issues.first(where: { $0.isError }) {
            throw LevelError(level.id, first.message)
        }

        let width = level.width, height = level.height
        var grid = TileGrid(width: width, height: height)
        var spawn: GridPoint?
        var door: GridPoint?

        for (row, line) in level.grid.enumerated() {
            let y = height - 1 - row
            for (x, c) in line.enumerated() {
                let p = GridPoint(x, y)
                if c == GridSymbol.spawn { spawn = p }
                if c == GridSymbol.door { door = p }
                if let kind = GridSymbol.tile(for: c), kind != .empty {
                    grid.set(kind, at: p)
                }
            }
        }

        guard let spawn, let door else {
            throw LevelError(level.id, "missing spawn or door")
        }
        let spawnFeet = Vec2(Double(spawn.x) + 0.5, Double(spawn.y))
        return World(levelID: level.id, grid: grid, spawn: spawnFeet,
                     door: Door(position: Vec2(Double(door.x), Double(door.y))))
    }

    public struct Issue: Equatable, CustomStringConvertible {
        public let isError: Bool
        public let message: String
        public var description: String { (isError ? "error: " : "warning: ") + message }
    }

    /// Static checks. Errors make the level unloadable; warnings are reported by
    /// `levelcheck` and the tests.
    public static func validate(_ level: Level) -> [Issue] {
        var issues: [Issue] = []
        func error(_ m: String) { issues.append(Issue(isError: true, message: m)) }
        func warn(_ m: String) { issues.append(Issue(isError: false, message: m)) }

        guard !level.grid.isEmpty else {
            error("grid is empty")
            return issues
        }
        let width = level.grid[0].count
        if width == 0 { error("grid rows are empty") }
        var spawns = 0, doors = 0
        for (row, line) in level.grid.enumerated() {
            if line.count != width {
                error("row \(row) has \(line.count) columns, expected \(width)")
            }
            for c in line {
                if c == GridSymbol.spawn { spawns += 1 }
                if c == GridSymbol.door { doors += 1 }
                if GridSymbol.tile(for: c) == nil {
                    error("row \(row) contains unknown symbol '\(c)'")
                }
            }
        }
        if spawns != 1 { error("expected exactly one spawn 'S', found \(spawns)") }
        if doors != 1 { error("expected exactly one door 'D', found \(doors)") }

        var ids = Set<String>()
        var emitted = Set<String>()
        for trap in level.traps {
            if !ids.insert(trap.id).inserted { error("duplicate trap id '\(trap.id)'") }
            emitted.insert(EventBus.firedEvent(for: trap.id))
            for effect in trap.effects {
                if case .emit(let e) = effect { emitted.insert(e) }
                for p in effect.referencedTiles where p.x < 0 || p.y < 0 || p.x >= width || p.y >= level.grid.count {
                    error("trap '\(trap.id)' \(effect.typeName) references \(p) outside the grid")
                }
            }
        }
        for trap in level.traps {
            if case .onEvent(let e) = trap.trigger, !emitted.contains(e) {
                warn("trap '\(trap.id)' listens for '\(e)' which nothing emits")
            }
        }
        return issues
    }
}
