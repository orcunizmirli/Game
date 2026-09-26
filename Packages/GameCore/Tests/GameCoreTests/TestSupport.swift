import XCTest
@testable import GameCore

/// Builds a level from grid rows (top row first) and optional traps.
func makeLevel(_ rows: [String], traps: [TrapDefinition] = [], id: String = "test") -> Level {
    Level(id: id, grid: rows, traps: traps)
}

/// A simple collision provider backed by a grid.
struct GridWorld: CollisionProvider {
    var grid: TileGrid
    func solids(in region: AABB) -> [AABB] { grid.solids(in: region) }

    /// Rows top-first, `#` solid.
    init(_ rows: [String]) {
        let h = rows.count, w = rows[0].count
        grid = TileGrid(width: w, height: h)
        for (r, line) in rows.enumerated() {
            for (x, c) in line.enumerated() where c == "#" {
                grid.set(.solid, at: GridPoint(x, h - 1 - r))
            }
        }
    }
}

extension Simulation {
    /// Steps `n` times with the same input; stops early when the run ends.
    mutating func run(_ n: Int, _ input: InputState = .none) {
        for _ in 0..<n where isRunning { step(input) }
    }

    /// Steps until `condition` holds or `limit` steps pass. Returns true if it held.
    @discardableResult
    mutating func run(until condition: (Simulation) -> Bool, limit: Int = 2000, _ input: InputState = .none) -> Bool {
        for _ in 0..<limit {
            if condition(self) { return true }
            guard isRunning else { return condition(self) }
            step(input)
        }
        return condition(self)
    }
}

let right = InputState(right: true)
let left = InputState(left: true)
let jump = InputState(jumpPressed: true, jumpHeld: true)
let holdJump = InputState(jumpHeld: true)
