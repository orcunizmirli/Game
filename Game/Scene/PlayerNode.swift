import SpriteKit
import GameCore

/// The little hero: a dark rounded block with googly eyes. Pure presentation; its position
/// is copied from `PlayerState` every frame.
final class PlayerNode: SKNode {
    private let body: SKSpriteNode
    private let eyes = SKNode()
    private let leftPupil: SKSpriteNode
    private let rightPupil: SKSpriteNode
    private let tile: CGFloat
    private let size: CGSize
    private var squash: CGFloat = 0
    private var runPhase: CGFloat = 0

    init(tile: CGFloat, playerSize: Vec2, theme: Theme, ghost: Bool = false) {
        self.tile = tile
        self.size = CGSize(width: tile * playerSize.x, height: tile * playerSize.y)
        body = SKSpriteNode(texture: TextureFactory.roundedRect(size: size, radius: size.width * 0.28, color: theme.ink))
        body.anchorPoint = CGPoint(x: 0.5, y: 0)
        let eyeD = size.width * 0.34
        let pupilD = eyeD * 0.5
        let white = TextureFactory.circle(diameter: eyeD, color: .white)
        let pupilTexture = TextureFactory.circle(diameter: pupilD, color: theme.ink)
        leftPupil = SKSpriteNode(texture: pupilTexture)
        rightPupil = SKSpriteNode(texture: pupilTexture)
        super.init()

        addChild(body)
        body.zPosition = 0
        for (i, pupil) in [leftPupil, rightPupil].enumerated() {
            let eye = SKSpriteNode(texture: white)
            eye.position = CGPoint(x: (i == 0 ? -1 : 1) * eyeD * 0.62, y: 0)
            eye.zPosition = 1
            pupil.position = eye.position
            pupil.zPosition = 2
            eyes.addChild(eye)
            eyes.addChild(pupil)
        }
        eyes.position = CGPoint(x: 0, y: size.height * 0.62)
        body.addChild(eyes)
        eyes.zPosition = 1

        if ghost {
            alpha = 0.35
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    func sync(with player: PlayerState, dt: CGFloat) {
        position = CGPoint(x: player.position.x * tile, y: player.position.y * tile)

        // Eyes look where we're going and up/down with vertical speed.
        let look = CGFloat(player.facing) * size.width * 0.07
        let lookY = CGFloat(max(-1, min(1, player.velocity.y / 20))) * size.height * 0.05
        eyes.position.x = look
        for pupil in [leftPupil, rightPupil] {
            pupil.position.y = lookY
        }
        leftPupil.position.x = -size.width * 0.34 * 0.62 + look * 0.5
        rightPupil.position.x = size.width * 0.34 * 0.62 + look * 0.5

        // Squash & stretch.
        squash *= pow(0.001, dt) // decays in ~0.15 s
        let airStretch = player.isGrounded ? 0 : CGFloat(max(-0.12, min(0.12, player.velocity.y / 160)))
        let s = squash + airStretch
        body.xScale = 1 - s * 0.6
        body.yScale = 1 + s

        // Tiny bob while running.
        if player.isGrounded && abs(player.velocity.x) > 0.5 {
            runPhase += dt * 18
            body.position.y = abs(sin(runPhase)) * size.height * 0.06
        } else {
            body.position.y = 0
        }
    }

    func landed() { squash = -0.22 }
    func jumped() { squash = 0.25 }
}
