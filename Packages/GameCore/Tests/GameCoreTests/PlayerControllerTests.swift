import XCTest
@testable import GameCore

final class PlayerControllerTests: XCTestCase {
    let dt = Constants.fixedDt
    let controller = PlayerController()

    /// 16x7 room, floor surface at y = 1, walls at x = 0 and x = 15.
    let room = GridWorld([
        "################",
        "#..............#",
        "#..............#",
        "#..............#",
        "#..............#",
        "#..............#",
        "################",
    ])

    func settle(_ p: inout PlayerState, in world: CollisionProvider) {
        for _ in 0..<240 { controller.step(&p, input: .none, dt: dt, world: world) }
    }

    func testFallsAndLandsExactlyOnTheFloor() {
        var p = PlayerState(position: Vec2(4, 4))
        var landed = false
        for _ in 0..<240 {
            if controller.step(&p, input: .none, dt: dt, world: room).landed { landed = true }
        }
        XCTAssertTrue(landed)
        XCTAssertTrue(p.isGrounded)
        XCTAssertEqual(p.position.y, 1)
        XCTAssertEqual(p.velocity.y, 0)
    }

    func testStaysGroundedWhileStanding() {
        var p = PlayerState(position: Vec2(4, 1))
        for _ in 0..<600 {
            controller.step(&p, input: .none, dt: dt, world: room)
            XCTAssertTrue(p.isGrounded)
            XCTAssertEqual(p.position.y, 1)
        }
    }

    func testRunsToTopSpeedAndStopsAtWall() {
        var p = PlayerState(position: Vec2(4, 1))
        for _ in 0..<30 { controller.step(&p, input: right, dt: dt, world: room) }
        XCTAssertEqual(p.velocity.x, PhysicsTuning.standard.runSpeed, accuracy: 1e-9)
        var hitWall = false
        for _ in 0..<300 {
            if controller.step(&p, input: right, dt: dt, world: room).hitWall { hitWall = true }
        }
        XCTAssertTrue(hitWall)
        XCTAssertEqual(p.bounds.maxX, 15, accuracy: 1e-12)
        XCTAssertEqual(p.velocity.x, 0)
        XCTAssertEqual(p.facing, 1)
    }

    func testFrictionStopsThePlayer() {
        var p = PlayerState(position: Vec2(4, 1))
        for _ in 0..<30 { controller.step(&p, input: right, dt: dt, world: room) }
        for _ in 0..<30 { controller.step(&p, input: .none, dt: dt, world: room) }
        XCTAssertEqual(p.velocity.x, 0)
    }

    func testFullJumpHeight() {
        var p = PlayerState(position: Vec2(4, 1))
        settle(&p, in: room)
        XCTAssertTrue(controller.step(&p, input: jump, dt: dt, world: room).jumped)
        var peak = p.position.y
        for _ in 0..<120 {
            controller.step(&p, input: holdJump, dt: dt, world: room)
            peak = max(peak, p.position.y)
        }
        let height = peak - 1
        XCTAssertEqual(height, PhysicsTuning.standard.fullJumpHeight, accuracy: 0.1)
        XCTAssertGreaterThan(height, 2.5, "must clear two blocks")
        XCTAssertLessThan(height, 3.0, "must not clear three blocks")
        XCTAssertTrue(p.isGrounded)
    }

    func testReleasingEarlyGivesALowerJump() {
        var p = PlayerState(position: Vec2(4, 1))
        settle(&p, in: room)
        controller.step(&p, input: jump, dt: dt, world: room)
        var peak = p.position.y
        for _ in 0..<120 {
            controller.step(&p, input: .none, dt: dt, world: room)
            peak = max(peak, p.position.y)
        }
        XCTAssertLessThan(peak - 1, 0.8)
        XCTAssertGreaterThan(peak - 1, 0.3)
    }

    func testCannotDoubleJump() {
        var p = PlayerState(position: Vec2(4, 1))
        settle(&p, in: room)
        controller.step(&p, input: jump, dt: dt, world: room)
        for _ in 0..<10 { controller.step(&p, input: holdJump, dt: dt, world: room) }
        XCTAssertFalse(controller.step(&p, input: jump, dt: dt, world: room).jumped)
    }

    // Floor surface at y = 2 for x < 5, open to the right.
    let ledge = GridWorld([
        "..........",
        "..........",
        "..........",
        "..........",
        "#####.....",
        "#####.....",
    ])

    func walkOffLedge() -> PlayerState {
        var p = PlayerState(position: Vec2(3, 2))
        settle(&p, in: ledge)
        while p.isGrounded {
            controller.step(&p, input: right, dt: dt, world: ledge)
        }
        return p
    }

    func testCoyoteTimeAllowsLateJump() {
        var p = walkOffLedge()
        for _ in 0..<5 { controller.step(&p, input: right, dt: dt, world: ledge) } // 42 ms late
        XCTAssertTrue(controller.step(&p, input: InputState(right: true, jumpPressed: true, jumpHeld: true),
                                      dt: dt, world: ledge).jumped)
    }

    func testCoyoteTimeExpires() {
        var p = walkOffLedge()
        for _ in 0..<12 { controller.step(&p, input: right, dt: dt, world: ledge) } // 100 ms late
        XCTAssertFalse(controller.step(&p, input: InputState(right: true, jumpPressed: true, jumpHeld: true),
                                       dt: dt, world: ledge).jumped)
    }

    func testJumpBufferExecutesOnLanding() {
        var p = PlayerState(position: Vec2(4, 1.3)) // lands after ~11 steps
        controller.step(&p, input: jump, dt: dt, world: room)
        XCTAssertFalse(p.isGrounded)
        var jumped = false
        for _ in 0..<20 {
            if controller.step(&p, input: holdJump, dt: dt, world: room).jumped { jumped = true }
        }
        XCTAssertTrue(jumped)
    }

    func testJumpBufferExpires() {
        var p = PlayerState(position: Vec2(4, 3)) // lands after ~28 steps
        controller.step(&p, input: jump, dt: dt, world: room)
        var jumped = false
        for _ in 0..<60 {
            if controller.step(&p, input: holdJump, dt: dt, world: room).jumped { jumped = true }
        }
        XCTAssertFalse(jumped)
        XCTAssertTrue(p.isGrounded)
    }

    func testHeadBump() {
        let lowRoom = GridWorld([
            "########",
            "#......#",
            "#......#",
            "########",
        ])
        var p = PlayerState(position: Vec2(3, 1))
        settle(&p, in: lowRoom)
        controller.step(&p, input: jump, dt: dt, world: lowRoom)
        var bumped = false
        for _ in 0..<30 {
            let r = controller.step(&p, input: holdJump, dt: dt, world: lowRoom)
            if r.bumpedHead {
                bumped = true
                XCTAssertEqual(p.bounds.maxY, 3, accuracy: 1e-12)
                XCTAssertEqual(p.velocity.y, 0)
            }
        }
        XCTAssertTrue(bumped)
    }

    func testDoesNotTunnelAtTerminalVelocity() {
        let tower = GridWorld([
            ".....", ".....", ".....", ".....", ".....", ".....", ".....", ".....",
            ".....", ".....", ".....", ".....", ".....", ".....", ".....", ".....",
            ".....", ".....", ".....", ".....", ".....", ".....", ".....", ".....",
            "#####",
            ".....",
        ])
        var p = PlayerState(position: Vec2(2, 24))
        for _ in 0..<600 { controller.step(&p, input: .none, dt: dt, world: tower) }
        XCTAssertEqual(p.position.y, 2)
        XCTAssertTrue(p.isGrounded)
    }

    func testOutOfBoundsSidesAreWalls() {
        let open = GridWorld([
            "......",
            "######",
        ])
        var p = PlayerState(position: Vec2(3, 1))
        for _ in 0..<300 { controller.step(&p, input: left, dt: dt, world: open) }
        XCTAssertEqual(p.bounds.minX, 0, accuracy: 1e-12)
    }

    /// Same input timeline, displayed at 60 Hz and at 120 Hz, must produce the same motion.
    func testFrameRateIndependence() throws {
        let level = makeLevel([
            "..........",
            "..........",
            "..........",
            "..........",
            "S........D",
            "##########",
        ])

        func run(fps: Double) throws -> (peak: Double, final: PlayerState) {
            var sim = try Simulation(level: level)
            var timestep = FixedTimestep()
            var latch = InputLatch()
            var peak = 0.0
            let frames = Int(1.5 * fps)
            for f in 0..<frames {
                let t = Double(f) / fps
                let held = t >= 0.5 && t < 0.75
                let pressed = held && Double(f - 1) / fps < 0.5
                latch.submit(InputState(right: t >= 0.25 && t < 1.0, jumpPressed: pressed, jumpHeld: held))
                for _ in 0..<timestep.advance(by: 1 / fps) {
                    sim.step(latch.next())
                    peak = max(peak, sim.player.position.y)
                }
            }
            return (peak, sim.player)
        }

        let at60 = try run(fps: 60)
        let at120 = try run(fps: 120)
        XCTAssertGreaterThan(at60.peak, 2.0)
        XCTAssertEqual(at60.peak, at120.peak)
        XCTAssertEqual(at60.final, at120.final)
    }
}

final class TileGridTests: XCTestCase {
    func testOrientationAndBounds() {
        var grid = TileGrid(width: 4, height: 3)
        grid.set(.solid, at: GridPoint(0, 0))
        XCTAssertEqual(grid[0, 0], .solid)
        XCTAssertEqual(grid[-1, 1], .solid, "left of the grid is wall")
        XCTAssertEqual(grid[4, 1], .solid, "right of the grid is wall")
        XCTAssertEqual(grid[1, -1], .empty, "below the grid is a pit")
        XCTAssertEqual(grid[1, 3], .empty, "above the grid is open")
        XCTAssertFalse(grid.set(.solid, at: GridPoint(9, 9)))
    }

    func testRevisionTracksChanges() {
        var grid = TileGrid(width: 2, height: 2)
        let r0 = grid.revision
        grid.set(.solid, at: GridPoint(1, 1))
        XCTAssertEqual(grid.revision, r0 + 1)
        grid.set(.solid, at: GridPoint(1, 1))
        XCTAssertEqual(grid.revision, r0 + 1, "no-op writes do not bump the revision")
    }

    func testSolidsAndHazardsQueries() {
        var grid = TileGrid(width: 5, height: 5)
        grid.set(.solid, at: GridPoint(2, 2))
        grid.set(.spikeUp, at: GridPoint(3, 2))
        grid.set(.fake, at: GridPoint(1, 2))
        grid.set(.hidden, at: GridPoint(2, 3))
        let region = AABB(x: 0.5, y: 1.5, width: 3.2, height: 2)
        let solids = grid.solids(in: region)
        XCTAssertTrue(solids.contains(GridPoint(2, 2).bounds))
        XCTAssertTrue(solids.contains(GridPoint(2, 3).bounds), "hidden blocks are solid")
        XCTAssertFalse(solids.contains(GridPoint(1, 2).bounds), "fake blocks are not solid")
        XCTAssertFalse(solids.contains(GridPoint(3, 2).bounds), "spikes are not solid")
        XCTAssertEqual(grid.hazards(in: region).count, 1)
    }

    func testSpikeHitboxIsForgiving() {
        let box = TileKind.spikeUp.hazardBounds(at: GridPoint(0, 0))!
        XCTAssertLessThan(box.height, 0.5)
        XCTAssertGreaterThan(box.minX, 0)
        XCTAssertLessThan(box.maxX, 1)
        let down = TileKind.spikeDown.hazardBounds(at: GridPoint(0, 0))!
        XCTAssertEqual(down.maxY, 1)
        XCTAssertNil(TileKind.solid.hazardBounds(at: GridPoint(0, 0)))
    }
}
