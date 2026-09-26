import Foundation

/// The floor (or anything else) falls away: the tiles are removed instantly.
public struct CollapseEffect: TrapEffect {
    public let tiles: [GridPoint]

    public func apply(to world: inout World, bus: inout EventBus) {
        world.removeTiles(tiles)
    }
}
