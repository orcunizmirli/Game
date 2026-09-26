import XCTest
@testable import GameCore

final class SessionTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gamecore-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Level 1: walk right to the door. Level 2: a spike pit right in front of spawn.
        try write(makeLevel([
            "########",
            "#......#",
            "#S....D#",
            "########",
        ], id: "level_001"))
        try write(makeLevel([
            "########",
            "#......#",
            "#......#",
            "#......#",
            "#S.^^.D#",
            "########",
        ], id: "level_002"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func write(_ level: Level) throws {
        try JSONEncoder().encode(level).write(to: directory.appendingPathComponent("\(level.id).json"))
    }

    func makeSession(start: Int = 0) throws -> (GameSession, ProgressStore) {
        let progress = ProgressStore(store: InMemoryKeyValueStore())
        let session = try GameSession(catalog: LevelCatalog(source: .directory(directory)),
                                      progress: progress, startLevel: start)
        return (session, progress)
    }

    func testDeathRestartsQuicklyAndCounts() throws {
        let (session, progress) = try makeSession(start: 1)
        var steps = 0
        while session.phase == .playing && steps < 600 {
            session.step(right)
            steps += 1
        }
        guard case .dying(.spikes, _) = session.phase else {
            return XCTFail("expected to die on spikes, got \(session.phase)")
        }
        XCTAssertEqual(session.deathsThisVisit, 1)
        XCTAssertEqual(progress.record(forLevel: "level_002").deaths, 1)
        XCTAssertEqual(progress.totalDeaths, 1)

        let generation = session.generation
        var restartSteps = 0
        var respawned = false
        while !respawned && restartSteps < 100 {
            respawned = session.step(.none).contains(.respawned)
            restartSteps += 1
        }
        XCTAssertTrue(respawned)
        XCTAssertLessThan(Double(restartSteps) * Constants.fixedDt, 0.2, "death → restart under 200 ms")
        XCTAssertEqual(session.phase, .playing)
        XCTAssertEqual(session.generation, generation + 1)
        XCTAssertEqual(session.player.position, session.world.spawn, "fresh world")
    }

    func testCompletingLevelsAdvancesAndFinishes() throws {
        let (session, progress) = try makeSession()
        var events: [GameEvent] = []
        for _ in 0..<600 where session.phase == .playing {
            events += session.step(right)
        }
        XCTAssertTrue(events.contains(.reachedDoor))
        XCTAssertTrue(events.contains { if case .levelCompleted(index: 0, _, _) = $0 { return true }; return false })
        XCTAssertEqual(progress.unlockedCount, 2)
        XCTAssertNotNil(progress.record(forLevel: "level_001").bestTime)

        var started = false
        for _ in 0..<200 where !started {
            started = session.step(.none).contains(.levelStarted(index: 1))
        }
        XCTAssertTrue(started)
        XCTAssertEqual(session.levelIndex, 1)
        XCTAssertEqual(session.level.id, "level_002")

        // Jump over the spikes to finish the last level.
        for _ in 0..<600 where session.phase == .playing {
            let x = session.player.position.x
            session.step(x > 2.6 && x < 3 ? InputState(right: true, jumpPressed: true, jumpHeld: true)
                                          : InputState(right: true, jumpHeld: true))
        }
        var finished = false
        for _ in 0..<200 where !finished {
            finished = session.step(.none).contains(.gameFinished)
        }
        XCTAssertTrue(finished)
        XCTAssertEqual(session.phase, .finished)
        XCTAssertEqual(session.step(right), [], "nothing happens after the end")
    }

    func testManualRestartDoesNotCountAsDeath() throws {
        let (session, progress) = try makeSession()
        session.step(right)
        session.restart()
        XCTAssertEqual(progress.totalDeaths, 0)
        XCTAssertEqual(session.player.position, session.world.spawn)
    }

    func testFrameUpdateRunsFixedSteps() throws {
        let (session, _) = try makeSession()
        session.update(frameDelta: 1.0 / 60.0, input: .none)
        XCTAssertEqual(session.simulation.stepCount, 2)
        session.update(frameDelta: 1.0, input: .none)
        XCTAssertEqual(session.simulation.stepCount, 2 + Constants.maxStepsPerFrame)
    }

    func testHotReloadPicksUpChangedFiles() throws {
        let (session, _) = try makeSession()
        XCTAssertEqual(session.world.grid.width, 8)
        try write(makeLevel([
            "##########",
            "#S......D#",
            "##########",
        ], id: "level_001"))
        try session.reloadLevels()
        XCTAssertEqual(session.world.grid.width, 10)
    }

    func testLoadingLevelResetsVisitDeaths() throws {
        let (session, _) = try makeSession(start: 1)
        for _ in 0..<600 where session.phase == .playing { session.step(right) }
        XCTAssertEqual(session.deathsThisVisit, 1)
        try session.load(levelIndex: 0)
        XCTAssertEqual(session.deathsThisVisit, 0)
        XCTAssertEqual(session.phase, .playing)
    }
}

final class ProgressStoreTests: XCTestCase {
    func testPersistsAcrossInstances() {
        let backing = InMemoryKeyValueStore()
        let a = ProgressStore(store: backing)
        a.recordDeath(levelID: "level_001")
        a.recordDeath(levelID: "level_001")
        a.recordCompletion(levelIndex: 0, levelID: "level_001", time: 12.5, levelCount: 5)
        a.recordCompletion(levelIndex: 0, levelID: "level_001", time: 20, levelCount: 5)

        let b = ProgressStore(store: backing)
        XCTAssertEqual(b.totalDeaths, 2)
        XCTAssertEqual(b.unlockedCount, 2)
        XCTAssertTrue(b.isUnlocked(levelIndex: 1))
        XCTAssertFalse(b.isUnlocked(levelIndex: 2))
        let record = b.record(forLevel: "level_001")
        XCTAssertEqual(record.deaths, 2)
        XCTAssertEqual(record.completions, 2)
        XCTAssertEqual(record.bestTime, 12.5)
        XCTAssertTrue(record.isCompleted)
    }

    func testUnlockNeverExceedsLevelCount() {
        let store = ProgressStore(store: InMemoryKeyValueStore())
        store.recordCompletion(levelIndex: 4, levelID: "level_005", time: 1, levelCount: 5)
        XCTAssertEqual(store.unlockedCount, 5)
    }

    func testReset() {
        let store = ProgressStore(store: InMemoryKeyValueStore())
        store.recordDeath(levelID: "x")
        store.unlockAll(levelCount: 9)
        XCTAssertEqual(store.unlockedCount, 9)
        store.reset()
        XCTAssertEqual(store.progress, Progress())
    }

    func testCorruptDataFallsBackToFreshProgress() {
        let backing = InMemoryKeyValueStore()
        backing.set(Data("nonsense".utf8), forKey: ProgressStore.defaultKey)
        XCTAssertEqual(ProgressStore(store: backing).progress, Progress())
    }
}

final class SolverTests: XCTestCase {
    func testSolvesAGapJump() throws {
        let level = makeLevel([
            "##################",
            "#................#",
            "#................#",
            "#................#",
            "#S..............D#",
            "######...#########",
        ])
        let result = try LevelSolver().solve(level)
        let replay = try XCTUnwrap(result.replay)
        XCTAssertEqual(try replay.play(on: level).status, .won)
    }

    func testReportsImpossibleLevels() throws {
        let level = makeLevel([
            "##########",
            "#....#...#",
            "#....#...#",
            "#....#...#",
            "#S...#..D#",
            "##########",
        ])
        var options = LevelSolver.Options()
        options.maxExpansions = 20_000
        XCTAssertFalse(try LevelSolver(options: options).solve(level).solved)
    }
}

final class GhostTests: XCTestCase {
    func testGhostReplaysSolutionInLockStep() throws {
        let catalog = try LevelCatalog()
        let session = try GameSession(catalog: catalog, progress: ProgressStore(store: InMemoryKeyValueStore()))
        let replay = try XCTUnwrap(session.hintReplay)
        session.showGhost(replay)
        XCTAssertTrue(session.isGhostVisible)
        for _ in 0..<replay.totalSteps { session.step(.none) }
        XCTAssertEqual(session.ghost?.status, .won, "the ghost finishes while the player idles")
        XCTAssertEqual(session.phase, .playing)

        // Restarting restarts the ghost too.
        session.restart()
        XCTAssertEqual(session.ghost?.stepCount, 0)
        session.hideGhost()
        XCTAssertNil(session.ghost)
    }
}

final class EndToEndTests: XCTestCase {
    /// Plays the whole shipped game through `GameSession` (level transitions, progress,
    /// timers) using the recorded solutions, at a jittery 60 Hz frame rate.
    func testAutopilotFinishesTheWholeGame() throws {
        let catalog = try LevelCatalog()
        let progress = ProgressStore(store: InMemoryKeyValueStore())
        let session = try GameSession(catalog: catalog, progress: progress)
        session.autopilot = true
        var frames = 0
        var completed: [Int] = []
        while session.phase != .finished && frames < 60 * 60 * 10 {
            let dt = frames.isMultiple(of: 3) ? 1.0 / 50.0 : 1.0 / 65.0
            for event in session.update(frameDelta: dt, input: .none) {
                if case .levelCompleted(let index, _, _) = event { completed.append(index) }
            }
            frames += 1
        }
        XCTAssertEqual(session.phase, .finished)
        XCTAssertEqual(completed, Array(0..<catalog.count))
        XCTAssertEqual(progress.totalDeaths, 0, "the recorded solutions never die")
        XCTAssertEqual(progress.unlockedCount, catalog.count)
    }
}
