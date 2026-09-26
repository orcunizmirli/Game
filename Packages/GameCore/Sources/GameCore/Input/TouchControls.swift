import Foundation

/// Screen layout of the on-screen controls, in any coordinate space whose x grows to
/// the right. The left half of the screen steers (left / right), the right half jumps.
/// Touch areas are much larger than the drawn buttons.
public struct TouchLayout: Equatable, Sendable {
    public enum Zone: Equatable, Hashable, Sendable {
        case left, right, jump
    }

    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// Visual button radius.
    public var buttonRadius: Double { min(46, max(30, height * 0.1)) }
    private var margin: Double { buttonRadius * 0.55 }

    public var leftButtonCenter: Vec2 { Vec2(margin + buttonRadius, margin + buttonRadius) }
    public var rightButtonCenter: Vec2 { Vec2(margin + buttonRadius * 3.6, margin + buttonRadius) }
    public var jumpButtonCenter: Vec2 { Vec2(width - margin - buttonRadius * 1.2, margin + buttonRadius * 1.2) }

    /// Touches left of this x steer left, between it and the middle steer right.
    public var leftRightSplit: Double {
        min((leftButtonCenter.x + rightButtonCenter.x) / 2, width * 0.25)
    }

    public func zone(for point: Vec2) -> Zone {
        if point.x >= width / 2 { return .jump }
        return point.x < leftRightSplit ? .left : .right
    }
}

/// Tracks every active touch and converts them into an `InputState`.
/// Multi-touch: hold right with one thumb and tap jump with the other.
public struct TouchTracker: Sendable {
    private var zones: [Int: TouchLayout.Zone] = [:]
    private var pendingJumpPress = false

    public init() {}

    public mutating func began(id: Int, at point: Vec2, layout: TouchLayout) {
        let zone = layout.zone(for: point)
        zones[id] = zone
        if zone == .jump { pendingJumpPress = true }
    }

    /// A finger sliding between the arrow buttons switches direction; a finger never slides
    /// into or out of the jump zone (that would cause accidental jumps).
    public mutating func moved(id: Int, to point: Vec2, layout: TouchLayout) {
        guard let current = zones[id], current != .jump else { return }
        let zone = layout.zone(for: point)
        zones[id] = zone == .jump ? .right : zone
    }

    public mutating func ended(id: Int) {
        zones[id] = nil
    }

    public mutating func cancelAll() {
        zones.removeAll()
        pendingJumpPress = false
    }

    public var activeZones: Set<TouchLayout.Zone> { Set(zones.values) }

    /// Current input. Consumes the pending jump press.
    public mutating func poll() -> InputState {
        let active = activeZones
        let input = InputState(left: active.contains(.left),
                               right: active.contains(.right),
                               jumpPressed: pendingJumpPress,
                               jumpHeld: active.contains(.jump) || pendingJumpPress)
        pendingJumpPress = false
        return input
    }
}

/// Edge detection for button-style sources (keyboard, gamepad) that only report "held".
public struct ButtonEdge: Sendable {
    private var wasDown = false

    public init() {}

    /// Returns true on the frame the button goes down.
    public mutating func update(isDown: Bool) -> Bool {
        defer { wasDown = isDown }
        return isDown && !wasDown
    }
}
