import Foundation

/// A runtime trap. Value type so a whole `Simulation` can be copied cheaply
/// (restart snapshots, the level solver, the ghost replay).
public protocol Trap: Sendable {
    var id: String { get }
    /// False once a one-shot trap has fired.
    var isArmed: Bool { get }
    /// Trigger area, drawn by the debug overlay. `nil` for non-spatial triggers.
    var zone: AABB? { get }
    /// Hash of the mutable state. Used by the solver to detect repeated situations.
    var stateHash: Int { get }

    /// Called every fixed step while the level is running. Fires the trap when its trigger
    /// condition is met.
    mutating func update(dt: Double, player: PlayerState, world: inout World, bus: inout EventBus)

    /// Applies the trap's effects immediately and emits `"<id>.fired"`.
    mutating func fire(in world: inout World, bus: inout EventBus)
}

/// One effect implementation. Add a new effect by adding an `Effect` case, a type
/// conforming to this protocol in `Traps/Effects/`, and one line in `TrapFactory`.
public protocol TrapEffect: Sendable {
    func apply(to world: inout World, bus: inout EventBus)
}
