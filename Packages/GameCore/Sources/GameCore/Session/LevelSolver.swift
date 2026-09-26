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
        public var maxExpansions = 400_000
        /// > 1 favours getting closer to the door over short solutions.
        public var heuristicWeight = 1.6
        /// Hard cap on solution length in seconds.
        public var maxTime: Double = 90

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
        let usesTime = level.traps.contains { trap in
            if case .delay = trap.trigger { return true }
            return trap.delay > 0 || trap.effects.contains { if case .invertControls = $0 { return true }; return false }
        }

        var nodes: [Node] = [Node(sim: start, parent: -1, action: nil, cost: 0)]
        var heap = MinHeap()
        var seen = Set<Int>()
        heap.push(priority: heuristic(start, tuning: tuning), value: 0)
        seen.insert(start.stateKey(includeTime: usesTime))
        var expansions = 0

        while let (_, index) = heap.pop() {
            expansions += 1
            if expansions > options.maxExpansions { break }
            let node = nodes[index]
            if node.cost > options.maxTime { continue }

            for action in actions(for: node.sim) {
                var sim = node.sim
                let steps = options.stepsPerAction
                for i in 0..<steps {
                    let input = InputState(left: action.direction < 0, right: action.direction > 0,
                                           jumpPressed: action.jump == .pressed && i == 0,
                                           jumpHeld: action.jump != .none)
                    sim.step(input)
                    if !sim.isRunning { break }
                }
                let cost = node.cost + Double(steps) * Constants.fixedDt
                switch sim.status {
                case .dead:
                    continue
                case .won:
                    nodes.append(Node(sim: sim, parent: index, action: action, cost: cost))
                    return Result(replay: reconstruct(nodes, from: nodes.count - 1), expansions: expansions)
                case .running:
                    let key = sim.stateKey(includeTime: usesTime)
                    guard seen.insert(key).inserted else { continue }
                    nodes.append(Node(sim: sim, parent: index, action: action, cost: cost))
                    heap.push(priority: cost + options.heuristicWeight * heuristic(sim, tuning: tuning),
                              value: nodes.count - 1)
                }
            }
        }
        return Result(replay: nil, expansions: expansions)
    }

    /// Only branch on jump choices that can matter, to keep the search small.
    private func actions(for sim: Simulation) -> [Action] {
        let p = sim.player
        var jumps: [InputReplay.Jump] = [.none]
        if p.isGrounded || p.coyoteTimer > 0 {
            jumps.append(.pressed)
        } else if p.isJumpRising {
            jumps.append(.held)
        }
        var result: [Action] = []
        for d in [1, -1, 0] {
            for j in jumps { result.append(Action(direction: d, jump: j)) }
        }
        return result
    }

    /// Optimistic time to reach the door.
    private func heuristic(_ sim: Simulation, tuning: PhysicsTuning) -> Double {
        let goal = sim.world.door.goalBounds.center
        let c = sim.player.center
        let dx = abs(goal.x - c.x), dy = abs(goal.y - c.y)
        return max(dx / tuning.runSpeed, dy / tuning.jumpVelocity)
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
            if a.jump == .pressed {
                replay.append(.init(direction: a.direction, jump: .pressed, steps: 1))
                replay.append(.init(direction: a.direction, jump: .held, steps: options.stepsPerAction - 1))
            } else {
                replay.append(.init(direction: a.direction, jump: a.jump, steps: options.stepsPerAction))
            }
        }
        return replay
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
