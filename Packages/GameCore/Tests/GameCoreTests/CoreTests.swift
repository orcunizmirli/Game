import XCTest
@testable import GameCore

final class GeometryTests: XCTestCase {
    func testTouchingBoxesDoNotIntersect() {
        let a = AABB(x: 0, y: 0, width: 1, height: 1)
        XCTAssertFalse(a.intersects(AABB(x: 1, y: 0, width: 1, height: 1)))
        XCTAssertFalse(a.intersects(AABB(x: 0, y: 1, width: 1, height: 1)))
        XCTAssertTrue(a.intersects(AABB(x: 0.99, y: 0.5, width: 1, height: 1)))
        XCTAssertTrue(a.touches(AABB(x: 1, y: 0, width: 1, height: 1)))
    }

    func testTileRectGridPoints() {
        let rect = TileRect(x: 2, y: 1, width: 3, height: 2)
        XCTAssertEqual(rect.gridPoints.count, 6)
        XCTAssertTrue(rect.gridPoints.contains(GridPoint(4, 2)))
        XCTAssertFalse(rect.gridPoints.contains(GridPoint(5, 2)))
    }

    func testJSONShapes() throws {
        let p = try JSONDecoder().decode(GridPoint.self, from: Data("[3, 4]".utf8))
        XCTAssertEqual(p, GridPoint(3, 4))
        let r = try JSONDecoder().decode(TileRect.self, from: Data("[1, 2, 3, 4]".utf8))
        XCTAssertEqual(r, TileRect(x: 1, y: 2, width: 3, height: 4))
        XCTAssertThrowsError(try JSONDecoder().decode(TileRect.self, from: Data("[1, 2, 0, 4]".utf8)))
    }

    func testApproach() {
        XCTAssertEqual(approach(0, 10, 3), 3)
        XCTAssertEqual(approach(9, 10, 3), 10)
        XCTAssertEqual(approach(0, -10, 3), -3)
        XCTAssertEqual(approach(5, 5, 3), 5)
    }
}

final class FixedTimestepTests: XCTestCase {
    func testOneStepPerFrameAt120Hz() {
        var ts = FixedTimestep()
        var total = 0
        for _ in 0..<1200 { total += ts.advance(by: 1.0 / 120.0) }
        XCTAssertEqual(total, 1200)
    }

    func testTwoStepsPerFrameAt60Hz() {
        var ts = FixedTimestep()
        for _ in 0..<600 { XCTAssertEqual(ts.advance(by: 1.0 / 60.0), 2) }
    }

    func testJitterAveragesOut() {
        var ts = FixedTimestep()
        var total = 0
        for i in 0..<1200 {
            // ±10% jitter around 120 Hz
            total += ts.advance(by: (1.0 / 120.0) * (i.isMultiple(of: 2) ? 1.1 : 0.9))
        }
        XCTAssertEqual(total, 1200, accuracy: 1)
    }

    func testSpiralOfDeathClamp() {
        var ts = FixedTimestep()
        XCTAssertEqual(ts.advance(by: 2.0), Constants.maxStepsPerFrame)
        XCTAssertEqual(ts.accumulator, 0)
        XCTAssertEqual(ts.advance(by: 1.0 / 120.0), 1)
    }

    func testIgnoresInvalidDeltas() {
        var ts = FixedTimestep()
        XCTAssertEqual(ts.advance(by: 0), 0)
        XCTAssertEqual(ts.advance(by: -1), 0)
        XCTAssertEqual(ts.advance(by: .nan), 0)
    }
}

final class InputTests: XCTestCase {
    func testLatchKeepsPressAcrossZeroStepFrames() {
        var latch = InputLatch()
        latch.submit(InputState(jumpPressed: true, jumpHeld: true))
        // This frame ran no step. Next frame the button is merely held.
        latch.submit(InputState(jumpHeld: true))
        let first = latch.next()
        XCTAssertTrue(first.jumpPressed)
        XCTAssertFalse(latch.next().jumpPressed, "a press is delivered to exactly one step")
    }

    func testMirroredSwapsDirections() {
        let input = InputState(left: true, jumpHeld: true).mirrored
        XCTAssertTrue(input.right)
        XCTAssertFalse(input.left)
        XCTAssertTrue(input.jumpHeld)
    }

    func testMergedIsLogicalOr() {
        let a = InputState(left: true)
        let b = InputState(jumpPressed: true, jumpHeld: true)
        XCTAssertEqual(a.merged(with: b), InputState(left: true, jumpPressed: true, jumpHeld: true))
    }

    func testButtonEdge() {
        var edge = ButtonEdge()
        XCTAssertTrue(edge.update(isDown: true))
        XCTAssertFalse(edge.update(isDown: true))
        XCTAssertFalse(edge.update(isDown: false))
        XCTAssertTrue(edge.update(isDown: true))
    }
}

final class TouchControlsTests: XCTestCase {
    let layout = TouchLayout(width: 800, height: 400)

    func testZones() {
        XCTAssertEqual(layout.zone(for: Vec2(20, 50)), .left)
        XCTAssertEqual(layout.zone(for: Vec2(layout.leftRightSplit + 5, 50)), .right)
        XCTAssertEqual(layout.zone(for: Vec2(399, 300)), .right)
        XCTAssertEqual(layout.zone(for: Vec2(401, 300)), .jump)
    }

    func testButtonsSitInsideTheirZones() {
        XCTAssertEqual(layout.zone(for: layout.leftButtonCenter), .left)
        XCTAssertEqual(layout.zone(for: layout.rightButtonCenter), .right)
        XCTAssertEqual(layout.zone(for: layout.jumpButtonCenter), .jump)
    }

    func testMultiTouchRunAndJump() {
        var tracker = TouchTracker()
        tracker.began(id: 1, at: layout.rightButtonCenter, layout: layout)
        tracker.began(id: 2, at: layout.jumpButtonCenter, layout: layout)
        let input = tracker.poll()
        XCTAssertTrue(input.right)
        XCTAssertTrue(input.jumpPressed)
        XCTAssertTrue(input.jumpHeld)
        let next = tracker.poll()
        XCTAssertFalse(next.jumpPressed)
        XCTAssertTrue(next.jumpHeld)
        tracker.ended(id: 2)
        XCTAssertFalse(tracker.poll().jumpHeld)
    }

    func testSlidingBetweenArrows() {
        var tracker = TouchTracker()
        tracker.began(id: 1, at: layout.leftButtonCenter, layout: layout)
        XCTAssertTrue(tracker.poll().left)
        tracker.moved(id: 1, to: layout.rightButtonCenter, layout: layout)
        let input = tracker.poll()
        XCTAssertTrue(input.right)
        XCTAssertFalse(input.left)
        // Sliding into the jump half keeps steering right instead of jumping.
        tracker.moved(id: 1, to: Vec2(700, 50), layout: layout)
        XCTAssertEqual(tracker.poll(), InputState(right: true))
    }

    func testQuickTapStillJumps() {
        var tracker = TouchTracker()
        tracker.began(id: 7, at: Vec2(700, 100), layout: layout)
        tracker.ended(id: 7)
        let input = tracker.poll()
        XCTAssertTrue(input.jumpPressed)
    }
}

final class EventBusTests: XCTestCase {
    func testEventsAreDeliveredOnDispatch() {
        var bus = EventBus()
        bus.emit("a")
        XCTAssertFalse(bus.didReceive("a"))
        bus.dispatch()
        XCTAssertTrue(bus.didReceive("a"))
        bus.dispatch()
        XCTAssertFalse(bus.didReceive("a"), "events live for exactly one step")
        XCTAssertEqual(bus.history, ["a"])
    }
}

final class ReplayTests: XCTestCase {
    func testParseAndPrintRoundTrip() throws {
        let text = "R30 RP1 RH20 N12 L5 LP1"
        let replay = try InputReplay(text)
        XCTAssertEqual(replay.description, text)
        XCTAssertEqual(replay.totalSteps, 69)
        let inputs = replay.inputs
        XCTAssertEqual(inputs[30], InputState(right: true, jumpPressed: true, jumpHeld: true))
        XCTAssertEqual(inputs[31], InputState(right: true, jumpHeld: true))
        XCTAssertEqual(inputs[51], InputState.none)
    }

    func testMergesAdjacentSegments() throws {
        XCTAssertEqual(try InputReplay("R3 R4 RH2 RH1").description, "R7 RH3")
        XCTAssertEqual(try InputReplay("RP1 RP1").description, "RP1 RP1", "separate presses are kept")
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try InputReplay("X3"))
        XCTAssertThrowsError(try InputReplay("R"))
        XCTAssertThrowsError(try InputReplay("R0"))
    }
}
