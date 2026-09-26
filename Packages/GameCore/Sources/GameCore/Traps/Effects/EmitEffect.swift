import Foundation

/// Emits a custom event so several traps can react to one trigger.
public struct EmitEffect: TrapEffect {
    public let event: String

    public func apply(to world: inout World, bus: inout EventBus) {
        bus.emit(event)
    }
}
