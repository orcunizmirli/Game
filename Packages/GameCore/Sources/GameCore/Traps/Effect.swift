import Foundation

/// What a trap does when it fires. Each case is implemented by one `TrapEffect` type in
/// `Traps/Effects/`; `TrapFactory` maps between them.
///
/// Tile lists can be given either as `"tiles": [[x,y], ...]` or as `"rect": [x, y, w, h]`.
///
/// JSON:
/// ```
/// { "type": "collapse",       "tiles": [[5,0],[6,0]] }
/// { "type": "spawnSpikes",    "at": [[3,1]], "dir": "up" }
/// { "type": "moveDoor",       "to": [20,1], "speed": 14 }
/// { "type": "dropCeiling",    "rect": [8,9,3,1], "speed": 12 }
/// { "type": "invertControls", "duration": 3 }
/// { "type": "emit",           "event": "boom" }
/// { "type": "addTiles",       "tiles": [[4,1]] }
/// { "type": "slideTiles",     "rect": [10,1,2,3], "by": [4,0], "speed": 6 }
/// ```
public enum Effect: Equatable, Hashable, Sendable {
    /// Removes tiles (floor falls away).
    case collapse(tiles: [GridPoint])
    /// Turns tiles into spikes.
    case spawnSpikes(at: [GridPoint], direction: SpikeDirection)
    /// Slides the door to a new tile. Speed 0 teleports.
    case moveDoor(to: GridPoint, speed: Double)
    /// Detaches solid tiles and drops them until they land. Crushes the player.
    case dropCeiling(tiles: [GridPoint], speed: Double)
    /// Swaps left and right for a while.
    case invertControls(duration: Double)
    /// Emits a named event for other traps.
    case emit(event: String)
    /// Makes solid tiles appear.
    case addTiles(tiles: [GridPoint])
    /// Moves solid tiles by an exact offset, then they become static again.
    case slideTiles(tiles: [GridPoint], by: GridPoint, speed: Double)

    public var typeName: String {
        switch self {
        case .collapse: return "collapse"
        case .spawnSpikes: return "spawnSpikes"
        case .moveDoor: return "moveDoor"
        case .dropCeiling: return "dropCeiling"
        case .invertControls: return "invertControls"
        case .emit: return "emit"
        case .addTiles: return "addTiles"
        case .slideTiles: return "slideTiles"
        }
    }

    /// Tiles referenced by the effect (for validation).
    public var referencedTiles: [GridPoint] {
        switch self {
        case .collapse(let t), .dropCeiling(let t, _), .addTiles(let t), .slideTiles(let t, _, _):
            return t
        case .spawnSpikes(let t, _):
            return t
        case .moveDoor(let p, _):
            return [p]
        case .invertControls, .emit:
            return []
        }
    }
}

extension Effect: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, tiles, rect, at, dir, to, speed, duration, event, by
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)

        func tiles(_ primary: CodingKeys = .tiles) throws -> [GridPoint] {
            if let list = try c.decodeIfPresent([GridPoint].self, forKey: primary) { return list }
            if primary != .tiles, let list = try c.decodeIfPresent([GridPoint].self, forKey: .tiles) { return list }
            if let rect = try c.decodeIfPresent(TileRect.self, forKey: .rect) { return rect.gridPoints }
            throw DecodingError.keyNotFound(primary, .init(codingPath: c.codingPath,
                                                           debugDescription: "\(type) needs '\(primary.rawValue)' or 'rect'"))
        }

        func positive(_ key: CodingKeys, default value: Double? = nil) throws -> Double {
            let v: Double
            if let value { v = try c.decodeIfPresent(Double.self, forKey: key) ?? value } else { v = try c.decode(Double.self, forKey: key) }
            guard v >= 0 else {
                throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "\(key.rawValue) must be >= 0")
            }
            return v
        }

        switch type {
        case "collapse":
            self = .collapse(tiles: try tiles())
        case "spawnSpikes":
            let dir = try c.decodeIfPresent(SpikeDirection.self, forKey: .dir) ?? .up
            self = .spawnSpikes(at: try tiles(.at), direction: dir)
        case "moveDoor":
            self = .moveDoor(to: try c.decode(GridPoint.self, forKey: .to),
                             speed: try positive(.speed, default: Constants.defaultDoorSpeed))
        case "dropCeiling":
            self = .dropCeiling(tiles: try tiles(), speed: try positive(.speed, default: 12))
        case "invertControls":
            self = .invertControls(duration: try positive(.duration))
        case "emit":
            self = .emit(event: try c.decode(String.self, forKey: .event))
        case "addTiles":
            self = .addTiles(tiles: try tiles())
        case "slideTiles":
            let speed = try positive(.speed, default: 6)
            guard speed > 0 else {
                throw DecodingError.dataCorruptedError(forKey: .speed, in: c, debugDescription: "slideTiles speed must be > 0")
            }
            self = .slideTiles(tiles: try tiles(), by: try c.decode(GridPoint.self, forKey: .by), speed: speed)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown effect type '\(type)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(typeName, forKey: .type)
        switch self {
        case .collapse(let t), .addTiles(let t):
            try c.encode(t, forKey: .tiles)
        case .spawnSpikes(let t, let dir):
            try c.encode(t, forKey: .at)
            try c.encode(dir, forKey: .dir)
        case .moveDoor(let p, let speed):
            try c.encode(p, forKey: .to)
            try c.encode(speed, forKey: .speed)
        case .dropCeiling(let t, let speed):
            try c.encode(t, forKey: .tiles)
            try c.encode(speed, forKey: .speed)
        case .invertControls(let d):
            try c.encode(d, forKey: .duration)
        case .emit(let e):
            try c.encode(e, forKey: .event)
        case .slideTiles(let t, let by, let speed):
            try c.encode(t, forKey: .tiles)
            try c.encode(by, forKey: .by)
            try c.encode(speed, forKey: .speed)
        }
    }
}
