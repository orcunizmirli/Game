import Foundation

/// Mutable tile map. (0,0) is the bottom-left tile; y grows upward.
///
/// Outside the grid, columns left of 0 and right of `width - 1` are solid walls (so the
/// player can never leave the screen sideways) while everything below row 0 or above the
/// top row is empty (falling out of the bottom kills you).
public struct TileGrid: Equatable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    private var tiles: [TileKind]
    /// Increments on every change so renderers can cheaply detect edits.
    public private(set) var revision = 0

    public init(width: Int, height: Int, fill: TileKind = .empty) {
        precondition(width > 0 && height > 0)
        self.width = width
        self.height = height
        self.tiles = Array(repeating: fill, count: width * height)
    }

    public func contains(_ p: GridPoint) -> Bool {
        p.x >= 0 && p.x < width && p.y >= 0 && p.y < height
    }

    public subscript(x: Int, y: Int) -> TileKind {
        if x < 0 || x >= width { return .solid }
        if y < 0 || y >= height { return .empty }
        return tiles[y * width + x]
    }

    public subscript(p: GridPoint) -> TileKind {
        self[p.x, p.y]
    }

    /// Sets a tile. Returns false (and does nothing) for points outside the grid.
    @discardableResult
    public mutating func set(_ kind: TileKind, at p: GridPoint) -> Bool {
        guard contains(p) else { return false }
        let i = p.y * width + p.x
        guard tiles[i] != kind else { return true }
        tiles[i] = kind
        revision &+= 1
        return true
    }

    /// Tile coordinates covered by `region` (inclusive of partially covered tiles).
    public func tileRange(covering region: AABB) -> (xs: ClosedRange<Int>, ys: ClosedRange<Int>) {
        let x0 = Int(region.minX.rounded(.down)), x1 = Int(region.maxX.rounded(.down))
        let y0 = Int(region.minY.rounded(.down)), y1 = Int(region.maxY.rounded(.down))
        return (x0...max(x0, x1), y0...max(y0, y1))
    }

    public func solids(in region: AABB) -> [AABB] {
        let r = tileRange(covering: region)
        var boxes: [AABB] = []
        for y in r.ys {
            for x in r.xs where self[x, y].isSolid {
                boxes.append(AABB(x: Double(x), y: Double(y), width: 1, height: 1))
            }
        }
        return boxes
    }

    /// Deadly boxes (spikes) that might overlap `region`.
    public func hazards(in region: AABB) -> [AABB] {
        let r = tileRange(covering: region)
        var boxes: [AABB] = []
        for y in r.ys {
            for x in r.xs {
                if let box = self[x, y].hazardBounds(at: GridPoint(x, y)) {
                    boxes.append(box)
                }
            }
        }
        return boxes
    }

    /// All in-bounds points, row by row from the bottom.
    public var points: [GridPoint] {
        var result: [GridPoint] = []
        result.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                result.append(GridPoint(x, y))
            }
        }
        return result
    }

    /// ASCII rendering, top row first (same orientation as level JSON).
    public func rows() -> [String] {
        (0..<height).reversed().map { y in
            String((0..<width).map { x in GridSymbol.character(for: self[x, y]) })
        }
    }
}
