import Foundation

/// The exit runs away to another tile.
public struct MoveDoorEffect: TrapEffect {
    public let target: GridPoint
    /// Tiles per second; 0 teleports.
    public let speed: Double

    public func apply(to world: inout World, bus: inout EventBus) {
        world.moveDoor(to: Vec2(Double(target.x), Double(target.y)), speed: speed)
    }
}
