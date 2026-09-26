import Foundation

/// Left becomes right (and vice versa) for a while.
public struct InvertControlsEffect: TrapEffect {
    public let duration: Double

    public func apply(to world: inout World, bus: inout EventBus) {
        world.invertControls(for: duration)
    }
}
