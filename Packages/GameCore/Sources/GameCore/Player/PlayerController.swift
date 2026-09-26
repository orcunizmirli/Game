import Foundation

/// Anything the player can collide with.
public protocol CollisionProvider {
    /// Solid boxes that might overlap `region`. May return extra boxes; callers filter.
    func solids(in region: AABB) -> [AABB]
}

/// What happened during one controller step. Used for sounds, particles and tests.
public struct StepReport: Equatable, Sendable {
    public var jumped = false
    public var landed = false
    public var bumpedHead = false
    public var hitWall = false

    public init() {}
}

/// Deterministic platformer controller.
///
/// No physics engine: velocity is integrated by hand and collisions are resolved one axis
/// at a time (X first, then Y) against axis aligned boxes. Independent of SpriteKit so it
/// can be unit tested and used by the headless level solver.
public struct PlayerController: Sendable {
    public var tuning: PhysicsTuning

    public init(tuning: PhysicsTuning = .standard) {
        self.tuning = tuning
    }

    @discardableResult
    public func step(_ s: inout PlayerState, input: InputState, dt: Double, world: CollisionProvider) -> StepReport {
        var report = StepReport()
        let t = tuning
        let wasGrounded = s.isGrounded

        // Horizontal velocity.
        let dir = input.horizontal
        if dir != 0 { s.facing = dir > 0 ? 1 : -1 }
        let accel: Double
        if dir != 0 {
            accel = s.isGrounded ? t.groundAccel : t.airAccel
        } else {
            accel = s.isGrounded ? t.friction : t.airFriction
        }
        s.velocity.x = approach(s.velocity.x, dir * t.runSpeed, accel * dt)

        // Coyote time and jump buffer.
        if s.isGrounded {
            s.coyoteTimer = t.coyoteTime
        } else {
            s.coyoteTimer = max(0, s.coyoteTimer - dt)
        }
        if input.jumpPressed {
            s.jumpBufferTimer = t.jumpBufferTime
        } else {
            s.jumpBufferTimer = max(0, s.jumpBufferTimer - dt)
        }

        // Jump.
        if s.jumpBufferTimer > 0 && s.coyoteTimer > 0 {
            s.velocity.y = t.jumpVelocity
            s.jumpBufferTimer = 0
            s.coyoteTimer = 0
            s.isGrounded = false
            s.isJumpRising = true
            report.jumped = true
        }

        // Variable jump height: releasing early cuts the upward speed once.
        if s.isJumpRising {
            if s.velocity.y <= 0 {
                s.isJumpRising = false
            } else if !input.jumpHeld {
                s.velocity.y *= t.jumpCutMultiplier
                s.isJumpRising = false
            }
        }

        // Gravity.
        s.velocity.y = max(s.velocity.y - t.gravity * dt, -t.maxFallSpeed)

        // Integrate and resolve, one axis at a time.
        if Self.moveX(&s, by: s.velocity.x * dt, world: world) {
            s.velocity.x = 0
            report.hitWall = true
        }
        let hit = Self.moveY(&s, by: s.velocity.y * dt, world: world)
        switch hit {
        case .floor:
            s.velocity.y = 0
            s.isGrounded = true
            s.isJumpRising = false
        case .ceiling:
            s.velocity.y = 0
            s.isGrounded = false
            s.isJumpRising = false
            report.bumpedHead = true
        case .none:
            s.isGrounded = false
        }
        report.landed = s.isGrounded && !wasGrounded
        return report
    }

    /// Moves horizontally and pushes out of any solid entered. Returns true on contact.
    @discardableResult
    public static func moveX(_ s: inout PlayerState, by dx: Double, world: CollisionProvider) -> Bool {
        guard dx != 0 else { return false }
        s.position.x += dx
        let box = s.bounds
        var hit = false
        for solid in world.solids(in: box) where box.intersects(solid) {
            if dx > 0 {
                s.position.x = min(s.position.x, solid.minX - s.size.x / 2)
            } else {
                s.position.x = max(s.position.x, solid.maxX + s.size.x / 2)
            }
            hit = true
        }
        return hit
    }

    public enum VerticalHit: Sendable { case none, floor, ceiling }

    /// Moves vertically and pushes out of any solid entered.
    @discardableResult
    public static func moveY(_ s: inout PlayerState, by dy: Double, world: CollisionProvider) -> VerticalHit {
        guard dy != 0 else { return .none }
        s.position.y += dy
        let box = s.bounds
        var hit = VerticalHit.none
        for solid in world.solids(in: box) where box.intersects(solid) {
            if dy < 0 {
                s.position.y = max(s.position.y, solid.maxY)
                hit = .floor
            } else {
                s.position.y = min(s.position.y, solid.minY - s.size.y)
                hit = .ceiling
            }
        }
        return hit
    }
}
