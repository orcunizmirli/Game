import Foundation

/// Solid tiles detach and fall until they land on something. Anything caught between the
/// falling block and the floor is crushed.
public struct DropCeilingEffect: TrapEffect {
    public let tiles: [GridPoint]
    /// Fall speed in tiles per second.
    public let speed: Double

    public func apply(to world: inout World, bus: inout EventBus) {
        world.releaseBlocks(tiles, velocity: Vec2(0, -speed), distance: nil)
    }
}
