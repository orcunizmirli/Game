import Foundation

/// A level exactly as stored in `Levels/level_NNN.json`.
///
/// Grid rows are listed top to bottom (as you see them in the file); in the simulation
/// (0,0) is the bottom-left tile. Symbols:
///
/// | char | meaning |
/// |------|---------|
/// | `#`  | wall / floor |
/// | `.`  | empty |
/// | `S`  | player spawn (exactly one) |
/// | `D`  | door / exit (exactly one) |
/// | `^` `v` `<` `>` | spikes pointing up / down / left / right |
/// | `x`  | fake wall: drawn like `#`, no collision |
/// | `?`  | hidden block: solid but invisible until touched |
public struct Level: Equatable, Hashable, Sendable {
    public var id: String
    /// Title shown when the level starts.
    public var name: String
    /// Render size of a tile in points (informational; the renderer scales to fit).
    public var tileSize: Double
    public var grid: [String]
    public var traps: [TrapDefinition]
    /// Optional palette index for the renderer.
    public var theme: Int?

    public init(id: String, name: String? = nil, tileSize: Double = 32, grid: [String],
                traps: [TrapDefinition] = [], theme: Int? = nil) {
        self.id = id
        self.name = name ?? id
        self.tileSize = tileSize
        self.grid = grid
        self.traps = traps
        self.theme = theme
    }

    public var width: Int { grid.map { $0.count }.max() ?? 0 }
    public var height: Int { grid.count }
}

extension Level: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, tileSize, grid, traps, theme
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        tileSize = try c.decodeIfPresent(Double.self, forKey: .tileSize) ?? 32
        grid = try c.decode([String].self, forKey: .grid)
        traps = try c.decodeIfPresent([TrapDefinition].self, forKey: .traps) ?? []
        theme = try c.decodeIfPresent(Int.self, forKey: .theme)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(tileSize, forKey: .tileSize)
        try c.encode(grid, forKey: .grid)
        try c.encode(traps, forKey: .traps)
        try c.encodeIfPresent(theme, forKey: .theme)
    }
}
