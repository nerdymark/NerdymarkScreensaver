import Cocoa

/// Pong: two AI paddles play forever. Each adds slight imperfection so the
/// rallies vary; ball speed gradually increases per rally and resets on
/// score. Score wraps after 99-99 to keep the screen tidy.
final class PongAIScene: DemoScene {
    static let identifier = "pong_ai"
    static let displayName = "Pong AI"

    static let options: [SceneOption] = [
        .slider(key: "ballSpeed", label: "Ball Speed", min: 200, max: 1200, defaultValue: 500, format: "%.0f px/s"),
        .slider(key: "paddleAccuracy", label: "AI Accuracy", min: 0.5, max: 1.0, defaultValue: 0.85, format: "%.2f"),
        .toggle(key: "showScore", label: "Show score", defaultValue: true),
    ]

    private var size: CGSize = .zero
    private let baseBallSpeed: Double
    private let accuracy: Double
    private let showScore: Bool

    private var ball: CGPoint = .zero
    private var ballVel: CGPoint = .init(x: 1, y: 1)
    private var ballSpeed: Double = 500
    private var paddleL: CGFloat = 0
    private var paddleR: CGFloat = 0
    private var scoreL: Int = 0
    private var scoreR: Int = 0
    private var aimErrorL: Double = 0
    private var aimErrorR: Double = 0
    private var nextAimRefresh: Double = 0
    private var elapsed: Double = 0
    private let paddleW: CGFloat = 12
    private let paddleH: CGFloat = 100
    private let ballSize: CGFloat = 12

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.baseBallSpeed = settings.double("ballSpeed", default: 500)
        self.accuracy = settings.double("paddleAccuracy", default: 0.85)
        self.showScore = settings.bool("showScore", default: true)
        self.ballSpeed = baseBallSpeed
        resetRound(direction: 1)
        paddleL = size.height / 2
        paddleR = size.height / 2
    }

    func resize(_ newSize: CGSize) {
        // Only reset when size actually changes — this is called every draw
        // by the screensaver host, so an unconditional reset froze the ball.
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        ball = CGPoint(x: newSize.width / 2, y: newSize.height / 2)
        paddleL = newSize.height / 2
        paddleR = newSize.height / 2
    }

    func tick(dt: TimeInterval) {
        elapsed += dt
        // AI: each paddle tracks the ball's y with a random aim error that
        // refreshes every ~0.4s (independent of ball position).
        let imperfection = (1 - accuracy) * 100
        if elapsed >= nextAimRefresh {
            aimErrorL = Double.random(in: -imperfection...imperfection)
            aimErrorR = Double.random(in: -imperfection...imperfection)
            nextAimRefresh = elapsed + 0.4
        }
        let paddleSpeed: CGFloat = CGFloat(ballSpeed * 0.85 * dt)
        // Left paddle reacts only when ball coming toward it.
        if ballVel.x < 0 {
            let target = ball.y + CGFloat(aimErrorL)
            if paddleL < target { paddleL += min(paddleSpeed, target - paddleL) }
            else if paddleL > target { paddleL -= min(paddleSpeed, paddleL - target) }
        }
        if ballVel.x > 0 {
            let target = ball.y + CGFloat(aimErrorR)
            if paddleR < target { paddleR += min(paddleSpeed, target - paddleR) }
            else if paddleR > target { paddleR -= min(paddleSpeed, paddleR - target) }
        }
        paddleL = max(paddleH / 2, min(size.height - paddleH / 2, paddleL))
        paddleR = max(paddleH / 2, min(size.height - paddleH / 2, paddleR))

        // Ball motion.
        ball.x += ballVel.x * CGFloat(ballSpeed * dt)
        ball.y += ballVel.y * CGFloat(ballSpeed * dt)
        // Walls.
        if ball.y < ballSize / 2 { ball.y = ballSize / 2; ballVel.y = abs(ballVel.y) }
        else if ball.y > size.height - ballSize / 2 { ball.y = size.height - ballSize / 2; ballVel.y = -abs(ballVel.y) }
        // Paddles.
        let padOffset: CGFloat = 30
        if ball.x - ballSize / 2 < padOffset + paddleW {
            if abs(ball.y - paddleL) < paddleH / 2 + ballSize / 2 {
                ballVel.x = abs(ballVel.x)
                ballVel.y += Double((ball.y - paddleL) / (paddleH / 2)) * 0.3
                normalizeBallVel()
                ballSpeed = min(1500, ballSpeed + 25)
            } else if ball.x < 0 {
                scoreR = (scoreR + 1) % 100
                resetRound(direction: -1)
            }
        }
        if ball.x + ballSize / 2 > size.width - padOffset - paddleW {
            if abs(ball.y - paddleR) < paddleH / 2 + ballSize / 2 {
                ballVel.x = -abs(ballVel.x)
                ballVel.y += Double((ball.y - paddleR) / (paddleH / 2)) * 0.3
                normalizeBallVel()
                ballSpeed = min(1500, ballSpeed + 25)
            } else if ball.x > size.width {
                scoreL = (scoreL + 1) % 100
                resetRound(direction: 1)
            }
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        // Center dashed line.
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
        let dashCount = Int(targetSize.height / 28)
        for i in 0..<dashCount {
            let y = CGFloat(i) * 28 + 6
            ctx.fill(CGRect(x: targetSize.width / 2 - 2, y: y, width: 4, height: 14))
        }

        // Paddles.
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 30, y: paddleL - paddleH / 2, width: paddleW, height: paddleH))
        ctx.fill(CGRect(x: targetSize.width - 30 - paddleW, y: paddleR - paddleH / 2, width: paddleW, height: paddleH))

        // Ball.
        ctx.fill(CGRect(x: ball.x - ballSize / 2, y: ball.y - ballSize / 2, width: ballSize, height: ballSize))

        // Score.
        if showScore {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 64, weight: .bold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            ]
            let s1 = NSAttributedString(string: String(format: "%02d", scoreL), attributes: attrs)
            let s2 = NSAttributedString(string: String(format: "%02d", scoreR), attributes: attrs)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            s1.draw(at: CGPoint(x: targetSize.width * 0.35 - s1.size().width / 2, y: targetSize.height - 100))
            s2.draw(at: CGPoint(x: targetSize.width * 0.65 - s2.size().width / 2, y: targetSize.height - 100))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // MARK: - Helpers

    private func resetRound(direction: Int) {
        ball = CGPoint(x: size.width / 2, y: size.height / 2)
        let angle = Double.random(in: -.pi / 4...(.pi / 4))
        ballVel = CGPoint(x: CGFloat(direction) * cos(angle), y: sin(angle))
        normalizeBallVel()
        ballSpeed = baseBallSpeed
    }

    private func normalizeBallVel() {
        let len = sqrt(ballVel.x * ballVel.x + ballVel.y * ballVel.y)
        if len > 0 {
            ballVel.x /= len
            ballVel.y /= len
        }
    }
}
