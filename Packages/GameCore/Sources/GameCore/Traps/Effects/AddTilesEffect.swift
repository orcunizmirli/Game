import Foundation

/// Walls appear out of nowhere.
public struct AddTilesEffect: TrapEffect {
    public let tiles: [GridPoint]

    public func apply(to world: inout World, bus: inout EventBus) {
        world.placeTiles(.solid, at: tiles)
    }
}
