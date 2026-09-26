import XCTest
@testable import GameCore

final class LevelParsingTests: XCTestCase {
    /// The example from the design document.
    let sample = """
    {
      "id": "level_001",
      "tileSize": 32,
      "grid": ["##########",
               "#........#",
               "#S......D#",
               "##########"],
      "traps": [
        {
          "id": "floor_drop_1",
          "trigger": { "type": "zone", "rect": [5, 1, 2, 1] },
          "effect":  { "type": "collapse", "tiles": [[5,0],[6,0]] },
          "once": true
        }
      ]
    }
    """

    func testDecodesDesignDocumentExample() throws {
        let level = try LevelCatalog.decode(Data(sample.utf8))
        XCTAssertEqual(level.id, "level_001")
        XCTAssertEqual(level.name, "level_001", "name defaults to id")
        XCTAssertEqual(level.width, 10)
        XCTAssertEqual(level.height, 4)
        XCTAssertEqual(level.traps.count, 1)
        let trap = level.traps[0]
        XCTAssertEqual(trap.trigger, .zone(TileRect(x: 5, y: 1, width: 2, height: 1)))
        XCTAssertEqual(trap.effects, [.collapse(tiles: [GridPoint(5, 0), GridPoint(6, 0)])])
        XCTAssertTrue(trap.once)
        XCTAssertEqual(trap.delay, 0)
    }

    func testGridOriginIsBottomLeft() throws {
        let world = try WorldBuilder.build(LevelCatalog.decode(Data(sample.utf8)))
        XCTAssertEqual(world.grid.width, 10)
        XCTAssertEqual(world.grid[0, 0], .solid)
        XCTAssertEqual(world.grid[1, 1], .empty)
        XCTAssertEqual(world.spawn, Vec2(1.5, 1), "spawn feet at the bottom-center of the S tile")
        XCTAssertEqual(world.door.position, Vec2(8, 1))
    }

    func testAllSymbols() throws {
        let world = try WorldBuilder.build(makeLevel([
            "^v<>x?",
            "S#...D",
        ]))
        XCTAssertEqual(world.grid[0, 1], .spikeUp)
        XCTAssertEqual(world.grid[1, 1], .spikeDown)
        XCTAssertEqual(world.grid[2, 1], .spikeLeft)
        XCTAssertEqual(world.grid[3, 1], .spikeRight)
        XCTAssertEqual(world.grid[4, 1], .fake)
        XCTAssertEqual(world.grid[5, 1], .hidden)
        XCTAssertEqual(world.grid[1, 0], .solid)
        XCTAssertEqual(world.grid[0, 0], .empty)
    }

    func testDecodesEveryTriggerAndEffect() throws {
        let json = """
        [
          { "id": "a", "trigger": { "type": "zone", "rect": [1, 1, 2, 3] },
            "effect": { "type": "collapse", "rect": [0, 0, 2, 1] } },
          { "id": "b", "trigger": { "type": "delay", "seconds": 1.5 },
            "effect": { "type": "spawnSpikes", "at": [[1, 1]], "dir": "down" } },
          { "id": "c", "trigger": { "type": "onEvent", "event": "a.fired" }, "delay": 0.25, "once": false,
            "effects": [
              { "type": "moveDoor", "to": [3, 4] },
              { "type": "dropCeiling", "tiles": [[2, 5]], "speed": 9 },
              { "type": "invertControls", "duration": 2 },
              { "type": "emit", "event": "boom" },
              { "type": "addTiles", "tiles": [[4, 4]] },
              { "type": "slideTiles", "rect": [5, 1, 1, 2], "by": [-2, 0], "speed": 4 }
            ] }
        ]
        """
        let traps = try JSONDecoder().decode([TrapDefinition].self, from: Data(json.utf8))
        XCTAssertEqual(traps[0].effects, [.collapse(tiles: [GridPoint(0, 0), GridPoint(1, 0)])])
        XCTAssertEqual(traps[1].trigger, .delay(1.5))
        XCTAssertEqual(traps[1].effects, [.spawnSpikes(at: [GridPoint(1, 1)], direction: .down)])
        XCTAssertEqual(traps[2].trigger, .onEvent("a.fired"))
        XCTAssertEqual(traps[2].delay, 0.25)
        XCTAssertFalse(traps[2].once)
        XCTAssertEqual(traps[2].effects, [
            .moveDoor(to: GridPoint(3, 4), speed: Constants.defaultDoorSpeed),
            .dropCeiling(tiles: [GridPoint(2, 5)], speed: 9),
            .invertControls(duration: 2),
            .emit(event: "boom"),
            .addTiles(tiles: [GridPoint(4, 4)]),
            .slideTiles(tiles: [GridPoint(5, 1), GridPoint(5, 2)], by: GridPoint(-2, 0), speed: 4),
        ])

        // Round trip.
        let encoded = try JSONEncoder().encode(traps)
        XCTAssertEqual(try JSONDecoder().decode([TrapDefinition].self, from: encoded), traps)
    }

    func testLevelRoundTrip() throws {
        let level = try LevelCatalog.decode(Data(sample.utf8))
        let again = try LevelCatalog.decode(JSONEncoder().encode(level))
        XCTAssertEqual(level, again)
    }

    func testRejectsUnknownTypes() {
        let badTrigger = #"{ "id": "x", "trigger": { "type": "teleport" }, "effect": { "type": "emit", "event": "e" } }"#
        XCTAssertThrowsError(try JSONDecoder().decode(TrapDefinition.self, from: Data(badTrigger.utf8)))
        let badEffect = #"{ "id": "x", "trigger": { "type": "delay", "seconds": 1 }, "effect": { "type": "explode" } }"#
        XCTAssertThrowsError(try JSONDecoder().decode(TrapDefinition.self, from: Data(badEffect.utf8)))
        let noTiles = #"{ "id": "x", "trigger": { "type": "delay", "seconds": 1 }, "effect": { "type": "collapse" } }"#
        XCTAssertThrowsError(try JSONDecoder().decode(TrapDefinition.self, from: Data(noTiles.utf8)))
    }

    func testValidationErrors() {
        XCTAssertThrowsError(try WorldBuilder.build(makeLevel(["S..D", "###"])), "ragged rows")
        XCTAssertThrowsError(try WorldBuilder.build(makeLevel(["...D", "####"])), "no spawn")
        XCTAssertThrowsError(try WorldBuilder.build(makeLevel(["S.DD", "####"])), "two doors")
        XCTAssertThrowsError(try WorldBuilder.build(makeLevel(["S.KD", "####"])), "unknown symbol")
        let outside = TrapDefinition(id: "t", trigger: .delay(0), effect: .collapse(tiles: [GridPoint(40, 0)]))
        XCTAssertThrowsError(try WorldBuilder.build(makeLevel(["S..D", "####"], traps: [outside])))
        let dup = TrapDefinition(id: "t", trigger: .delay(0), effect: .emit(event: "e"))
        XCTAssertThrowsError(try WorldBuilder.build(makeLevel(["S..D", "####"], traps: [dup, dup])))
    }

    func testValidationWarnsAboutDanglingEvents() {
        let lonely = TrapDefinition(id: "t", trigger: .onEvent("nobody.fired"), effect: .emit(event: "e"))
        let issues = WorldBuilder.validate(makeLevel(["S..D", "####"], traps: [lonely]))
        XCTAssertEqual(issues.count, 1)
        XCTAssertFalse(issues[0].isError)
    }
}

/// Checks the levels that ship with the game.
final class BundledLevelTests: XCTestCase {
    func testCatalogFindsLevelsInOrder() throws {
        let catalog = try LevelCatalog()
        XCTAssertGreaterThanOrEqual(catalog.count, 5)
        let ids = try catalog.allLevels().map(\.id)
        XCTAssertEqual(ids, ids.sorted())
        XCTAssertEqual(Set(ids).count, ids.count, "level ids are unique")
    }

    func testEveryLevelValidatesWithoutWarnings() throws {
        for level in try LevelCatalog().allLevels() {
            XCTAssertEqual(WorldBuilder.validate(level), [], level.id)
            XCTAssertNoThrow(try WorldBuilder.build(level), level.id)
        }
    }

    func testCatalogCachesParsedLevels() throws {
        let catalog = try LevelCatalog()
        let a = try catalog.level(at: 0)
        let b = try catalog.level(at: 0)
        XCTAssertEqual(a, b)
        XCTAssertThrowsError(try catalog.level(at: 999))
    }

    /// Every level must be beatable: its recorded solution (found by `levelcheck solve`)
    /// has to reach the door. If physics or a level changes, re-run the solver.
    func testEveryLevelHasAWorkingSolution() throws {
        let catalog = try LevelCatalog()
        for level in try catalog.allLevels() {
            guard let replay = catalog.solution(for: level.id) else {
                XCTFail("\(level.id) has no solution file; run `levelcheck solve --write`")
                continue
            }
            let sim = try replay.play(on: level)
            XCTAssertEqual(sim.status, .won, "\(level.id) solution no longer works")
        }
    }

    /// Doing nothing must never win a level, and walking straight right should
    /// not either (otherwise the level has no challenge).
    func testLevelsAreNotTrivial() throws {
        for level in try LevelCatalog().allLevels() {
            var idle = try Simulation(level: level)
            idle.run(1200)
            XCTAssertNotEqual(idle.status, .won, "\(level.id) wins by standing still")

            var walker = try Simulation(level: level)
            walker.run(1200, right)
            XCTAssertNotEqual(walker.status, .won, "\(level.id) wins by holding right")
        }
    }
}
