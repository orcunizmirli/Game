import Foundation

/// The complete player intent for one simulation step. Touch controls, gamepads and the
/// keyboard all produce one of these; the controller only ever reads this struct.
public struct InputState: Equatable, Hashable, Sendable {
    public var left: Bool
    public var right: Bool
    /// True on the step the jump button went down (edge).
    public var jumpPressed: Bool
    /// True while the jump button is held (level).
    public var jumpHeld: Bool

    public init(left: Bool = false, right: Bool = false, jumpPressed: Bool = false, jumpHeld: Bool = false) {
        self.left = left
        self.right = right
        self.jumpPressed = jumpPressed
        self.jumpHeld = jumpHeld
    }

    public static let none = InputState()

    /// -1, 0 or +1. Pressing both directions cancels out.
    public var horizontal: Double {
        (right ? 1 : 0) - (left ? 1 : 0)
    }

    /// Left and right swapped (used by the invert-controls trap).
    public var mirrored: InputState {
        InputState(left: right, right: left, jumpPressed: jumpPressed, jumpHeld: jumpHeld)
    }

    /// Logical OR of two input sources.
    public func merged(with other: InputState) -> InputState {
        InputState(left: left || other.left,
                   right: right || other.right,
                   jumpPressed: jumpPressed || other.jumpPressed,
                   jumpHeld: jumpHeld || other.jumpHeld)
    }
}

/// Turns a stream of per-frame inputs into per-step inputs without losing jump presses.
///
/// A frame may run zero, one or several fixed steps. A jump press that arrives on a frame
/// with zero steps must survive until the next step, and a press must only be seen by
/// the first step of a multi-step frame.
public struct InputLatch: Equatable, Sendable {
    private var pendingPress = false
    private var current = InputState.none

    public init() {}

    /// Records the input sampled this frame.
    public mutating func submit(_ input: InputState) {
        current = input
        if input.jumpPressed { pendingPress = true }
    }

    /// Input for the next fixed step. Consumes a pending jump press.
    public mutating func next() -> InputState {
        var input = current
        input.jumpPressed = pendingPress
        pendingPress = false
        return input
    }

    public mutating func reset() {
        pendingPress = false
        current = .none
    }
}
