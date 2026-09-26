import Foundation

/// Headless best-first search that finds an input sequence completing a level.
///
/// Used by `levelcheck solve` to prove every level is beatable and to record the
/// solutions that the tests replay and the in-game hint ("ghost") shows.
public struct LevelSolver {
    public struct Options: Sendable {
        /// Fixed steps per search action (6 steps = 50 ms).
        public var stepsPerAction = 6
        /// Give up after expanding this many states.
        public var maxExpansions = 1_500_000
        /// > 1 favours getting closer to the door over short solutions.
        public var heuristicWeight = 1.6
        /// Hard cap on solution length in seconds.
        public var maxTime: Double = 90
        /// Duplicate detection grid: states closer than 1/positionResolution tiles (and
        /// with similar velocity) count as the same. Coarser = faster but less precise.
        public var positionResolution: Double = 8
        public var velocityResolution: Double = 0.5

        public init() {}
    }

    public struct Result {
        public var replay: InputReplay?
        public var expansions: Int
        public var solved: Bool { replay != nil }
    }

    private struct Action {
        var direction: Int
        var jump: InputReplay.Jump
        /// Number of fixed steps; `nil` means the default action length.
        var steps: Int?
    }

    private struct Node {
        var sim: Simulation
        var parent: Int
        var action: Action?
        var cost: Double
    }

    public let options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    public func solve(_ level: Level, tuning: PhysicsTuning = .standard) throws -> Result {
        let start = try Simulation(level: level, tuning: tuning)
        var nodes: [Node] = [Node(sim: start, parent: -1, action: nil, cost: 0)]
        var heap = MinHeap()
        var seen = Set<Int>()
        var maps: [Int: NavigationMap] = [:]
        // Tiles some trap can move or remove: the navigation map lets you walk through them.
        var movable = Set<GridPoint>()
        for trap in level.traps {
            for effect in trap.effects {
                switch effect {
                case .collapse(let tiles), .dropCeiling(let tiles, _), .slideTiles(let tiles, _, _):
                    movable.formUnion(tiles)
                default:
                    break
                }
            }
        }
        func heuristic(_ sim: Simulation) -> Double {
            var h = Hasher()
            h.combine(sim.world.grid.revision)
            let door = sim.world.door.target
            h.combine(Int(door.x.rounded()))
            h.combine(Int(door.y.rounded()))
            let key = h.finalize()
            if maps[key] == nil {
                maps[key] = NavigationMap(grid: sim.world.grid, door: sim.world.door, movable: movable, tuning: tuning)
            }
            return maps[key]!.estimate(from: sim.player)
        }
        func key(_ sim: Simulation) -> Int {
            sim.stateKey(positionResolution: options.positionResolution,
                         velocityResolution: options.velocityResolution, includeTime: false)
        }
        heap.push(priority: heuristic(start), value: 0)
        seen.insert(key(start))
        var expansions = 0

        while let (_, index) = heap.pop() {
            expansions += 1
            if expansions > options.maxExpansions { break }
            let node = nodes[index]
            if node.cost > options.maxTime { continue }

            for var action in actions(for: node.sim, level: level) {
                var sim = node.sim
                var steps = action.steps ?? options.stepsPerAction
                if action.steps == -1 {
                    // Wait until the world changes (at most 10 s).
                    let before = signature(sim)
                    steps = 0
                    while steps < 1200 && sim.isRunning {
                        sim.step(.none)
                        steps += 1
                        if steps >= options.stepsPerAction && signature(sim) != before { break }
                    }
                    action.steps = steps
                } else {
                    for i in 0..<steps {
                        let input = InputState(left: action.direction < 0, right: action.direction > 0,
                                               jumpPressed: action.jump == .pressed && i == 0,
                                               jumpHeld: action.jump != .none)
                        sim.step(input)
                        if !sim.isRunning { break }
                    }
                }
                // Waiting is priced low so that levels built around patience don't make the
                // search explore every other position first. (Costs only steer the search.)
                let cost = node.cost + Double(steps) * Constants.fixedDt * (action.steps == nil ? 1 : waitCostFactor(action))
                switch sim.status {
                case .dead:
                    continue
                case .won:
                    nodes.append(Node(sim: sim, parent: index, action: action, cost: cost))
                    return Result(replay: reconstruct(nodes, from: nodes.count - 1), expansions: expansions)
                case .running:
                    guard seen.insert(key(sim)).inserted else { continue }
                    nodes.append(Node(sim: sim, parent: index, action: action, cost: cost))
                    heap.push(priority: cost + options.heuristicWeight * heuristic(sim),
                              value: nodes.count - 1)
                }
            }
        }
        return Result(replay: nil, expansions: expansions)
    }

    /// Time is not part of the search state (that would explode it), so waiting is an
    /// explicit action: stand still until something changes — a timed trap fires, a block
    /// lands, the controls flip back or the door stops moving.
    private func hasPendingChange(_ sim: Simulation, level: Level) -> Bool {
        if sim.world.controlsInverted || !sim.world.blocks.isEmpty || sim.world.door.isMoving { return true }
        for (i, trap) in sim.traps.enumerated() where trap.isArmed && i < level.traps.count {
            if case .delay = level.traps[i].trigger { return true }
            if let t = trap as? TriggeredTrap, t.countdown != nil { return true }
        }
        return false
    }

    private func waitCostFactor(_ action: Action) -> Double {
        action.direction == 0 && action.jump == .none && (action.steps ?? 0) > options.stepsPerAction ? 0.2 : 1
    }

    private func signature(_ sim: Simulation) -> Int {
        var h = Hasher()
        h.combine(sim.world.grid.revision)
        h.combine(sim.world.blocks.count)
        h.combine(sim.world.controlsInverted)
        h.combine(sim.world.door.isMoving)
        for trap in sim.traps { h.combine(trap.isArmed) }
        return h.finalize()
    }

    /// Only branch on jump choices that can matter, to keep the search small.
    private func actions(for sim: Simulation, level: Level) -> [Action] {
        let p = sim.player
        var jumps: [InputReplay.Jump] = [.none]
        if p.isGrounded || p.coyoteTimer > 0 {
            jumps.append(.pressed)
        } else if p.isJumpRising {
            jumps.append(.held)
        }
        var result: [Action] = []
        for d in [1, -1, 0] {
            for j in jumps { result.append(Action(direction: d, jump: j, steps: nil)) }
        }
        if p.isGrounded && hasPendingChange(sim, level: level) {
            result.append(Action(direction: 0, jump: .none, steps: -1))
        }
        return result
    }

    private func reconstruct(_ nodes: [Node], from last: Int) -> InputReplay {
        var actions: [Action] = []
        var i = last
        while i > 0, let action = nodes[i].action {
            actions.append(action)
            i = nodes[i].parent
        }
        var replay = InputReplay()
        for a in actions.reversed() {
            let steps = a.steps ?? options.stepsPerAction
            if a.jump == .pressed {
                replay.append(.init(direction: a.direction, jump: .pressed, steps: 1))
                replay.append(.init(direction: a.direction, jump: .held, steps: steps - 1))
            } else {
                replay.append(.init(direction: a.direction, jump: a.jump, steps: steps))
            }
        }
        return replay
    }
}

/// Coarse estimate of how long it takes to reach the door from anywhere, respecting what
/// the player can actually climb. Nodes are the tiles you can stand in; edges are walks and
/// jumps (obstacles in the arc are ignored, so estimates stay optimistic).
struct NavigationMap {
    private let width: Int
    private let height: Int
    private var distance: [Double]
    private let runSpeed: Double
    private let goal: Vec2

    init(grid: TileGrid, door: Door, movable: Set<GridPoint> = [], tuning: PhysicsTuning) {
        width = grid.width
        height = grid.height
        runSpeed = tuning.runSpeed
        goal = door.target + Vec2(0.5, 0.5)
        distance = Array(repeating: .infinity, count: width * height)

        func standable(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0 && x < grid.width && y >= 0 && y < grid.height else { return false }
            let free = (!grid[x, y].isSolid || movable.contains(GridPoint(x, y))) && !grid[x, y].isHazard
            return free && grid[x, y - 1].isSolid
        }
        var nodes: [GridPoint] = []
        for y in 0..<height {
            for x in 0..<width where standable(x, y) { nodes.append(GridPoint(x, y)) }
        }

        // Air time of a full jump that lands `dy` tiles higher (negative: lower).
        let g = tuning.gravity, v = tuning.jumpVelocity
        func airTime(_ dy: Int) -> Double? {
            let disc = v * v - 2 * g * Double(dy)
            guard disc >= 0 else { return nil }
            return (v + disc.squareRoot()) / g
        }
        let slack = tuning.playerSize.x + 0.3

        // Reverse edges: for each node, which nodes can reach it and at what cost.
        var incoming: [Int: [(from: Int, cost: Double)]] = [:]
        func index(_ p: GridPoint) -> Int { p.y * width + p.x }
        for a in nodes {
            for b in nodes where a != b {
                let dx = abs(b.x - a.x), dy = b.y - a.y
                let cost: Double
                if dy == 0 && dx == 1 {
                    cost = 1 / runSpeed
                } else if let t = airTime(dy) {
                    let reach = runSpeed * t + slack
                    guard Double(dx) <= reach else { continue }
                    cost = max(Double(dx) / runSpeed, dy > 0 ? t * 0.8 : 0.05)
                } else {
                    continue
                }
                incoming[index(b), default: []].append((index(a), cost))
            }
        }

        // Goal cells: standable cells from which the door is touchable.
        let goal = door.target
        var heap = MinHeap()
        for p in nodes {
            let dx = abs(Double(p.x) + 0.5 - (goal.x + 0.5))
            let dy = goal.y - Double(p.y)
            if dx <= 1.2 && dy <= tuning.fullJumpHeight + 0.5 && dy >= -0.9 {
                let c = dy > 0.5 ? 0.3 : 0
                distance[index(p)] = c
                heap.push(priority: c, value: index(p))
            }
        }
        while let (d, i) = heap.pop() {
            guard d <= distance[i] else { continue }
            for edge in incoming[i] ?? [] {
                let nd = d + edge.cost
                if nd < distance[edge.from] {
                    distance[edge.from] = nd
                    heap.push(priority: nd, value: edge.from)
                }
            }
        }
    }

    /// Estimated seconds to the door from the player's current position. Looks at nearby
    /// standable tiles (not just the one below) so airborne states over spikes or pits get
    /// sensible values.
    func estimate(from player: PlayerState) -> Double {
        let px = player.position.x, py = player.position.y
        let cx = Int(px.rounded(.down)), cy = Int((py + 0.05).rounded(.down))
        var best = Double.infinity
        for y in max(0, cy - 8)...min(height - 1, max(0, cy + 2)) {
            for x in max(0, cx - 3)...min(width - 1, max(0, cx + 3)) {
                let d = distance[y * width + x]
                guard d.isFinite else { continue }
                let dx = abs(Double(x) + 0.5 - px)
                let up = max(0, Double(y) - py)
                best = min(best, d + dx / runSpeed + up * 0.08)
            }
        }
        if best.isFinite { return best }
        // The door is unreachable right now (walled off until a trap opens it): fall back to
        // straight-line distance so the search still heads the right way and waits there.
        let c = player.center
        return 5 + ((goal.x - c.x) * (goal.x - c.x) + (goal.y - c.y) * (goal.y - c.y)).squareRoot() / runSpeed
    }
}

/// Binary min-heap of (priority, value) pairs. Ties resolve in insertion order.
struct MinHeap {
    private var items: [(priority: Double, order: Int, value: Int)] = []
    private var counter = 0

    var isEmpty: Bool { items.isEmpty }

    mutating func push(priority: Double, value: Int) {
        items.append((priority, counter, value))
        counter += 1
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            guard less(i, parent) else { break }
            items.swapAt(i, parent)
            i = parent
        }
    }

    mutating func pop() -> (Double, Int)? {
        guard !items.isEmpty else { return nil }
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var smallest = i
                if l < items.count && less(l, smallest) { smallest = l }
                if r < items.count && less(r, smallest) { smallest = r }
                if smallest == i { break }
                items.swapAt(i, smallest)
                i = smallest
            }
        }
        return (top.priority, top.value)
    }

    private func less(_ a: Int, _ b: Int) -> Bool {
        items[a].priority != items[b].priority ? items[a].priority < items[b].priority : items[a].order < items[b].order
    }
}
