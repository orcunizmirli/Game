import Foundation

/// Direction a spike points to.
public enum SpikeDirection: String, Codable, Sendable, CaseIterable {
    case up, down, left, right
}

/// Contents of one grid cell.
public enum TileKind: UInt8, Codable, Sendable, CaseIterable {
    case empty
    /// `#` Wall / floor.
    case solid
    /// `^` `v` `<` `>` Spikes (deadly, not solid).
    case spikeUp, spikeDown, spikeLeft, spikeRight
    /// `x` Looks exactly like a wall but has no collision.
    case fake
    /// `?` Solid but invisible until the player touches it.
    case hidden
    /// A hidden block after it has been touched.
    case revealed

    public var isSolid: Bool {
        switch self {
        case .solid, .hidden, .revealed: return true
        default: return false
        }
    }

    public var spikeDirection: SpikeDirection? {
        switch self {
        case .spikeUp: return .up
        case .spikeDown: return .down
        case .spikeLeft: return .left
        case .spikeRight: return .right
        default: return nil
        }
    }

    public var isHazard: Bool { spikeDirection != nil }

    /// Whether the renderer should draw this tile as a wall block.
    public var looksSolid: Bool {
        self == .solid || self == .fake || self == .revealed
    }

    public static func spike(_ direction: SpikeDirection) -> TileKind {
        switch direction {
        case .up: return .spikeUp
        case .down: return .spikeDown
        case .left: return .spikeLeft
        case .right: return .spikeRight
        }
    }

    /// Deadly region of a spike tile at `p`. Smaller than the drawn triangle to feel fair.
    public func hazardBounds(at p: GridPoint) -> AABB? {
        guard let dir = spikeDirection else { return nil }
        let x = Double(p.x), y = Double(p.y)
        let inset = 0.2, depth = 0.45
        switch dir {
        case .up: return AABB(minX: x + inset, minY: y, maxX: x + 1 - inset, maxY: y + depth)
        case .down: return AABB(minX: x + inset, minY: y + 1 - depth, maxX: x + 1 - inset, maxY: y + 1)
        case .right: return AABB(minX: x, minY: y + inset, maxX: x + depth, maxY: y + 1 - inset)
        case .left: return AABB(minX: x + 1 - depth, minY: y + inset, maxX: x + 1, maxY: y + 1 - inset)
        }
    }
}

/// Characters allowed in a level grid.
public enum GridSymbol {
    public static let empty: Character = "."
    public static let solid: Character = "#"
    public static let spawn: Character = "S"
    public static let door: Character = "D"

    public static func tile(for c: Character) -> TileKind? {
        switch c {
        case ".", " ", "S", "D": return .empty
        case "#": return .solid
        case "^": return .spikeUp
        case "v": return .spikeDown
        case "<": return .spikeLeft
        case ">": return .spikeRight
        case "x": return .fake
        case "?": return .hidden
        default: return nil
        }
    }

    public static func character(for kind: TileKind) -> Character {
        switch kind {
        case .empty: return "."
        case .solid: return "#"
        case .spikeUp: return "^"
        case .spikeDown: return "v"
        case .spikeLeft: return "<"
        case .spikeRight: return ">"
        case .fake: return "x"
        case .hidden: return "?"
        case .revealed: return "#"
        }
    }
}
