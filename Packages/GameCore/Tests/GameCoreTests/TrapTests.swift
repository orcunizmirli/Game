import XCTest
@testable import GameCore

final class TrapTests: XCTestCase {
    /// 20x6 corridor, floor surface at y = 1, spawn at x = 1.5, door at x = 18.
    let corridor = [
        "####################",
        "#..................#",
        "#..................#",
        "#..................#",
        "#S................D#",
        "####################",
    ]

    func sim(_ traps: [TrapDefinition], rows: [String]? = nil) throws -> Simulation {
        try Simulation(level: makeLevel(rows ?? corridor, traps: traps))
    }

    func zone(_ x: Double, _ y: Double = 1, _ w: Double = 1, _ h: Double = 1) -> Trigger {
        .zone(TileRect(x: x, y: y, width: w, height: h))
    }

    func testWalkingToTheDoorWins() throws {
        var s = try sim([])
        XCTAssertTrue(s.run(until: { $0.status == .won }, limit: 600, right))
    }

    func testZoneTriggerFiresOnceOnEntry() throws {
        let trap = TrapDefinition(id: "t", trigger: zone(5), effect: .emit(event: "e"))
        var s = try sim([trap])
        s.run(until: { !$0.traps[0].isArmed }, limit: 600, right)
        XCTAssertFalse(s.traps[0].isArmed)
        s.run(300, left)
        s.run(300, right)
        XCTAssertEqual(s.bus.history.filter { $0 == "t.fired" }.count, 1)
    }

    func testRepeatingZoneTriggerFiresOnEveryEntry() throws {
        let trap = TrapDefinition(id: "t", trigger: zone(5), effect: .emit(event: "e"), once: false)
        var s = try sim([trap])
        for _ in 0..<3 {
            s.run(until: { $0.player.position.x > 7 }, limit: 600, right)
            s.run(until: { $0.player.position.x < 3 }, limit: 600, left)
        }
        XCTAssertEqual(s.bus.history.filter { $0 == "t.fired" }.count, 6, "enters from both sides, 3 times")
        XCTAssertTrue(s.traps[0].isArmed)
    }

    func testCollapseDropsThePlayer() throws {
        let trap = TrapDefinition(id: "drop", trigger: zone(6), effect: .collapse(tiles: [GridPoint(6, 0), GridPoint(7, 0)]))
        var s = try sim([trap])
        s.run(until: { !$0.isRunning }, limit: 600, right)
        XCTAssertEqual(s.status, .dead(.fell))
        XCTAssertEqual(s.world.grid[6, 0], .empty)
    }

    func testJumpingOverTheZoneAvoidsTheTrap() throws {
        let trap = TrapDefinition(id: "drop", trigger: zone(8, 1, 2, 1), effect: .collapse(tiles: [GridPoint(8, 0), GridPoint(9, 0)]))
        var s = try sim([trap])
        s.run(until: { $0.player.position.x > 6.2 }, limit: 600, right)
        s.step(InputState(right: true, jumpPressed: true, jumpHeld: true))
        s.run(40, InputState(right: true, jumpHeld: true))
        XCTAssertTrue(s.traps[0].isArmed)
        XCTAssertTrue(s.run(until: { $0.status == .won }, limit: 600, right))
    }

    func testSpawnedSpikesKillImmediately() throws {
        let trap = TrapDefinition(id: "spikes", trigger: zone(5), effect: .spawnSpikes(at: [GridPoint(5, 1)], direction: .up))
        var s = try sim([trap])
        s.run(until: { !$0.isRunning }, limit: 600, right)
        XCTAssertEqual(s.status, .dead(.spikes))
        XCTAssertEqual(s.world.grid[5, 1], .spikeUp)
    }

    func testDoorRunsAway() throws {
        let trap = TrapDefinition(id: "run", trigger: zone(15), effect: .moveDoor(to: GridPoint(18, 4), speed: 10))
        var s = try sim([trap])
        s.run(until: { !$0.traps[0].isArmed }, limit: 600, right)
        XCTAssertTrue(s.world.door.isMoving)
        s.run(120)
        XCTAssertEqual(s.world.door.position, Vec2(18, 4))
        XCTAssertFalse(s.world.door.isMoving)
        s.run(240, right)
        XCTAssertTrue(s.isRunning, "the door is out of reach now")
    }

    func testDoorCanRunIntoThePlayer() throws {
        let trap = TrapDefinition(id: "come", trigger: .delay(0), effect: .moveDoor(to: GridPoint(1, 1), speed: 10))
        var s = try sim([trap])
        XCTAssertTrue(s.run(until: { $0.status == .won }, limit: 600))
    }

    func testTeleportingDoor() throws {
        let trap = TrapDefinition(id: "tp", trigger: .delay(0), effect: .moveDoor(to: GridPoint(10, 3), speed: 0))
        var s = try sim([trap])
        s.step(.none)
        XCTAssertEqual(s.world.door.position, Vec2(10, 3))
    }

    func testFallingCeilingCrushes() throws {
        let rows = [
            "####################",
            "#.......###........#",
            "#..................#",
            "#..................#",
            "#S................D#",
            "####################",
        ]
        let trap = TrapDefinition(id: "ceil", trigger: zone(8, 1, 3, 1), effect: .dropCeiling(tiles: [GridPoint(8, 4), GridPoint(9, 4), GridPoint(10, 4)], speed: 20))
        var s = try sim([trap], rows: rows)
        s.run(until: { !$0.traps[0].isArmed }, limit: 600, right)
        XCTAssertEqual(s.world.blocks.count, 3)
        s.run(until: { !$0.isRunning }, limit: 600)
        XCTAssertEqual(s.status, .dead(.crushed))
    }

    func testFallingCeilingLandsAndBecomesFloor() throws {
        let rows = [
            "####################",
            "#.......#..........#",
            "#..................#",
            "#..................#",
            "#S................D#",
            "####################",
        ]
        let trap = TrapDefinition(id: "ceil", trigger: .delay(0), effect: .dropCeiling(tiles: [GridPoint(8, 4)], speed: 12))
        var s = try sim([trap], rows: rows)
        s.run(120)
        XCTAssertTrue(s.world.blocks.isEmpty)
        XCTAssertEqual(s.world.grid[8, 4], .empty)
        XCTAssertEqual(s.world.grid[8, 1], .solid, "landed on the floor")
        // The player can now climb over it.
        XCTAssertTrue(s.run(until: { $0.player.position.x > 7 }, limit: 600, right))
        s.step(InputState(right: true, jumpPressed: true, jumpHeld: true))
        XCTAssertTrue(s.run(until: { $0.status == .won }, limit: 600, InputState(right: true, jumpHeld: true)))
    }

    func testSideClipByFallingBlockNudgesInsteadOfCrushing() throws {
        let rows = [
            "##########",
            "#...#....#",
            "#........#",
            "#........#",
            "#S......D#",
            "##########",
        ]
        let trap = TrapDefinition(id: "ceil", trigger: .delay(0), effect: .dropCeiling(tiles: [GridPoint(4, 4)], speed: 12))
        var s = try sim([trap], rows: rows)
        // Stand so that only 0.15 tiles of the player are under the block.
        s.run(until: { $0.player.bounds.maxX >= 4.15 }, limit: 600, right)
        s.run(120)
        XCTAssertTrue(s.isRunning)
        XCTAssertLessThanOrEqual(s.player.bounds.maxX, 4 + 1e-9)
    }

    func testInvertControls() throws {
        let trap = TrapDefinition(id: "flip", trigger: .delay(0), effect: .invertControls(duration: 0.5))
        var s = try sim([trap])
        s.run(10)
        let x0 = s.player.position.x
        s.run(30, right)
        XCTAssertTrue(s.world.controlsInverted)
        XCTAssertLessThan(s.player.position.x, x0, "right moves left while inverted")
        s.run(60, .none)
        XCTAssertFalse(s.world.controlsInverted)
        let x1 = s.player.position.x
        s.run(30, right)
        XCTAssertGreaterThan(s.player.position.x, x1)
    }

    func testEventChaining() throws {
        let first = TrapDefinition(id: "first", trigger: zone(4), effect: .emit(event: "custom"))
        let second = TrapDefinition(id: "second", trigger: .onEvent("first.fired"), effect: .addTiles(tiles: [GridPoint(10, 3)]))
        let third = TrapDefinition(id: "third", trigger: .onEvent("custom"), effect: .spawnSpikes(at: [GridPoint(12, 4)], direction: .down))
        var s = try sim([first, second, third])
        s.run(until: { !$0.traps[0].isArmed }, limit: 600, right)
        XCTAssertTrue(s.traps[1].isArmed, "chained traps fire on the following step")
        s.step(.none)
        XCTAssertFalse(s.traps[1].isArmed)
        XCTAssertFalse(s.traps[2].isArmed)
        XCTAssertEqual(s.world.grid[10, 3], .solid)
        XCTAssertEqual(s.world.grid[12, 4], .spikeDown)
        XCTAssertEqual(s.bus.history, ["custom", "first.fired", "second.fired", "third.fired"])
    }

    func testDelayTriggerAndTrapDelay() throws {
        let timed = TrapDefinition(id: "timed", trigger: .delay(0.5), effect: .addTiles(tiles: [GridPoint(10, 3)]))
        let delayed = TrapDefinition(id: "delayed", trigger: zone(1), effect: .addTiles(tiles: [GridPoint(11, 3)]), delay: 0.25)
        var s = try sim([timed, delayed])
        s.run(29)  // 0.24 s
        XCTAssertEqual(s.world.grid[11, 3], .empty)
        s.run(2)
        XCTAssertEqual(s.world.grid[11, 3], .solid)
        XCTAssertEqual(s.world.grid[10, 3], .empty)
        s.run(30)
        XCTAssertEqual(s.world.grid[10, 3], .solid)
    }

    func testAddedWallOnPlayerCrushes() throws {
        let trap = TrapDefinition(id: "wall", trigger: zone(5), effect: .addTiles(tiles: [GridPoint(5, 1)]))
        var s = try sim([trap])
        s.run(until: { !$0.isRunning }, limit: 600, right)
        XCTAssertEqual(s.status, .dead(.crushed))
    }

    func testSlidingWallSettlesAtDestination() throws {
        let rows = [
            "####################",
            "#..................#",
            "#..................#",
            "#.....#............#",
            "#S....#...........D#",
            "####################",
        ]
        let trap = TrapDefinition(id: "slide", trigger: .delay(0),
                                  effect: .slideTiles(tiles: [GridPoint(6, 1), GridPoint(6, 2)], by: GridPoint(0, -2), speed: 8))
        var s = try sim([trap], rows: rows)
        s.run(1)
        XCTAssertEqual(s.world.blocks.count, 2)
        s.run(60)
        XCTAssertTrue(s.world.blocks.isEmpty)
        XCTAssertEqual(s.world.grid[6, 0], .solid)
        XCTAssertEqual(s.world.grid[6, 1], .empty)
        XCTAssertEqual(s.world.grid[6, 2], .empty)
        XCTAssertTrue(s.run(until: { $0.status == .won }, limit: 600, right), "wall sank into the floor, path is open")
    }

    func testSlidingWallPushesAndCrushes() throws {
        let rows = [
            "##########",
            "#........#",
            "#........#",
            "#........#",
            "#.S...#.D#",
            "##########",
        ]
        let trap = TrapDefinition(id: "slide", trigger: .delay(0.1),
                                  effect: .slideTiles(tiles: [GridPoint(6, 1)], by: GridPoint(-6, 0), speed: 6))
        var s = try sim([trap], rows: rows)
        s.run(until: { !$0.isRunning }, limit: 600)
        XCTAssertEqual(s.status, .dead(.crushed), "pinned against the left wall")
    }

    func testPlatformCarriesThePlayer() throws {
        let rows = [
            "####################",
            "#..................#",
            "#..................#",
            "#S.................#",
            "##................D#",
            "####################",
        ]
        let trap = TrapDefinition(id: "lift", trigger: .delay(0.5),
                                  effect: .slideTiles(tiles: [GridPoint(1, 1)], by: GridPoint(5, 0), speed: 5))
        var s = try sim([trap], rows: rows)
        s.run(until: { !$0.world.blocks.isEmpty }, limit: 120)
        let x0 = s.player.position.x
        s.run(until: { $0.world.blocks.isEmpty }, limit: 240)
        XCTAssertEqual(s.player.position.x - x0, 5, accuracy: 0.05)
        XCTAssertEqual(s.world.grid[6, 1], .solid)
    }

    func testHiddenBlockIsSolidAndRevealed() throws {
        let rows = [
            "##########",
            "#........#",
            "#...?....#",
            "#........#",
            "#.S.....D#",
            "##########",
        ]
        var s = try sim([], rows: rows)
        s.run(until: { $0.player.position.x >= 4.4 }, limit: 600, right)
        s.run(10)
        s.step(jump)
        var sawReveal = false
        for _ in 0..<60 {
            if s.step(holdJump).contains(.world(.tileRevealed(GridPoint(4, 3)))) { sawReveal = true }
        }
        XCTAssertTrue(sawReveal)
        XCTAssertEqual(s.world.grid[4, 3], .revealed)
        XCTAssertLessThan(s.player.bounds.maxY, 3.0001, "bumped into the invisible block")
    }

    func testFakeFloorIsNotSolid() throws {
        let rows = [
            "##########",
            "#........#",
            "#........#",
            "#.S.....D#",
            "####x#####",
            "####.#####",
        ]
        var s = try sim([], rows: rows)
        s.run(until: { !$0.isRunning }, limit: 600, right)
        XCTAssertEqual(s.status, .dead(.fell))
    }

    func testFallingOutKills() throws {
        let rows = [
            "..........",
            "..........",
            "S.......D.",
            "###....###",
        ]
        var s = try sim([], rows: rows)
        s.run(until: { !$0.isRunning }, limit: 600, right)
        XCTAssertEqual(s.status, .dead(.fell))
    }
}
