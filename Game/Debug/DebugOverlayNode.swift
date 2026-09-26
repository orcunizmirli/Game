#if DEBUG
import SpriteKit
import GameCore

/// Debug-only overlay: trap trigger zones, hitboxes, spike hazard boxes, the door goal,
/// moving blocks and the ghost. Toggle with the bug button or the ` key.
final class DebugOverlayNode: SKNode {
    private let zoneLayer = SKNode()
    private let hazardLayer = SKNode()
    private let blockLayer = SKNode()
    private let playerBox = SKShapeNode()
    private let doorBox = SKShapeNode()
    private let info = SKLabelNode(fontNamed: "Menlo-Bold")
    private var zoneNodes: [(trapIndex: Int, node: SKShapeNode)] = []
    private var hazardRevision = -1

    override init() {
        super.init()
        for layer in [zoneLayer, hazardLayer, blockLayer] { addChild(layer) }
        playerBox.strokeColor = .systemGreen
        playerBox.lineWidth = 2
        doorBox.strokeColor = .systemBlue
        doorBox.lineWidth = 2
        addChild(playerBox)
        addChild(doorBox)
        info.fontSize = 11
        info.fontColor = .black
        info.horizontalAlignmentMode = .left
        info.verticalAlignmentMode = .top
        addChild(info)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func rect(_ box: AABB, _ tile: CGFloat) -> CGRect {
        CGRect(x: box.minX * tile, y: box.minY * tile, width: box.width * tile, height: box.height * tile)
    }

    func rebuild(for session: GameSession, tile: CGFloat) {
        zoneLayer.removeAllChildren()
        zoneNodes.removeAll()
        hazardRevision = -1
        for (i, trap) in session.simulation.traps.enumerated() {
            guard let zone = trap.zone else { continue }
            let node = SKShapeNode(rect: rect(zone, tile))
            node.strokeColor = .systemRed
            node.fillColor = UIColor.systemRed.withAlphaComponent(0.18)
            node.lineWidth = 1.5
            let label = SKLabelNode(fontNamed: "Menlo")
            label.text = trap.id
            label.fontSize = max(8, tile * 0.28)
            label.fontColor = .systemRed
            label.position = CGPoint(x: zone.midX * tile, y: zone.maxY * tile + 2)
            label.verticalAlignmentMode = .bottom
            node.addChild(label)
            zoneLayer.addChild(node)
            zoneNodes.append((i, node))
        }
        info.position = CGPoint(x: 4, y: CGFloat(session.world.grid.height) * tile - 4)
    }

    func sync(with session: GameSession, tile: CGFloat) {
        let sim = session.simulation
        playerBox.path = CGPath(rect: rect(sim.player.bounds, tile), transform: nil)
        doorBox.path = CGPath(rect: rect(sim.world.door.goalBounds, tile), transform: nil)

        for (index, node) in zoneNodes {
            node.alpha = sim.traps[index].isArmed ? 1 : 0.25
        }

        if sim.world.grid.revision != hazardRevision {
            hazardRevision = sim.world.grid.revision
            hazardLayer.removeAllChildren()
            let grid = sim.world.grid
            for p in grid.points {
                guard let box = grid[p].hazardBounds(at: p) else { continue }
                let node = SKShapeNode(rect: rect(box, tile))
                node.strokeColor = .systemOrange
                node.lineWidth = 1
                hazardLayer.addChild(node)
            }
        }

        blockLayer.removeAllChildren()
        for block in sim.world.blocks {
            let node = SKShapeNode(rect: rect(block.bounds, tile))
            node.strokeColor = .systemPurple
            node.lineWidth = 2
            blockLayer.addChild(node)
        }

        let p = sim.player
        info.text = String(format: "t=%.2f  x=%.2f y=%.2f  vx=%.1f vy=%.1f  %@%@  gen %d",
                           sim.time, p.position.x, p.position.y, p.velocity.x, p.velocity.y,
                           p.isGrounded ? "grounded" : "air",
                           sim.world.controlsInverted ? "  INVERTED" : "",
                           session.generation)
    }
}
#endif
