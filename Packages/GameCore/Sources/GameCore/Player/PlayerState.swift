import Foundation

/// Everything the simulation knows about the player. Pure value type.
public struct PlayerState: Equatable, Hashable, Sendable {
    /// Bottom-center of the hitbox (the feet), in tiles.
    public var position: Vec2
    /// Tiles per second.
    public var velocity: Vec2 = .zero
    /// Hitbox width and height in tiles.
    public var size: Vec2
    public var isGrounded = false
    /// -1 facing left, +1 facing right.
    public var facing = 1
    /// Remaining coyote time (jump still allowed after leaving a ledge).
    public var coyoteTimer: Double = 0
    /// Remaining buffered-jump time (jump pressed shortly before landing).
    public var jumpBufferTimer: Double = 0
    /// True from takeoff until the jump is cut or reaches its apex; enables variable height.
    public var isJumpRising = false

    public init(position: Vec2, size: Vec2 = PhysicsTuning.standard.playerSize) {
        self.position = position
        self.size = size
    }

    public var bounds: AABB {
        AABB(minX: position.x - size.x / 2, minY: position.y,
             maxX: position.x + size.x / 2, maxY: position.y + size.y)
    }

    public var center: Vec2 { Vec2(position.x, position.y + size.y / 2) }
}
