import Foundation

public enum DeathCause: String, Equatable, Hashable, Sendable {
    case spikes, crushed, fell
}

/// Everything a renderer, HUD or sound system may want to react to.
public enum GameEvent: Equatable, Sendable {
    case world(WorldEvent)
    case jumped
    case landed
    case bumpedHead
    case died(DeathCause, at: Vec2)
    case reachedDoor
    /// The level was rebuilt after a death or a manual restart.
    case respawned
    case levelStarted(index: Int)
    case levelCompleted(index: Int, deaths: Int, time: Double)
    case gameFinished
}

/// One attempt at one level: world + player + traps, advanced in fixed steps.
///
/// A value type. Copying it snapshots the entire game state, which the level solver and
/// the ghost replay rely on. It knows nothing about rendering, timing or persistence.
public struct Simulation: Sendable {
    public enum Status: Equatable, Sendable {
        case running
        case dead(DeathCause)
        case won
    }

    public let level: Level
    public var controller: PlayerController
    public private(set) var world: World
    public private(set) var player: PlayerState
    public private(set) var traps: [any Trap]
    public private(set) var bus = EventBus()
    public private(set) var status: Status = .running
    public private(set) var stepCount = 0

    public init(level: Level, tuning: PhysicsTuning = .standard) throws {
        self.level = level
        self.controller = PlayerController(tuning: tuning)
        self.world = try WorldBuilder.build(level)
        self.player = PlayerState(position: world.spawn, size: tuning.playerSize)
        self.traps = TrapFactory.makeAll(level.traps)
    }

    public var time: Double { world.time }

    public var isRunning: Bool { status == .running }

    /// Advances one fixed step.
    @discardableResult
    public mutating func step(_ input: InputState, dt: Double = Constants.fixedDt) -> [GameEvent] {
        guard status == .running else { return [] }
        stepCount += 1
        var events: [GameEvent] = []

        let effectiveInput = world.controlsInverted ? input.mirrored : input
        let report = controller.step(&player, input: effectiveInput, dt: dt, world: world)
        if report.jumped { events.append(.jumped) }
        if report.landed { events.append(.landed) }
        if report.bumpedHead { events.append(.bumpedHead) }

        world.revealHidden(touching: player.bounds)
        let crushed = world.update(dt: dt, player: &player)

        for i in traps.indices {
            traps[i].update(dt: dt, player: player, world: &world, bus: &bus)
        }
        bus.dispatch()
        events.append(contentsOf: world.drainEvents().map(GameEvent.world))

        let box = player.bounds
        if crushed || world.isEmbedded(box) {
            status = .dead(.crushed)
        } else if world.touchesHazard(box) {
            status = .dead(.spikes)
        } else if box.maxY < -Constants.killPlaneDepth {
            status = .dead(.fell)
        } else if world.reachedDoor(box) {
            status = .won
            events.append(.reachedDoor)
        }
        if case .dead(let cause) = status {
            events.append(.died(cause, at: player.center))
        }
        return events
    }

    /// Compact fingerprint of the dynamic state (for the solver's duplicate detection).
    public func stateKey(positionResolution: Double = 16, velocityResolution: Double = 1, timeResolution: Double = 8, includeTime: Bool) -> Int {
        var h = Hasher()
        h.combine(Int((player.position.x * positionResolution).rounded()))
        h.combine(Int((player.position.y * positionResolution).rounded()))
        h.combine(Int((player.velocity.x * velocityResolution).rounded()))
        h.combine(Int((player.velocity.y * velocityResolution / 2).rounded()))
        h.combine(player.isGrounded)
        h.combine(player.isJumpRising)
        h.combine(player.coyoteTimer > 0)
        for trap in traps { h.combine(trap.stateHash) }
        h.combine(Int((world.door.position.x * 2).rounded()))
        h.combine(Int((world.door.position.y * 2).rounded()))
        h.combine(world.grid.revision)
        h.combine(world.blocks.count)
        for b in world.blocks {
            h.combine(Int((b.position.x * 2).rounded()))
            h.combine(Int((b.position.y * 2).rounded()))
        }
        h.combine(world.controlsInverted)
        if includeTime { h.combine(Int((world.time * timeResolution).rounded())) }
        return h.finalize()
    }
}
