import Foundation

/// 2D vector in tile units. Pure value type; the simulation never touches CoreGraphics
/// so it builds and tests on any platform.
public struct Vec2: Equatable, Hashable, Codable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static func += (a: inout Vec2, b: Vec2) { a = a + b }

    public var length: Double { (x * x + y * y).squareRoot() }

    public var description: String { "(\(x), \(y))" }

    // Encoded as a two element array: [x, y]
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        y = try c.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
    }
}

/// Integer tile coordinate. (0,0) is the bottom-left tile of a level.
/// Encoded in JSON as `[x, y]`.
public struct GridPoint: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public var x: Int
    public var y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    public static func < (a: GridPoint, b: GridPoint) -> Bool {
        a.y != b.y ? a.y < b.y : a.x < b.x
    }

    public var description: String { "[\(x),\(y)]" }

    /// The full tile box.
    public var bounds: AABB { AABB(x: Double(x), y: Double(y), width: 1, height: 1) }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Int.self)
        y = try c.decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
    }
}

/// Axis aligned bounding box in tile units.
public struct AABB: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    /// Overlaps smaller than this are treated as touching, not intersecting.
    public static let epsilon = 1e-9

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(minX: x, minY: y, maxX: x + width, maxY: y + height)
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var midX: Double { (minX + maxX) / 2 }
    public var midY: Double { (minY + maxY) / 2 }
    public var center: Vec2 { Vec2(midX, midY) }

    /// Strict overlap test: boxes that only share an edge do not intersect.
    public func intersects(_ o: AABB) -> Bool {
        minX < o.maxX - Self.epsilon && maxX > o.minX + Self.epsilon &&
            minY < o.maxY - Self.epsilon && maxY > o.minY + Self.epsilon
    }

    /// Like `intersects` but also true when the boxes touch (within `margin`).
    public func touches(_ o: AABB, margin: Double = 0.01) -> Bool {
        insetBy(dx: -margin, dy: -margin).intersects(o)
    }

    public func contains(_ p: Vec2) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }

    public func insetBy(dx: Double, dy: Double) -> AABB {
        AABB(minX: minX + dx, minY: minY + dy, maxX: maxX - dx, maxY: maxY - dy)
    }

    public func offsetBy(dx: Double, dy: Double) -> AABB {
        AABB(minX: minX + dx, minY: minY + dy, maxX: maxX + dx, maxY: maxY + dy)
    }

    public func union(_ o: AABB) -> AABB {
        AABB(minX: Swift.min(minX, o.minX), minY: Swift.min(minY, o.minY),
             maxX: Swift.max(maxX, o.maxX), maxY: Swift.max(maxY, o.maxY))
    }

    public var description: String { "AABB(\(minX), \(minY) → \(maxX), \(maxY))" }
}

/// A rectangle in tile units, encoded in JSON as `[x, y, width, height]`.
public struct TileRect: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var aabb: AABB { AABB(x: x, y: y, width: width, height: height) }

    /// Every tile whose origin lies inside the rect (for integer rects: exactly its tiles).
    public var gridPoints: [GridPoint] {
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let x1 = Int((x + width).rounded(.up)), y1 = Int((y + height).rounded(.up))
        var points: [GridPoint] = []
        for yy in y0..<max(y0, y1) {
            for xx in x0..<max(x0, x1) {
                points.append(GridPoint(xx, yy))
            }
        }
        return points
    }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        y = try c.decode(Double.self)
        width = try c.decode(Double.self)
        height = try c.decode(Double.self)
        guard width > 0, height > 0 else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "rect needs positive width and height")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
        try c.encode(width)
        try c.encode(height)
    }
}

/// Moves `value` toward `target` by at most `maxDelta`.
@inlinable
public func approach(_ value: Double, _ target: Double, _ maxDelta: Double) -> Double {
    if value < target { return min(value + maxDelta, target) }
    if value > target { return max(value - maxDelta, target) }
    return value
}
