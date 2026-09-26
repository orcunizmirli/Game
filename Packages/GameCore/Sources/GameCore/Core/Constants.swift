import Foundation

/// Global simulation constants.
public enum Constants {
    /// Fixed simulation step. The game always simulates at 120 Hz regardless of display rate,
    /// so jump height and timing are identical on 60 Hz and ProMotion screens.
    public static let fixedDt: Double = 1.0 / 120.0
    /// Spiral-of-death guard: never run more than this many steps for one rendered frame.
    public static let maxStepsPerFrame = 5
    /// Length of the death effect before the level is rebuilt (seconds).
    public static let deathDuration: Double = 0.15
    /// Pause after touching the door before the next level loads (seconds).
    public static let levelCompleteDelay: Double = 0.6
    /// The player dies once their head drops this far below the bottom of the level (tiles).
    public static let killPlaneDepth: Double = 1.0
    /// Default door slide speed for `moveDoor` (tiles per second).
    public static let defaultDoorSpeed: Double = 14
}

/// Character controller tuning. All distances are in tiles, times in seconds.
/// Tweak freely: nothing else in the code base hard-codes these numbers.
public struct PhysicsTuning: Equatable, Sendable {
    /// Top horizontal speed (tiles/s).
    public var runSpeed: Double = 7.5
    /// Horizontal acceleration while grounded and holding a direction (tiles/s²).
    public var groundAccel: Double = 90
    /// Horizontal acceleration while airborne and holding a direction (tiles/s²).
    public var airAccel: Double = 60
    /// Deceleration on the ground with no input (tiles/s²).
    public var friction: Double = 85
    /// Deceleration in the air with no input (tiles/s²).
    public var airFriction: Double = 25
    /// Downward acceleration (tiles/s²).
    public var gravity: Double = 72
    /// Terminal fall speed (tiles/s).
    public var maxFallSpeed: Double = 24
    /// Initial upward speed of a jump (tiles/s). Peak height ≈ v² / 2g ≈ 2.9 tiles.
    public var jumpVelocity: Double = 20.5
    /// Grace period after walking off a ledge during which a jump still works.
    public var coyoteTime: Double = 0.08
    /// A jump pressed this long before landing is still executed on touchdown.
    public var jumpBufferTime: Double = 0.10
    /// Upward speed multiplier applied once when the jump button is released early.
    public var jumpCutMultiplier: Double = 0.45
    /// Player hitbox size (tiles).
    public var playerSize = Vec2(0.7, 0.9)

    public init() {}

    public static let standard = PhysicsTuning()

    /// Apex height of a full jump in tiles (ignoring the discrete step).
    public var fullJumpHeight: Double { jumpVelocity * jumpVelocity / (2 * gravity) }
}
