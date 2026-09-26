import Foundation

/// What arms a trap.
///
/// JSON:
/// ```
/// { "type": "zone", "rect": [x, y, w, h] }   // player enters the rect (tiles)
/// { "type": "delay", "seconds": 2.5 }         // time since the level (re)started
/// { "type": "onEvent", "event": "a.fired" }   // another trap fired / emitted an event
/// ```
public enum Trigger: Equatable, Hashable, Sendable {
    case zone(TileRect)
    case delay(Double)
    case onEvent(String)
}

extension Trigger: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, rect, seconds, event
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "zone":
            self = .zone(try c.decode(TileRect.self, forKey: .rect))
        case "delay":
            let seconds = try c.decode(Double.self, forKey: .seconds)
            guard seconds >= 0 else {
                throw DecodingError.dataCorruptedError(forKey: .seconds, in: c, debugDescription: "delay must be >= 0")
            }
            self = .delay(seconds)
        case "onEvent":
            self = .onEvent(try c.decode(String.self, forKey: .event))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown trigger type '\(type)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .zone(let rect):
            try c.encode("zone", forKey: .type)
            try c.encode(rect, forKey: .rect)
        case .delay(let seconds):
            try c.encode("delay", forKey: .type)
            try c.encode(seconds, forKey: .seconds)
        case .onEvent(let event):
            try c.encode("onEvent", forKey: .type)
            try c.encode(event, forKey: .event)
        }
    }
}
