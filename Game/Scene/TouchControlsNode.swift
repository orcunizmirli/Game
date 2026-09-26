import SpriteKit
import GameCore

/// Draws the on-screen buttons. The actual hit testing lives in GameCore's `TouchLayout`,
/// whose zones are far larger than these visuals.
final class TouchControlsNode: SKNode {
    private var buttons: [TouchLayout.Zone: SKSpriteNode] = [:]
    private var builtFor: (TouchLayout, Theme)?

    func layout(_ layout: TouchLayout, origin: CGPoint, theme: Theme) {
        if let built = builtFor, built.0 == layout, built.1 == theme {
            return
        }
        builtFor = (layout, theme)
        removeAllChildren()
        buttons.removeAll()
        position = origin

        let d = CGFloat(layout.buttonRadius * 2)
        let fill = theme.ink.withAlphaComponent(0.3)
        let glyph = theme.background.withAlphaComponent(0.95)
        let specs: [(TouchLayout.Zone, String, Vec2, CGFloat)] = [
            (.left, "arrowtriangle.left.fill", layout.leftButtonCenter, d),
            (.right, "arrowtriangle.right.fill", layout.rightButtonCenter, d),
            (.jump, "arrowtriangle.up.fill", layout.jumpButtonCenter, d * 1.2),
        ]
        for (zone, symbol, center, diameter) in specs {
            let node = SKSpriteNode(texture: TextureFactory.button(diameter: diameter, symbol: symbol, fill: fill, glyph: glyph))
            node.position = CGPoint(x: center.x, y: center.y)
            node.alpha = 0.75
            addChild(node)
            buttons[zone] = node
        }
    }

    func highlight(_ active: Set<TouchLayout.Zone>) {
        for (zone, node) in buttons {
            let on = active.contains(zone)
            node.alpha = on ? 1 : 0.75
            node.setScale(on ? 0.92 : 1)
        }
    }
}
