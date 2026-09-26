import Foundation

/// A run-length encoded sequence of per-step inputs.
///
/// Text form: space separated tokens `<dir><jump><steps>` where
/// - `dir` is `L`, `R` or `N` (none)
/// - `jump` is empty (not held), `H` (held) or `P` (pressed on the first step, then held)
/// - `steps` is the number of fixed steps
///
/// Example: `R30 RP1 RH20 N12` = run right for 30 steps, jump, keep holding for 20
/// steps, then stand still.
public struct InputReplay: Equatable, Hashable, Sendable, CustomStringConvertible {
    public enum Jump: Character, Sendable {
        case none = "-", held = "H", pressed = "P"
    }

    public struct Segment: Equatable, Hashable, Sendable {
        public var direction: Int
        public var jump: Jump
        public var steps: Int

        public init(direction: Int, jump: Jump, steps: Int) {
            self.direction = direction
            self.jump = jump
            self.steps = steps
        }

        func input(atStep i: Int) -> InputState {
            InputState(left: direction < 0, right: direction > 0,
                       jumpPressed: jump == .pressed && i == 0,
                       jumpHeld: jump != .none)
        }
    }

    public private(set) var segments: [Segment]

    public init(segments: [Segment] = []) {
        self.segments = []
        for s in segments { append(s) }
    }

    public struct ParseError: Error, CustomStringConvertible {
        public let token: String
        public var description: String { "invalid replay token '\(token)'" }
    }

    public init(_ text: String) throws {
        self.init()
        for token in text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            var chars = Substring(token)
            let direction: Int
            switch chars.first {
            case "L": direction = -1
            case "R": direction = 1
            case "N": direction = 0
            default: throw ParseError(token: String(token))
            }
            chars = chars.dropFirst()
            var jump = Jump.none
            if chars.first == "H" { jump = .held; chars = chars.dropFirst() }
            else if chars.first == "P" { jump = .pressed; chars = chars.dropFirst() }
            guard let steps = Int(chars), steps > 0 else { throw ParseError(token: String(token)) }
            append(Segment(direction: direction, jump: jump, steps: steps))
        }
    }

    /// Appends a segment, merging with the previous one when possible.
    public mutating func append(_ segment: Segment) {
        guard segment.steps > 0 else { return }
        if var last = segments.last, last.direction == segment.direction,
           last.jump == segment.jump, segment.jump != .pressed {
            last.steps += segment.steps
            segments[segments.count - 1] = last
        } else {
            segments.append(segment)
        }
    }

    public var totalSteps: Int { segments.reduce(0) { $0 + $1.steps } }

    public var duration: Double { Double(totalSteps) * Constants.fixedDt }

    /// Expanded per-step inputs.
    public var inputs: [InputState] {
        var result: [InputState] = []
        result.reserveCapacity(totalSteps)
        for s in segments {
            for i in 0..<s.steps { result.append(s.input(atStep: i)) }
        }
        return result
    }

    public var description: String {
        segments.map { s in
            let d = s.direction < 0 ? "L" : s.direction > 0 ? "R" : "N"
            let j = s.jump == .none ? "" : String(s.jump.rawValue)
            return "\(d)\(j)\(s.steps)"
        }.joined(separator: " ")
    }

    /// Plays the replay on a fresh simulation. Returns the final simulation.
    public func play(on level: Level, tuning: PhysicsTuning = .standard) throws -> Simulation {
        var sim = try Simulation(level: level, tuning: tuning)
        for input in inputs {
            guard sim.isRunning else { break }
            sim.step(input)
        }
        return sim
    }
}

/// Feeds a replay one step at a time (used for the in-game ghost).
public struct ReplayCursor: Sendable {
    private let inputs: [InputState]
    public private(set) var index = 0

    public init(_ replay: InputReplay) {
        inputs = replay.inputs
    }

    public var isFinished: Bool { index >= inputs.count }

    public mutating func next() -> InputState {
        guard index < inputs.count else { return .none }
        defer { index += 1 }
        return inputs[index]
    }
}
