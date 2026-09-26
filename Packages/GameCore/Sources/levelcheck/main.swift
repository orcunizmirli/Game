import Foundation
import GameCore

// Level tooling. Run from the repo root:
//
//   swift run -c release --package-path Packages/GameCore levelcheck validate
//   swift run -c release --package-path Packages/GameCore levelcheck solve --write
//   swift run -c release --package-path Packages/GameCore levelcheck replay level_003 --trace
//   swift run -c release --package-path Packages/GameCore levelcheck render level_003
//   swift run -c release --package-path Packages/GameCore levelcheck physics

let usage = """
usage: levelcheck <command> [level ids...] [options]

commands:
  validate            parse and statically check every level
  solve [--write]     search for a solution for each level (writes Levels/solutions/<id>.txt)
  replay [--trace]    replay stored solutions and check they still win
  render              print the grid with trap zones and effect targets
  physics             print derived jump metrics

options:
  --dir <path>        levels directory (default: the source tree)
  --max <n>           solver expansion limit
  --pos <n>           solver position buckets per tile (default 8)
  --weight <w>        solver heuristic weight (default 1.6)
"""

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print(usage)
    exit(1)
}
args.removeFirst()

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let value = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return value
}

func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

let dir = option("--dir").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? LevelCatalog.sourceDirectory
let maxExpansions = option("--max").flatMap(Int.init)
let positionResolution = option("--pos").flatMap(Double.init)
let heuristicWeight = option("--weight").flatMap(Double.init)
let write = flag("--write")
let trace = flag("--trace")
let filter = Set(args)

func loadLevels() -> [Level] {
    do {
        let catalog = try LevelCatalog(source: .directory(dir))
        return try catalog.allLevels().filter { filter.isEmpty || filter.contains($0.id) }
    } catch {
        print("error: \(error)")
        exit(1)
    }
}

func solutionURL(_ id: String) -> URL {
    dir.appendingPathComponent("solutions/\(id).txt")
}

func format(_ seconds: Double) -> String {
    String(format: "%.2fs", seconds)
}

var failures = 0

switch command {
case "validate":
    for level in loadLevels() {
        let issues = WorldBuilder.validate(level)
        let errors = issues.filter(\.isError).count
        print("\(level.id) \"\(level.name)\" \(level.width)x\(level.height), \(level.traps.count) traps: \(errors == 0 ? "ok" : "FAILED")")
        for issue in issues { print("  \(issue)") }
        if errors > 0 { failures += 1 }
    }

case "solve":
    var options = LevelSolver.Options()
    if let maxExpansions { options.maxExpansions = maxExpansions }
    if let positionResolution { options.positionResolution = positionResolution }
    if let heuristicWeight { options.heuristicWeight = heuristicWeight }
    let solver = LevelSolver(options: options)
    for level in loadLevels() {
        let started = Date()
        do {
            let result = try solver.solve(level)
            let elapsed = Date().timeIntervalSince(started)
            if let replay = result.replay {
                print("\(level.id): solved in \(format(replay.duration)) game time (\(result.expansions) states, \(format(elapsed)))")
                print("  \(replay)")
                if write {
                    try FileManager.default.createDirectory(at: solutionURL(level.id).deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    try (replay.description + "\n").write(to: solutionURL(level.id), atomically: true, encoding: .utf8)
                }
            } else {
                print("\(level.id): NO SOLUTION (\(result.expansions) states, \(format(elapsed)))")
                failures += 1
            }
        } catch {
            print("\(level.id): error \(error)")
            failures += 1
        }
    }

case "replay":
    for level in loadLevels() {
        guard let text = try? String(contentsOf: solutionURL(level.id), encoding: .utf8) else {
            print("\(level.id): no stored solution")
            failures += 1
            continue
        }
        do {
            let replay = try InputReplay(text.trimmingCharacters(in: .whitespacesAndNewlines))
            var sim = try Simulation(level: level)
            var step = 0
            for input in replay.inputs {
                let events = sim.step(input)
                step += 1
                if trace {
                    let p = sim.player
                    let marks = events.compactMap { e -> String? in
                        switch e {
                        case .world(let w): return "\(w)"
                        case .jumped: return "jump"
                        case .died(let c, _): return "DIED(\(c))"
                        case .reachedDoor: return "DOOR"
                        default: return nil
                        }
                    }
                    if step % 6 == 0 || !marks.isEmpty {
                        print(String(format: "  %5.2fs x=%6.2f y=%6.2f vx=%6.2f vy=%6.2f %@ %@",
                                     sim.time, p.position.x, p.position.y, p.velocity.x, p.velocity.y,
                                     p.isGrounded ? "G" : " ", marks.joined(separator: ", ")))
                    }
                }
                if !sim.isRunning { break }
            }
            let ok = sim.status == .won
            print("\(level.id): \(ok ? "ok" : "FAILED (\(sim.status))") after \(format(sim.time))")
            if !ok { failures += 1 }
        } catch {
            print("\(level.id): error \(error)")
            failures += 1
        }
    }

case "render":
    for level in loadLevels() {
        print("\(level.id) \"\(level.name)\"")
        guard let world = try? WorldBuilder.build(level) else {
            print("  cannot build")
            failures += 1
            continue
        }
        var canvas = world.grid.rows().map { Array($0) }
        let h = world.grid.height
        func mark(_ p: GridPoint, _ c: Character) {
            let row = h - 1 - p.y
            guard row >= 0, row < canvas.count, p.x >= 0, p.x < canvas[row].count else { return }
            canvas[row][p.x] = c
        }
        for trap in level.traps {
            if case .zone(let rect) = trap.trigger {
                for p in rect.gridPoints where world.grid[p] == .empty { mark(p, "z") }
            }
            for effect in trap.effects {
                for p in effect.referencedTiles {
                    switch effect {
                    case .collapse: mark(p, "c")
                    case .spawnSpikes: mark(p, "s")
                    case .moveDoor: mark(p, "d")
                    case .dropCeiling: mark(p, "f")
                    case .addTiles: mark(p, "a")
                    case .slideTiles: mark(p, "m")
                    default: break
                    }
                }
            }
        }
        mark(GridPoint(Int(world.spawn.x), Int(world.spawn.y)), "S")
        mark(GridPoint(Int(world.door.position.x), Int(world.door.position.y)), "D")
        for (i, row) in canvas.enumerated() {
            print(String(format: "%3d ", h - 1 - i) + String(row))
        }
        print("    " + String((0..<world.grid.width).map { Character(String($0 % 10)) }))
        print("  legend: z trigger zone, c collapse, s spikes, d door target, f falling, a appears, m slides")
    }

case "physics":
    let t = PhysicsTuning.standard
    var sim = try Simulation(level: Level(id: "flat", grid: [
        "..............................",
        "S............................D",
        "##############################",
    ]))
    for _ in 0..<30 { sim.step(.none) }
    let groundY = sim.player.position.y
    var peak = groundY
    var airSteps = 0
    var startX = sim.player.position.x
    sim.step(InputState(right: true, jumpPressed: true, jumpHeld: true))
    startX = sim.player.position.x
    while !sim.player.isGrounded {
        sim.step(InputState(right: true, jumpHeld: true))
        peak = max(peak, sim.player.position.y)
        airSteps += 1
    }
    print("full jump height:   \(String(format: "%.3f", peak - groundY)) tiles (analytic \(String(format: "%.3f", t.fullJumpHeight)))")
    print("air time:           \(format(Double(airSteps) * Constants.fixedDt))")
    print("jump distance:      \(String(format: "%.2f", sim.player.position.x - startX)) tiles at full speed (from standstill)")
    print("run speed:          \(t.runSpeed) tiles/s")

default:
    print(usage)
    exit(1)
}

exit(failures == 0 ? 0 : 1)
