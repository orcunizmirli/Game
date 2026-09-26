import SwiftUI
import GameCore

/// App-wide state: navigation, level catalog and saved progress.
@MainActor
final class AppModel: ObservableObject {
    enum Screen: Equatable {
        case menu
        case levels
        case settings
        case playing(level: Int)
    }

    @Published var screen: Screen = .menu
    /// Bumped whenever progress changes so menus refresh.
    @Published private(set) var progressVersion = 0

    let progress: ProgressStore
    let catalog: LevelCatalog?
    let loadError: String?
    /// Debug builds launched with `-demoLevel N` start level N on autopilot (used by CI to
    /// take screenshots of real gameplay).
    private(set) var demoMode = false

    init() {
        _ = SoundEngine.shared // synthesize sounds up front, not on the first jump
        progress = ProgressStore()
        do {
            catalog = try Self.makeCatalog()
            loadError = nil
        } catch {
            catalog = nil
            loadError = "\(error)"
        }
        #if DEBUG
        let demoLevel = UserDefaults.standard.integer(forKey: "demoLevel")
        if demoLevel > 0 && demoLevel <= levelCount {
            demoMode = true
            screen = .playing(level: demoLevel - 1)
        }
        #endif
    }

    private static func makeCatalog() throws -> LevelCatalog {
        #if DEBUG && targetEnvironment(simulator)
        // The simulator can read the Mac's file system, so debug builds load levels straight
        // from the source tree. Edit a JSON file, press L (or the reload button) in game.
        let source = LevelCatalog.sourceDirectory
        if FileManager.default.fileExists(atPath: source.path) {
            return try LevelCatalog(source: .directory(source))
        }
        #endif
        return try LevelCatalog()
    }

    var levelCount: Int { catalog?.count ?? 0 }

    func levelName(_ index: Int) -> String {
        (try? catalog?.level(at: index))?.name ?? "Level \(index + 1)"
    }

    func levelID(_ index: Int) -> String {
        (try? catalog?.level(at: index))?.id ?? ""
    }

    /// First unlocked level that has not been completed yet (or the last level).
    var continueLevel: Int {
        let unlocked = min(progress.unlockedCount, levelCount)
        for i in 0..<unlocked where !progress.record(forLevel: levelID(i)).isCompleted {
            return i
        }
        return max(0, unlocked - 1)
    }

    var completedCount: Int {
        (0..<levelCount).filter { progress.record(forLevel: levelID($0)).isCompleted }.count
    }

    var hasStarted: Bool {
        progress.totalDeaths > 0 || completedCount > 0
    }

    func play(_ index: Int) {
        screen = .playing(level: index)
    }

    func progressChanged() {
        progressVersion += 1
    }

    func resetProgress() {
        progress.reset()
        progressChanged()
    }

    func unlockAll() {
        progress.unlockAll(levelCount: levelCount)
        progressChanged()
    }
}
