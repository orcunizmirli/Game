import Foundation

/// Named-event channel used to chain traps together.
///
/// Value type so the whole simulation can be copied (used by the level solver). Events
/// emitted during step N are delivered at the end of that step and are visible to
/// `onEvent` triggers during step N+1. The one-step latency (8 ms) keeps chains
/// deterministic and independent of trap ordering.
public struct EventBus: Equatable, Sendable {
    private var pending: [String] = []
    /// Events delivered at the end of the previous step.
    public private(set) var delivered: Set<String> = []
    /// Every event ever delivered, in order. Handy for tests and the debug overlay.
    public private(set) var history: [String] = []

    public init() {}

    public mutating func emit(_ name: String) {
        pending.append(name)
    }

    /// Moves emitted events into `delivered`. Called once at the end of every step.
    public mutating func dispatch() {
        delivered = Set(pending)
        history.append(contentsOf: pending)
        pending.removeAll(keepingCapacity: true)
    }

    public func didReceive(_ name: String) -> Bool {
        delivered.contains(name)
    }

    /// Conventional name of the event a trap emits when it fires.
    public static func firedEvent(for trapID: String) -> String {
        "\(trapID).fired"
    }
}
