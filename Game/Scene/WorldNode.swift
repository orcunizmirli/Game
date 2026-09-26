import SpriteKit
import GameCore

/// Draws one `Simulation`: tiles, spikes, door, moving blocks and the player.
///
/// Built once per level attempt (the session rebuilds the world on every restart) and then
/// synced every frame. Tile changes are detected through `TileGrid.revision` and applied as
/// a diff, so no trap event can ever be missed.
final class WorldNode: SKNode {
    let tile: CGFloat
    let theme: Theme
    let player: PlayerNode
    private(set) var ghost: PlayerNode?

    private var tileNodes: [GridPoint: (kind: TileKind, node: SKNode)] = [:]
    private var blockNodes: [Int: SKNode] = [:]
    private let door: SKSpriteNode
    private var gridRevision: Int
    private let spikeTexture: SKTexture
    private let tileLayer = SKNode()
    private let dynamicLayer = SKNode()
    private let gridWidth: Int
    private let gridHeight: Int

    init(simulation: Simulation, tile: CGFloat, theme: Theme) {
        self.tile = tile
        self.theme = theme
        spikeTexture = TextureFactory.spikes(tile: tile, color: theme.ink)
        player = PlayerNode(tile: tile, playerSize: simulation.player.size, theme: theme)
        door = SKSpriteNode(texture: TextureFactory.door(tile: tile, ink: theme.ink, glow: theme.doorGlow))
        gridRevision = simulation.world.grid.revision
        gridWidth = simulation.world.grid.width
        gridHeight = simulation.world.grid.height
        super.init()

        tileLayer.zPosition = 0
        dynamicLayer.zPosition = 5
        addChild(tileLayer)
        addChild(dynamicLayer)

        door.anchorPoint = CGPoint(x: 0.5, y: 0)
        door.zPosition = 3
        addChild(door)

        player.zPosition = 10
        addChild(player)

        let grid = simulation.world.grid
        for p in grid.points where grid[p] != .empty {
            addTile(grid[p], at: p, animated: false)
        }
        sync(with: simulation, dt: 0)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Size of the level in points.
    var levelSize: CGSize {
        CGSize(width: CGFloat(gridWidth) * tile, height: CGFloat(gridHeight) * tile)
    }

    func point(_ v: Vec2) -> CGPoint {
        CGPoint(x: v.x * tile, y: v.y * tile)
    }

    // MARK: Tiles

    private func makeNode(for kind: TileKind) -> SKNode? {
        switch kind {
        case .empty, .hidden:
            return nil
        case .solid, .fake, .revealed:
            // Slight overlap hides hairline seams between neighbouring tiles.
            let node = SKSpriteNode(color: theme.ink, size: CGSize(width: tile + 0.6, height: tile + 0.6))
            node.anchorPoint = CGPoint(x: 0, y: 0)
            return node
        case .spikeUp, .spikeDown, .spikeLeft, .spikeRight:
            let node = SKSpriteNode(texture: spikeTexture)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            switch kind.spikeDirection {
            case .down: node.zRotation = .pi
            case .left: node.zRotation = .pi / 2
            case .right: node.zRotation = -.pi / 2
            default: break
            }
            let holder = SKNode()
            node.position = CGPoint(x: tile / 2, y: tile / 2)
            holder.addChild(node)
            return holder
        }
    }

    private func addTile(_ kind: TileKind, at p: GridPoint, animated: Bool) {
        guard let node = makeNode(for: kind) else {
            tileNodes[p] = (kind, SKNode())
            return
        }
        node.position = point(Vec2(Double(p.x), Double(p.y)))
        tileLayer.addChild(node)
        tileNodes[p] = (kind, node)
        guard animated else { return }
        if kind.isHazard {
            // Spikes shoot out of the ground.
            let spike = node.children.first ?? node
            spike.setScale(0.1)
            spike.run(.scale(to: 1, duration: 0.06))
        } else {
            node.setScale(0.6)
            node.position.x += tile * 0.2
            node.position.y += tile * 0.2
            node.run(.group([
                .scale(to: 1, duration: 0.08),
                .move(to: point(Vec2(Double(p.x), Double(p.y))), duration: 0.08),
            ]))
        }
    }

    /// Diffs the grid against the drawn tiles. Removed tiles listed in `crumbled` fall away
    /// as debris; others (tiles that turned into moving blocks) just disappear.
    private func syncTiles(_ grid: TileGrid, crumbled: Set<GridPoint>, debrisLayer: SKNode?) {
        guard grid.revision != gridRevision else { return }
        gridRevision = grid.revision
        for p in grid.points {
            let kind = grid[p]
            let current = tileNodes[p]?.kind ?? .empty
            guard kind != current else { continue }
            if let old = tileNodes[p]?.node {
                if crumbled.contains(p), let debrisLayer, current.looksSolid || current.isHazard {
                    Effects.debris(from: old, tile: tile, into: debrisLayer, in: self)
                }
                old.removeFromParent()
                tileNodes[p] = nil
            }
            if kind != .empty {
                addTile(kind, at: p, animated: true)
            }
        }
    }

    // MARK: Frame sync

    func sync(with simulation: Simulation, dt: CGFloat, crumbled: Set<GridPoint> = [], debrisLayer: SKNode? = nil) {
        let world = simulation.world
        syncTiles(world.grid, crumbled: crumbled, debrisLayer: debrisLayer)

        // Moving blocks.
        var alive = Set<Int>()
        for block in world.blocks {
            alive.insert(block.id)
            let node: SKNode
            if let existing = blockNodes[block.id] {
                node = existing
            } else {
                let sprite = SKSpriteNode(color: theme.ink, size: CGSize(width: tile + 0.6, height: tile + 0.6))
                sprite.anchorPoint = .zero
                dynamicLayer.addChild(sprite)
                blockNodes[block.id] = sprite
                node = sprite
            }
            node.position = point(block.position)
        }
        for (id, node) in blockNodes where !alive.contains(id) {
            node.removeFromParent()
            blockNodes[id] = nil
        }

        let doorPosition = world.door.position
        door.position = point(Vec2(doorPosition.x + 0.5, doorPosition.y))

        player.sync(with: simulation.player, dt: dt)
        player.isHidden = !simulation.isRunning && simulation.status != .won
    }

    func syncGhost(_ ghost: Simulation?, dt: CGFloat) {
        guard let ghost else {
            self.ghost?.removeFromParent()
            self.ghost = nil
            return
        }
        if self.ghost == nil {
            let node = PlayerNode(tile: tile, playerSize: ghost.player.size, theme: theme, ghost: true)
            node.zPosition = 9
            addChild(node)
            self.ghost = node
        }
        self.ghost?.sync(with: ghost.player, dt: dt)
    }

    func doorCelebration() {
        door.run(.sequence([.scale(to: 1.15, duration: 0.08), .scale(to: 1, duration: 0.12)]))
    }
}
