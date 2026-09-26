import Foundation

/// Accumulates variable frame times and converts them into a whole number of fixed steps.
///
/// ```
/// let steps = timestep.advance(by: frameDelta)
/// for _ in 0..<steps { simulation.step() }
/// ```
public struct FixedTimestep: Equatable, Sendable {
    public let step: Double
    public let maxSteps: Int
    public private(set) var accumulator: Double = 0

    /// Frame times within this fraction of a step are rounded to a whole step, so a display
    /// running at exactly the simulation rate gets one step per frame despite timer jitter.
    private let tolerance: Double

    public init(step: Double = Constants.fixedDt, maxSteps: Int = Constants.maxStepsPerFrame) {
        precondition(step > 0 && maxSteps > 0)
        self.step = step
        self.maxSteps = maxSteps
        self.tolerance = step * 0.05
    }

    /// Adds `frameDelta` seconds and returns how many fixed steps should be simulated now.
    public mutating func advance(by frameDelta: Double) -> Int {
        guard frameDelta.isFinite, frameDelta > 0 else { return 0 }
        accumulator += frameDelta
        var count = Int(((accumulator + tolerance) / step).rounded(.down))
        if count > maxSteps {
            // Spiral of death: we cannot catch up, so drop the backlog instead of
            // simulating ever more steps per frame.
            count = maxSteps
            accumulator = 0
        } else {
            accumulator -= Double(count) * step
        }
        return count
    }

    public mutating func reset() {
        accumulator = 0
    }
}
