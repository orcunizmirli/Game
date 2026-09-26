import Foundation

/// Solid tiles slide by an exact offset (closing walls, platforms that leave), then become
/// static again at their destination. The player is pushed along and can be crushed.
public struct SlideTilesEffect: TrapEffect {
    public let tiles: [GridPoint]
    public let offset: GridPoint
    public let speed: Double

    public func apply(to world: inout World, bus: inout EventBus) {
        let delta = Vec2(Double(offset.x), Double(offset.y))
        let distance = delta.length
        guard distance > 0, speed > 0 else { return }
        world.releaseBlocks(tiles, velocity: delta * (speed / distance), distance: distance)
    }
}
