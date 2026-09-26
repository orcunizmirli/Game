import Foundation

/// Spikes pop out of the given tiles. They are deadly on the same step.
public struct SpawnSpikesEffect: TrapEffect {
    public let tiles: [GridPoint]
    public let direction: SpikeDirection

    public func apply(to world: inout World, bus: inout EventBus) {
        world.placeTiles(.spike(direction), at: tiles)
    }
}
