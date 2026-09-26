import Foundation

/// Runs the game: turns frame times into fixed steps, handles death → restart, level
/// completion → next level, and records progress. The SpriteKit scene owns one of these.
public final class GameSession {
    public enum Phase: Equatable, Sendable {
        case playing
        /// Short death effect; the level is rebuilt when it ends.
        case dying(DeathCause, remaining: Double)
        /// Door reached; the next level loads when it ends.
        case completing(remaining: Double)
        /// The last level was completed.
        case finished
    }

    public let catalog: LevelCatalog
    public let progress: ProgressStore
    public var tuning: PhysicsTuning

    public private(set) var levelIndex: Int
    public private(set) var simulation: Simulation
    public private(set) var phase: Phase = .playing
    /// Deaths since this level was entered (the persistent count lives in `progress`).
    public private(set) var deathsThisVisit = 0
    /// Increments every time the simulation is rebuilt. Renderers compare it to know when to
    /// rebuild their node tree.
    public private(set) var generation = 0

    private var timestep = FixedTimestep()
    private var latch = InputLatch()

    public init(catalog: LevelCatalog, progress: ProgressStore, startLevel: Int = 0,
                tuning: PhysicsTuning = .standard) throws {
        self.catalog = catalog
        self.progress = progress
        self.tuning = tuning
        let index = min(max(0, startLevel), max(0, catalog.count - 1))
        self.levelIndex = index
        self.simulation = try Simulation(level: catalog.level(at: index), tuning: tuning)
    }

    public var level: Level { simulation.level }
    public var levelCount: Int { catalog.count }
    public var world: World { simulation.world }
    public var player: PlayerState { simulation.player }

    /// Persistent death count for the current level.
    public var levelDeaths: Int { progress.record(forLevel: level.id).deaths }

    /// Call once per rendered frame.
    @discardableResult
    public func update(frameDelta: Double, input: InputState) -> [GameEvent] {
        latch.submit(input)
        let steps = timestep.advance(by: frameDelta)
        var events: [GameEvent] = []
        for _ in 0..<steps {
            events.append(contentsOf: step(latch.next()))
        }
        return events
    }

    /// Advances exactly one fixed step (used directly by tests).
    @discardableResult
    public func step(_ input: InputState) -> [GameEvent] {
        let dt = Constants.fixedDt
        switch phase {
        case .playing:
            var events = simulation.step(input, dt: dt)
            switch simulation.status {
            case .running:
                break
            case .dead(let cause):
                deathsThisVisit += 1
                progress.recordDeath(levelID: level.id)
                phase = .dying(cause, remaining: Constants.deathDuration)
            case .won:
                progress.recordCompletion(levelIndex: levelIndex, levelID: level.id,
                                          time: simulation.time, levelCount: catalog.count)
                events.append(.levelCompleted(index: levelIndex, deaths: levelDeaths, time: simulation.time))
                phase = .completing(remaining: Constants.levelCompleteDelay)
            }
            return events

        case .dying(let cause, let remaining):
            let left = remaining - dt
            if left > 1e-9 {
                phase = .dying(cause, remaining: left)
                return []
            }
            rebuild()
            return [.respawned]

        case .completing(let remaining):
            let left = remaining - dt
            if left > 1e-9 {
                phase = .completing(remaining: left)
                return []
            }
            if levelIndex + 1 < catalog.count, (try? load(levelIndex: levelIndex + 1)) != nil {
                return [.levelStarted(index: levelIndex)]
            }
            phase = .finished
            return [.gameFinished]

        case .finished:
            return []
        }
    }

    /// Restarts the current level without counting a death.
    public func restart() {
        rebuild()
    }

    /// Jumps to a level.
    public func load(levelIndex index: Int) throws {
        let level = try catalog.level(at: index)
        simulation = try Simulation(level: level, tuning: tuning)
        levelIndex = index
        deathsThisVisit = 0
        resetRuntimeState()
    }

    /// Re-reads every level file from disk and restarts the current level (debug hot reload).
    public func reloadLevels() throws {
        try catalog.reload()
        try load(levelIndex: min(levelIndex, max(0, catalog.count - 1)))
    }

    /// The level is rebuilt from the cached `Level`, never rewound.
    private func rebuild() {
        if let fresh = try? Simulation(level: level, tuning: tuning) {
            simulation = fresh
        }
        resetRuntimeState()
    }

    private func resetRuntimeState() {
        phase = .playing
        generation += 1
        latch.reset()
    }
}
