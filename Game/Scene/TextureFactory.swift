import SpriteKit
import UIKit

/// Procedurally drawn textures. The whole game ships without image assets.
enum TextureFactory {
    private static func render(_ size: CGSize, _ draw: (CGContext) -> Void) -> SKTexture {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            draw(ctx.cgContext)
        }
        return SKTexture(image: image)
    }

    /// Two spikes pointing up, filling the bottom 60% of a tile.
    static func spikes(tile: CGFloat, color: UIColor) -> SKTexture {
        render(CGSize(width: tile, height: tile)) { ctx in
            ctx.setFillColor(color.cgColor)
            let count = 2
            let w = tile * 0.9 / CGFloat(count)
            let x0 = tile * 0.05
            let top = tile * 0.4 // UIKit y grows downward
            for i in 0..<count {
                let left = x0 + CGFloat(i) * w
                ctx.move(to: CGPoint(x: left, y: tile))
                ctx.addLine(to: CGPoint(x: left + w / 2, y: top))
                ctx.addLine(to: CGPoint(x: left + w, y: tile))
                ctx.closePath()
            }
            ctx.fillPath()
            ctx.fill(CGRect(x: x0, y: tile - tile * 0.06, width: tile * 0.9, height: tile * 0.06))
        }
    }

    /// Arched doorway: ink frame with a bright interior.
    static func door(tile: CGFloat, ink: UIColor, glow: UIColor) -> SKTexture {
        let size = CGSize(width: tile * 0.84, height: tile * 1.0)
        return render(size) { ctx in
            let outer = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size),
                                     byRoundingCorners: [.topLeft, .topRight],
                                     cornerRadii: CGSize(width: size.width / 2, height: size.width / 2))
            ctx.setFillColor(ink.cgColor)
            ctx.addPath(outer.cgPath)
            ctx.fillPath()
            let inset = tile * 0.12
            let innerRect = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset)
            let inner = UIBezierPath(roundedRect: innerRect,
                                     byRoundingCorners: [.topLeft, .topRight],
                                     cornerRadii: CGSize(width: innerRect.width / 2, height: innerRect.width / 2))
            ctx.setFillColor(glow.cgColor)
            ctx.addPath(inner.cgPath)
            ctx.fillPath()
            // Door knob.
            ctx.setFillColor(ink.cgColor)
            let knob = tile * 0.08
            ctx.fillEllipse(in: CGRect(x: size.width - inset - knob * 2.2, y: size.height * 0.58, width: knob, height: knob))
        }
    }

    static func roundedRect(size: CGSize, radius: CGFloat, color: UIColor) -> SKTexture {
        render(size) { ctx in
            ctx.setFillColor(color.cgColor)
            ctx.addPath(UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius).cgPath)
            ctx.fillPath()
        }
    }

    static func circle(diameter: CGFloat, color: UIColor) -> SKTexture {
        render(CGSize(width: diameter, height: diameter)) { ctx in
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        }
    }

    /// Round control button with an SF Symbol glyph.
    static func button(diameter: CGFloat, symbol: String, fill: UIColor, ring: UIColor, glyph: UIColor) -> SKTexture {
        render(CGSize(width: diameter, height: diameter)) { ctx in
            ctx.setFillColor(fill.cgColor)
            ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
            let lineWidth = max(2, diameter * 0.05)
            ctx.setStrokeColor(ring.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.strokeEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter).insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
            let config = UIImage.SymbolConfiguration(pointSize: diameter * 0.4, weight: .black)
            if let image = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(glyph, renderingMode: .alwaysOriginal) {
                let s = image.size
                image.draw(in: CGRect(x: (diameter - s.width) / 2, y: (diameter - s.height) / 2,
                                      width: s.width, height: s.height))
            }
        }
    }
}
