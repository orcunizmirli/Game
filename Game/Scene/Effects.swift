import SpriteKit
import GameCore

/// Short-lived visual effects. They live in a layer that survives level rebuilds, so a
/// death burst keeps flying while the level has already restarted.
enum Effects {
    /// A tile breaks off and tumbles down.
    static func debris(from node: SKNode, tile: CGFloat, into layer: SKNode, in world: SKNode) {
        guard let copy = node.copy() as? SKNode else { return }
        copy.removeAllActions()
        copy.position = layer.convert(node.position, from: world)
        copy.zPosition = 4
        layer.addChild(copy)
        let drift = CGFloat.random(in: -0.4...0.4) * tile
        copy.run(.sequence([
            .group([
                .moveBy(x: drift, y: -tile * 5, duration: 0.55),
                .rotate(byAngle: CGFloat.random(in: -1.2...1.2), duration: 0.55),
                .fadeOut(withDuration: 0.55),
            ]),
            .removeFromParent(),
        ]))
        copy.children.first?.run(.fadeOut(withDuration: 0.55))
    }

    /// The player bursts into little squares.
    static func deathBurst(at position: CGPoint, tile: CGFloat, theme: Theme, into layer: SKNode) {
        let colors = [theme.ink, theme.ink, theme.accent]
        for i in 0..<18 {
            let size = tile * CGFloat.random(in: 0.08...0.2)
            let piece = SKSpriteNode(color: colors[i % colors.count], size: CGSize(width: size, height: size))
            piece.position = position
            piece.zPosition = 20
            layer.addChild(piece)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = tile * CGFloat.random(in: 1.5...4)
            let dx = cos(angle) * speed, dy = sin(angle) * speed + tile * 1.2
            let duration = TimeInterval.random(in: 0.35...0.6)
            piece.run(.sequence([
                .group([
                    .moveBy(x: dx, y: dy, duration: duration * 0.5),
                    .rotate(byAngle: CGFloat.random(in: -6...6), duration: duration),
                    .sequence([.wait(forDuration: duration * 0.3), .fadeOut(withDuration: duration * 0.7)]),
                ]),
                .removeFromParent(),
            ]))
            piece.run(.moveBy(x: 0, y: -tile * 3, duration: duration), withKey: "gravity")
        }
        let ring = SKShapeNode(circleOfRadius: tile * 0.3)
        ring.strokeColor = theme.accent
        ring.lineWidth = max(2, tile * 0.08)
        ring.fillColor = .clear
        ring.position = position
        ring.zPosition = 19
        layer.addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 3, duration: 0.25), .fadeOut(withDuration: 0.25)]),
            .removeFromParent(),
        ]))
    }

    /// Door reached.
    static func celebrate(at position: CGPoint, tile: CGFloat, theme: Theme, into layer: SKNode) {
        for _ in 0..<16 {
            let piece = SKSpriteNode(color: [theme.accent, theme.doorGlow, theme.ink].randomElement()!,
                                     size: CGSize(width: tile * 0.12, height: tile * 0.2))
            piece.position = position
            piece.zPosition = 20
            layer.addChild(piece)
            let dx = CGFloat.random(in: -2...2) * tile
            let dy = CGFloat.random(in: 1...3.5) * tile
            piece.run(.sequence([
                .group([
                    .moveBy(x: dx, y: dy, duration: 0.5),
                    .rotate(byAngle: CGFloat.random(in: -8...8), duration: 0.5),
                    .sequence([.wait(forDuration: 0.25), .fadeOut(withDuration: 0.35)]),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    /// A few dust puffs on landing.
    static func dust(at position: CGPoint, tile: CGFloat, theme: Theme, into layer: SKNode) {
        for side in [-1.0, 1.0] {
            let puff = SKSpriteNode(color: theme.ink.withAlphaComponent(0.35),
                                    size: CGSize(width: tile * 0.14, height: tile * 0.14))
            puff.position = position
            puff.zPosition = 8
            layer.addChild(puff)
            puff.run(.sequence([
                .group([
                    .moveBy(x: CGFloat(side) * tile * 0.5, y: tile * 0.12, duration: 0.2),
                    .fadeOut(withDuration: 0.2),
                    .scale(to: 0.3, duration: 0.2),
                ]),
                .removeFromParent(),
            ]))
        }
    }
}
