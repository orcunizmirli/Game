import SwiftUI
import UIKit
import GameCore

/// Bridges the SpriteKit scene and the SwiftUI overlay (HUD, pause menu, banners).
@MainActor
final class GameViewModel: ObservableObject {
    @Published private(set) var hud = HUDState()
    @Published private(set) var banner: String?
    @Published var isPaused = false {
        didSet { scene?.isGameplayPaused = isPaused }
    }
    #if DEBUG
    @Published var showsDebugOverlay = false {
        didSet { scene?.showsDebugOverlay = showsDebugOverlay }
    }
    #endif

    let scene: GameScene?
    let error: String?
    private weak var app: AppModel?
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()
    private var bannerTask: Task<Void, Never>?

    init(app: AppModel, startLevel: Int) {
        self.app = app
        if let catalog = app.catalog {
            do {
                let session = try GameSession(catalog: catalog, progress: app.progress, startLevel: startLevel)
                scene = GameScene(session: session)
                error = nil
            } catch {
                scene = nil
                self.error = "\(error)"
            }
        } else {
            scene = nil
            error = app.loadError ?? "Levels could not be loaded."
        }
        scene?.gameDelegate = self
        if let scene {
            scene.session.autopilot = app.demoMode
            showBanner(for: scene.session.levelIndex)
        }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debugOverlay") {
            showsDebugOverlay = true
            scene?.showsDebugOverlay = true
        }
        #endif
    }

    private var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.haptics) as? Bool ?? true
    }

    private var soundEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.sound) as? Bool ?? true
    }

    private var hintsEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.hints) as? Bool ?? true
    }

    var theme: Theme { scene?.theme ?? Palette.menu }

    var showsHintButton: Bool {
        hintsEnabled && (hud.hintAvailable || hud.ghostVisible)
    }

    // MARK: Actions

    func pause() { isPaused = true }

    func resume() { isPaused = false }

    func restart() {
        scene?.restartLevel()
        isPaused = false
    }

    func toggleGhost() {
        scene?.toggleGhost()
    }

    func reloadLevels() {
        scene?.reloadLevels()
    }

    func quitToMenu() {
        app?.progressChanged()
        app?.screen = .menu
    }

    func quitToLevels() {
        app?.progressChanged()
        app?.screen = .levels
    }

    private func showBanner(for index: Int) {
        guard let scene else { return }
        let text = "\(index + 1). \(scene.session.level.name)"
        banner = text
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            if self?.banner == text { self?.banner = nil }
        }
    }
}

extension GameViewModel: GameSceneDelegate {
    func gameScene(_ scene: GameScene, didUpdate hud: HUDState) {
        self.hud = hud
    }

    func gameScene(_ scene: GameScene, didReceive events: [GameEvent]) {
        let sound = SoundEngine.shared
        sound.isEnabled = soundEnabled
        for event in events {
            switch event {
            case .jumped:
                sound.play(.jump)
            case .landed:
                sound.play(.land)
            case .world(.tilesRemoved), .world(.blocksReleased), .world(.doorMoving):
                sound.play(.trap)
            case .world(.spikesSpawned), .world(.tilesAdded):
                sound.play(.spikes)
            case .died:
                sound.play(.death)
                if hapticsEnabled { impact.impactOccurred() }
            case .reachedDoor:
                sound.play(.door)
                if hapticsEnabled { notification.notificationOccurred(.success) }
            case .levelStarted(let index):
                showBanner(for: index)
                app?.progressChanged()
            case .gameFinished:
                app?.progressChanged()
            default:
                break
            }
        }
    }

    func gameSceneRequestedPause(_ scene: GameScene) {
        isPaused.toggle()
    }
}

enum SettingsKeys {
    static let sound = "settings.sound"
    static let haptics = "settings.haptics"
    static let hints = "settings.hints"
}
