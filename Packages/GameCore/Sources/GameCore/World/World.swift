import Foundation

/// The level exit.
public struct Door: Equatable, Hashable, Sendable {
    /// Bottom-left corner in tiles. Continuous because the door can slide.
    public var position: Vec2
    public var target: Vec2
    /// Slide speed in tiles per second.
    public var speed: Double

    public init(position: Vec2) {
        self.position = position
        self.target = position
        self.speed = Constants.defaultDoorSpeed
    }

    public var isMoving: Bool { position != target }

    public var bounds: AABB { AABB(x: position.x, y: position.y, width: 1, height: 1) }

    /// The player must overlap this to finish the level.
    public var goalBounds: AABB { bounds.insetBy(dx: 0.3, dy: 0.15) }
}

/// A tile that has come loose (falling ceiling, sliding wall).
public struct MovingBlock: Equatable, Hashable, Sendable {
    public let id: Int
    /// What the block becomes when it settles.
    public let kind: TileKind
    /// Where it started, so renderers can reuse the tile's node.
    public let origin: GridPoint
    /// Bottom-left corner in tiles.
    public var position: Vec2
    public var velocity: Vec2
    /// Distance left to travel; `nil` means "until it hits something".
    public var remaining: Double?

    public var bounds: AABB { AABB(x: position.x, y: position.y, width: 1, height: 1) }
}

/// Things that happened in the world during a step. Consumed by renderers for effects.
public enum WorldEvent: Equatable, Hashable, Sendable {
    case trapFired(String)
    case tilesRemoved([GridPoint])
    case tilesAdded([GridPoint])
    case spikesSpawned([GridPoint])
    case tileRevealed(GridPoint)
    case blocksReleased([Int])
    case blockSettled(id: Int, at: GridPoint)
    case blockLost(id: Int)
    case doorMoving(to: Vec2)
    case controlsInverted(duration: Double)
}

/// Mutable runtime state of a level: tiles, door, moving blocks, timers.
///
/// Built from a `Level` by `WorldBuilder`; never saved or rewound. Restarting a level
/// throws the world away and builds a fresh one.
public struct World: Equatable, Hashable, Sendable, CollisionProvider {
    public let levelID: String
    public private(set) var grid: TileGrid
    public private(set) var door: Door
    /// Feet position where the player appears.
    public let spawn: Vec2
    public private(set) var blocks: [MovingBlock] = []
    /// Seconds since the level (re)started.
    public private(set) var time: Double = 0
    public private(set) var controlsInvertedUntil: Double = -1
    /// Events produced since the last `drainEvents()`.
    public private(set) var events: [WorldEvent] = []
    private var nextBlockID = 1

    public init(levelID: String, grid: TileGrid, spawn: Vec2, door: Door) {
        self.levelID = levelID
        self.grid = grid
        self.spawn = spawn
        self.door = door
    }

    public var controlsInverted: Bool { time < controlsInvertedUntil }

    public var controlsInvertedRemaining: Double { max(0, controlsInvertedUntil - time) }

    // MARK: Queries

    public func solids(in region: AABB) -> [AABB] {
        var boxes = grid.solids(in: region)
        for block in blocks where block.bounds.intersects(region.insetBy(dx: -0.5, dy: -0.5)) {
            boxes.append(block.bounds)
        }
        return boxes
    }

    /// True when `box` overlaps any solid (tile or moving block).
    public func isEmbedded(_ box: AABB) -> Bool {
        solids(in: box).contains { $0.intersects(box) }
    }

    public func touchesHazard(_ box: AABB) -> Bool {
        grid.hazards(in: box).contains { $0.intersects(box) }
    }

    public func reachedDoor(_ box: AABB) -> Bool {
        door.goalBounds.intersects(box)
    }

    // MARK: Mutations used by trap effects

    public mutating func removeTiles(_ points: [GridPoint]) {
        var removed: [GridPoint] = []
        for p in points where grid.contains(p) && grid[p] != .empty {
            grid.set(.empty, at: p)
            removed.append(p)
        }
        if !removed.isEmpty { events.append(.tilesRemoved(removed)) }
    }

    public mutating func placeTiles(_ kind: TileKind, at points: [GridPoint]) {
        var placed: [GridPoint] = []
        for p in points where grid.contains(p) && grid[p] != kind {
            grid.set(kind, at: p)
            placed.append(p)
        }
        guard !placed.isEmpty else { return }
        events.append(kind.isHazard ? .spikesSpawned(placed) : .tilesAdded(placed))
    }

    public mutating func moveDoor(to target: Vec2, speed: Double) {
        door.target = target
        door.speed = speed
        if speed <= 0 { door.position = target }
        events.append(.doorMoving(to: target))
    }

    /// Detaches the given solid tiles into moving blocks.
    public mutating func releaseBlocks(_ points: [GridPoint], velocity: Vec2, distance: Double?) {
        var ids: [Int] = []
        for p in points where grid.contains(p) && grid[p] != .empty && !grid[p].isHazard {
            let kind: TileKind = grid[p] == .fake ? .fake : .solid
            grid.set(.empty, at: p)
            blocks.append(MovingBlock(id: nextBlockID, kind: kind, origin: p,
                                      position: Vec2(Double(p.x), Double(p.y)),
                                      velocity: velocity, remaining: distance))
            ids.append(nextBlockID)
            nextBlockID += 1
        }
        if !ids.isEmpty { events.append(.blocksReleased(ids)) }
    }

    public mutating func invertControls(for duration: Double) {
        controlsInvertedUntil = max(controlsInvertedUntil, time + duration)
        events.append(.controlsInverted(duration: duration))
    }

    public mutating func noteTrapFired(_ id: String) {
        events.append(.trapFired(id))
    }

    /// Hidden blocks become visible once the player touches them.
    public mutating func revealHidden(touching box: AABB) {
        let area = box.insetBy(dx: -0.02, dy: -0.02)
        let range = grid.tileRange(covering: area)
        for y in range.ys {
            for x in range.xs {
                let p = GridPoint(x, y)
                if grid[p] == .hidden && p.bounds.intersects(area) {
                    grid.set(.revealed, at: p)
                    events.append(.tileRevealed(p))
                }
            }
        }
    }

    public mutating func drainEvents() -> [WorldEvent] {
        defer { events.removeAll(keepingCapacity: true) }
        return events
    }

    // MARK: Simulation

    /// Advances time, the door and moving blocks by `dt`. Moving blocks push the player;
    /// returns true if the player got squeezed between a block and something solid.
    public mutating func update(dt: Double, player: inout PlayerState) -> Bool {
        time += dt
        updateDoor(dt: dt)
        return updateBlocks(dt: dt, player: &player)
    }

    private mutating func updateDoor(dt: Double) {
        guard door.isMoving else { return }
        let delta = door.target - door.position
        let length = delta.length
        let stepLength = door.speed * dt
        if length <= stepLength {
            door.position = door.target
        } else {
            door.position += delta * (stepLength / length)
        }
    }

    private mutating func updateBlocks(dt: Double, player: inout PlayerState) -> Bool {
        guard !blocks.isEmpty else { return false }
        var crushed = false
        var i = 0
        while i < blocks.count {
            var block = blocks[i]
            let before = block.bounds
            var delta = block.velocity * dt
            var finished = false

            if let remaining = block.remaining {
                let length = delta.length
                if length >= remaining - 1e-9 {
                    delta = length > 0 ? delta * (remaining / length) : .zero
                    block.remaining = 0
                    finished = true
                } else {
                    block.remaining = remaining - length
                }
            }
            block.position += delta

            if block.remaining == nil {
                // Falls until it hits the static grid.
                let hits = grid.solids(in: block.bounds).filter { $0.intersects(block.bounds) }
                if !hits.isEmpty {
                    if delta.y < 0 { block.position.y = hits.map(\.maxY).max()! }
                    if delta.y > 0 { block.position.y = hits.map(\.minY).min()! - 1 }
                    if delta.x > 0 { block.position.x = hits.map(\.minX).min()! - 1 }
                    if delta.x < 0 { block.position.x = hits.map(\.maxX).max()! }
                    finished = true
                }
            }
            blocks[i] = block

            // Carry a player standing on a block that slides sideways.
            let standingOnTop = player.isGrounded && abs(player.position.y - before.maxY) < 1e-6 &&
                player.bounds.maxX > before.minX + AABB.epsilon && player.bounds.minX < before.maxX - AABB.epsilon
            if standingOnTop && delta.x != 0 {
                PlayerController.moveX(&player, by: delta.x, world: self)
            }

            if block.bounds.intersects(player.bounds) {
                push(&player, outOf: block.bounds, movingBy: delta, velocity: block.velocity)
                if isEmbedded(player.bounds) { crushed = true }
            }

            if finished {
                settle(block)
                blocks.remove(at: i)
            } else if block.position.y < -4 || block.position.x < -4 || block.position.x > Double(grid.width) + 4 {
                events.append(.blockLost(id: block.id))
                blocks.remove(at: i)
            } else {
                i += 1
            }
        }
        return crushed
    }

    /// Pushes the player out of a moving block along its direction of travel. For a falling
    /// block that only clips the player's side, the player is nudged sideways instead of
    /// being crushed (feels much fairer).
    private func push(_ player: inout PlayerState, outOf box: AABB, movingBy delta: Vec2, velocity: Vec2) {
        let pb = player.bounds
        if delta.y != 0 {
            let overlapX = min(pb.maxX, box.maxX) - max(pb.minX, box.minX)
            if overlapX < 0.3 {
                if pb.midX < box.midX {
                    player.position.x = box.minX - player.size.x / 2
                } else {
                    player.position.x = box.maxX + player.size.x / 2
                }
                return
            }
            if delta.y < 0 {
                player.position.y = box.minY - player.size.y
                player.velocity.y = min(player.velocity.y, velocity.y)
            } else {
                player.position.y = box.maxY
                player.velocity.y = max(player.velocity.y, 0)
                player.isGrounded = true
            }
        }
        if delta.x > 0 {
            player.position.x = box.maxX + player.size.x / 2
        } else if delta.x < 0 {
            player.position.x = box.minX - player.size.x / 2
        }
    }

    private mutating func settle(_ block: MovingBlock) {
        let p = GridPoint(Int(block.position.x.rounded()), Int(block.position.y.rounded()))
        if grid.contains(p) {
            grid.set(block.kind, at: p)
            events.append(.blockSettled(id: block.id, at: p))
        } else {
            events.append(.blockLost(id: block.id))
        }
    }
}
