import Foundation

/// The standard trap: waits for its `Trigger`, optionally counts down `delay`, then runs its
/// effects. Every trap in the level JSON becomes one of these.
public struct TriggeredTrap: Trap, Hashable {
    public let definition: TrapDefinition
    public private(set) var isArmed = true
    /// Seconds left before a triggered trap fires, when it has a delay.
    public private(set) var countdown: Double?
    /// Zone triggers fire on entry, so we remember whether the player was inside last step.
    private var playerWasInside = false

    public init(definition: TrapDefinition) {
        self.definition = definition
    }

    public var id: String { definition.id }

    public var zone: AABB? {
        if case .zone(let rect) = definition.trigger { return rect.aabb }
        return nil
    }

    public var stateHash: Int {
        var h = Hasher()
        h.combine(isArmed)
        h.combine(countdown.map { Int(($0 * 60).rounded()) })
        h.combine(playerWasInside)
        return h.finalize()
    }

    public mutating func update(dt: Double, player: PlayerState, world: inout World, bus: inout EventBus) {
        guard isArmed else { return }

        if let remaining = countdown {
            let left = remaining - dt
            if left <= 1e-9 {
                countdown = nil
                fire(in: &world, bus: &bus)
            } else {
                countdown = left
            }
            return
        }

        guard isTriggered(player: player, world: world, bus: bus) else { return }
        if definition.delay > 0 {
            countdown = definition.delay
        } else {
            fire(in: &world, bus: &bus)
        }
    }

    private mutating func isTriggered(player: PlayerState, world: World, bus: EventBus) -> Bool {
        switch definition.trigger {
        case .zone(let rect):
            let inside = player.bounds.intersects(rect.aabb)
            defer { playerWasInside = inside }
            return inside && !playerWasInside
        case .delay(let seconds):
            return world.time >= seconds - 1e-9
        case .onEvent(let name):
            return bus.didReceive(name)
        }
    }

    public mutating func fire(in world: inout World, bus: inout EventBus) {
        for effect in definition.effects {
            TrapFactory.makeEffect(effect).apply(to: &world, bus: &bus)
        }
        world.noteTrapFired(id)
        bus.emit(EventBus.firedEvent(for: id))
        // Timed triggers only ever fire once; others re-arm when `once` is false.
        if case .delay = definition.trigger {
            isArmed = false
        } else if definition.once {
            isArmed = false
        }
    }
}
