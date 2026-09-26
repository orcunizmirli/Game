import SpriteKit
import UIKit
import GameCore

/// What the SwiftUI HUD shows. Published only when it changes.
struct HUDState: Equatable {
    var levelIndex = 0
    var levelCount = 0
    var levelName = ""
    var levelDeaths = 0
    var visitDeaths = 0
    var controlsInverted = false
    var finished = false
    var hintAvailable = false
    var ghostVisible = false
}

@MainActor
protocol GameSceneDelegate: AnyObject {
    func gameScene(_ scene: GameScene, didUpdate hud: HUDState)
    func gameScene(_ scene: GameScene, didReceive events: [GameEvent])
    func gameSceneRequestedPause(_ scene: GameScene)
}

/// Hosts the simulation: samples input, advances the `GameSession`, and keeps the
/// SpriteKit node tree in sync with the (pure Swift) game state.
@MainActor
final class GameScene: SKScene {
    let session: GameSession
    weak var gameDelegate: GameSceneDelegate?

    /// Deaths on the current level before the hint button appears.
    static let hintThreshold = 5

    private let input = InputRouter()
    private let worldContainer = SKNode()
    private let effectsLayer = SKNode()
    private let controls = TouchControlsNode()
    private var worldNode: WorldNode?
    private var renderedGeneration = -1
    private var lastUpdateTime: TimeInterval?
    private var lastHUD: HUDState?
    private var tile: CGFloat = 32
    private var shakeRemaining: TimeInterval = 0
    private var laidOutSize = CGSize.zero
    private var laidOutInsets = UIEdgeInsets.zero
    private(set) var theme = Palette.menu

    /// Space reserved at the top for the SwiftUI HUD.
    private let hudHeight: CGFloat = 44

    #if DEBUG
    private let debugOverlay = DebugOverlayNode()
    var showsDebugOverlay = false {
        didSet {
            debugOverlay.isHidden = !showsDebugOverlay
            view?.showsFPS = showsDebugOverlay
            view?.showsNodeCount = showsDebugOverlay
            view?.showsDrawCount = showsDebugOverlay
            renderedGeneration = -1
        }
    }
    #endif

    /// Freezes gameplay (rendering continues so the pause menu can sit on top).
    var isGameplayPaused = false {
        didSet {
            lastUpdateTime = nil
            input.reset()
        }
    }

    init(session: GameSession) {
        self.session = session
        super.init(size: CGSize(width: 844, height: 390))
        scaleMode = .resizeFill
        anchorPoint = .zero
        worldContainer.zPosition = 0
        effectsLayer.zPosition = 50
        controls.zPosition = 100
        addChild(worldContainer)
        worldContainer.addChild(effectsLayer)
        addChild(controls)
        #if DEBUG
        debugOverlay.zPosition = 60
        debugOverlay.isHidden = true
        worldContainer.addChild(debugOverlay)
        #endif
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 120
        relayoutIfNeeded(force: true)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        relayoutIfNeeded(force: false)
    }

    // MARK: Layout

    private var safeInsets: UIEdgeInsets { view?.safeAreaInsets ?? .zero }

    private func relayoutIfNeeded(force: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        let insets = safeInsets
        guard force || size != laidOutSize || insets != laidOutInsets else { return }
        laidOutSize = size
        laidOutInsets = insets

        let layout = touchLayout
        controls.layout(layout, origin: CGPoint(x: insets.left, y: insets.bottom), theme: theme)
        renderedGeneration = -1 // rebuild the world at the new tile size
    }

    private var touchLayout: TouchLayout {
        let insets = safeInsets
        return TouchLayout(width: Double(size.width - insets.left - insets.right),
                           height: Double(size.height - insets.bottom))
    }

    /// Picks a tile size that fits the level's height (and width, up to 32 columns).
    private func computeTileSize(for grid: TileGrid) -> CGFloat {
        let insets = safeInsets
        let availableW = size.width - insets.left - insets.right - 8
        let availableH = size.height - hudHeight - max(insets.bottom, 4)
        let byHeight = availableH / CGFloat(grid.height)
        let byWidth = availableW / CGFloat(min(grid.width, 32))
        return max(8, floor(min(byHeight, byWidth)))
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime.map { min(currentTime - $0, 0.25) } ?? 0
        lastUpdateTime = currentTime

        handle(commands: input.pollCommands())

        let frameInput = input.poll()
        controls.highlight(input.touches.activeZones)
        controls.isHidden = input.hasGamepad

        var events: [GameEvent] = []
        if !isGameplayPaused {
            events = session.update(frameDelta: dt, input: frameInput)
        }

        if session.generation != renderedGeneration {
            react(to: events)
            rebuildWorld()
        } else if let worldNode {
            // Tiles removed by a collapse fall away as debris; other removals just vanish.
            var crumbled = Set<GridPoint>()
            for event in events {
                if case .world(.tilesRemoved(let points)) = event { crumbled.formUnion(points) }
            }
            worldNode.sync(with: session.simulation, dt: CGFloat(dt), crumbled: crumbled, debrisLayer: effectsLayer)
            react(to: events)
        }
        worldNode?.syncGhost(session.ghost, dt: CGFloat(dt))
        updateCamera(dt: dt)

        #if DEBUG
        if showsDebugOverlay { debugOverlay.sync(with: session, tile: tile) }
        #endif

        if !events.isEmpty { gameDelegate?.gameScene(self, didReceive: events) }
        publishHUD()
    }

    private func rebuildWorld() {
        renderedGeneration = session.generation
        let simulation = session.simulation
        theme = Palette.theme(for: simulation.level, index: session.levelIndex)
        backgroundColor = theme.background
        tile = computeTileSize(for: simulation.world.grid)

        worldNode?.removeFromParent()
        let node = WorldNode(simulation: simulation, tile: tile, theme: theme)
        node.zPosition = 1
        worldContainer.addChild(node)
        worldNode = node

        controls.layout(touchLayout, origin: CGPoint(x: safeInsets.left, y: safeInsets.bottom), theme: theme)
        #if DEBUG
        debugOverlay.rebuild(for: session, tile: tile)
        #endif
        updateCamera(dt: 0)
    }

    private func updateCamera(dt: TimeInterval) {
        guard let worldNode else { return }
        let insets = safeInsets
        let levelSize = worldNode.levelSize
        let availableW = size.width - insets.left - insets.right
        let bottom = max(insets.bottom, 4)
        let availableH = size.height - hudHeight - bottom

        var x = insets.left + (availableW - levelSize.width) / 2
        if levelSize.width > availableW {
            // Wide level: follow the player, clamped to the level edges.
            let playerX = CGFloat(session.player.position.x) * tile
            let desired = insets.left + availableW / 2 - playerX
            x = min(insets.left, max(insets.left + availableW - levelSize.width, desired))
        }
        let y = bottom + max(0, (availableH - levelSize.height) / 2)
        var origin = CGPoint(x: x.rounded(), y: y.rounded())

        if shakeRemaining > 0 {
            shakeRemaining -= dt
            let m = tile * 0.12
            origin.x += CGFloat.random(in: -m...m)
            origin.y += CGFloat.random(in: -m...m)
        }
        worldContainer.position = origin
    }

    private func react(to events: [GameEvent]) {
        guard let worldNode else { return }
        for event in events {
            switch event {
            case .jumped:
                worldNode.player.jumped()
            case .landed:
                worldNode.player.landed()
                let p = session.player.position
                Effects.dust(at: CGPoint(x: p.x * tile, y: p.y * tile), tile: tile, theme: theme, into: effectsLayer)
            case .died(_, let at):
                Effects.deathBurst(at: CGPoint(x: at.x * tile, y: at.y * tile), tile: tile, theme: theme, into: effectsLayer)
                shakeRemaining = 0.15
            case .reachedDoor:
                let d = session.world.door.position
                Effects.celebrate(at: CGPoint(x: (d.x + 0.5) * tile, y: (d.y + 0.5) * tile),
                                  tile: tile, theme: theme, into: effectsLayer)
                worldNode.doorCelebration()
            case .world(.blocksReleased), .world(.tilesRemoved):
                shakeRemaining = max(shakeRemaining, 0.08)
            default:
                break
            }
        }
    }

    private func publishHUD() {
        var hud = HUDState()
        hud.levelIndex = session.levelIndex
        hud.levelCount = session.levelCount
        hud.levelName = session.level.name
        hud.levelDeaths = session.levelDeaths
        hud.visitDeaths = session.deathsThisVisit
        hud.controlsInverted = session.world.controlsInverted
        hud.finished = session.phase == .finished
        hud.hintAvailable = session.deathsThisVisit >= Self.hintThreshold && session.hintReplay != nil
        hud.ghostVisible = session.isGhostVisible
        guard hud != lastHUD else { return }
        lastHUD = hud
        gameDelegate?.gameScene(self, didUpdate: hud)
    }

    // MARK: Commands

    func restartLevel() {
        session.restart()
    }

    func toggleGhost() {
        if session.isGhostVisible {
            session.hideGhost()
        } else if let replay = session.hintReplay {
            session.showGhost(replay)
            session.restart()
        }
    }

    func reloadLevels() {
        #if DEBUG
        do {
            try session.reloadLevels()
        } catch {
            print("Level reload failed: \(error)")
        }
        #endif
    }

    private func handle(commands: InputRouter.Commands) {
        if commands.contains(.pause) { gameDelegate?.gameSceneRequestedPause(self) }
        guard !isGameplayPaused else { return }
        if commands.contains(.restart) { restartLevel() }
        #if DEBUG
        if commands.contains(.toggleDebug) { showsDebugOverlay.toggle() }
        if commands.contains(.reloadLevels) { reloadLevels() }
        #endif
    }

    // MARK: Touches

    private func touchPoint(_ touch: UITouch) -> Vec2 {
        let p = touch.location(in: self)
        return Vec2(Double(p.x - safeInsets.left), Double(p.y - safeInsets.bottom))
    }

    private func touchID(_ touch: UITouch) -> Int {
        ObjectIdentifier(touch).hashValue
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isGameplayPaused else { return }
        let layout = touchLayout
        for touch in touches {
            input.touches.began(id: touchID(touch), at: touchPoint(touch), layout: layout)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let layout = touchLayout
        for touch in touches {
            input.touches.moved(id: touchID(touch), to: touchPoint(touch), layout: layout)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { input.touches.ended(id: touchID(touch)) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { input.touches.ended(id: touchID(touch)) }
    }
}
