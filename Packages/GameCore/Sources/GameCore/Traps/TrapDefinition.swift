import Foundation

/// A trap as written in level JSON.
///
/// ```
/// {
///   "id": "floor_drop_1",
///   "trigger": { "type": "zone", "rect": [5, 1, 2, 1] },
///   "effect":  { "type": "collapse", "tiles": [[5,0],[6,0]] },
///   "once": true,        // optional, default true
///   "delay": 0.1         // optional seconds between trigger and effect, default 0
/// }
/// ```
/// `"effects": [ ... ]` may be used instead of `"effect"` to fire several effects at once.
public struct TrapDefinition: Equatable, Hashable, Sendable {
    public var id: String
    public var trigger: Trigger
    public var effects: [Effect]
    public var once: Bool
    public var delay: Double

    public init(id: String, trigger: Trigger, effects: [Effect], once: Bool = true, delay: Double = 0) {
        self.id = id
        self.trigger = trigger
        self.effects = effects
        self.once = once
        self.delay = delay
    }

    public init(id: String, trigger: Trigger, effect: Effect, once: Bool = true, delay: Double = 0) {
        self.init(id: id, trigger: trigger, effects: [effect], once: once, delay: delay)
    }
}

extension TrapDefinition: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, trigger, effect, effects, once, delay
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        trigger = try c.decode(Trigger.self, forKey: .trigger)
        if let list = try c.decodeIfPresent([Effect].self, forKey: .effects) {
            effects = list
        } else {
            effects = [try c.decode(Effect.self, forKey: .effect)]
        }
        guard !effects.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .effects, in: c, debugDescription: "trap '\(id)' has no effects")
        }
        once = try c.decodeIfPresent(Bool.self, forKey: .once) ?? true
        delay = try c.decodeIfPresent(Double.self, forKey: .delay) ?? 0
        guard delay >= 0 else {
            throw DecodingError.dataCorruptedError(forKey: .delay, in: c, debugDescription: "delay must be >= 0")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(trigger, forKey: .trigger)
        if effects.count == 1 {
            try c.encode(effects[0], forKey: .effect)
        } else {
            try c.encode(effects, forKey: .effects)
        }
        if !once { try c.encode(once, forKey: .once) }
        if delay > 0 { try c.encode(delay, forKey: .delay) }
    }
}
