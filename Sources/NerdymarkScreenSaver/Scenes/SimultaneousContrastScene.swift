import Cocoa

/// Simultaneous contrast illusion: two identical neutral gray patches placed
/// on backgrounds of opposing color appear to take on the *opposite* tint
/// of their surroundings. We rotate through several pair backgrounds and
/// label the patches "SAME GRAY →" so it's clear what's happening.
final class SimultaneousContrastScene: DemoScene {
    static let identifier = "simultaneous_contrast"
    static let displayName = "Simultaneous Contrast"

    static let options: [SceneOption] = [
        .slider(key: "patchSize", label: "Patch Size", min: 80, max: 280, defaultValue: 160, format: "%.0f px"),
        .slider(key: "secondsPerPair", label: "Pair Duration", min: 3, max: 15, defaultValue: 7, format: "%.0f s"),
        .toggle(key: "showLabel", label: "Show explanatory label", defaultValue: true),
        .toggle(key: "blendMidline", label: "Hide midline divider", defaultValue: false),
    ]

    private struct Pair {
        let leftBg: CGColor
        let rightBg: CGColor
        let label: String
    }

    private var size: CGSize = .zero
    private let patchSize: CGFloat
    private let secondsPerPair: Double
    private let showLabel: Bool
    private let hideMidline: Bool

    private let pairs: [Pair] = [
        Pair(leftBg: CGColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1),
              rightBg: CGColor(red: 0.0, green: 0.4, blue: 0.95, alpha: 1),
              label: "Both gray patches are #888888"),
        Pair(leftBg: CGColor(red: 0.95, green: 0.0, blue: 0.4, alpha: 1),
              rightBg: CGColor(red: 0.05, green: 0.85, blue: 0.40, alpha: 1),
              label: "Same gray. Same RGB. Trust the spec, not your eyes."),
        Pair(leftBg: CGColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1),
              rightBg: CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1),
              label: "Identical mid-gray patches on white vs. black"),
        Pair(leftBg: CGColor(red: 0.5, green: 0.0, blue: 0.6, alpha: 1),
              rightBg: CGColor(red: 0.95, green: 0.85, blue: 0.0, alpha: 1),
              label: "Yes, both gray. You're not broken."),
    ]

    private let neutralGray = CGColor(red: 0.53, green: 0.53, blue: 0.53, alpha: 1)
    private var elapsed: Double = 0
    private var currentPairIdx = 0
    private var pairSwitchAt: Double = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.patchSize = CGFloat(settings.double("patchSize", default: 160))
        self.secondsPerPair = settings.double("secondsPerPair", default: 7)
        self.showLabel = settings.bool("showLabel", default: true)
        self.hideMidline = settings.bool("blendMidline", default: false)
    }

    func resize(_ newSize: CGSize) { size = newSize }

    func tick(dt: TimeInterval) {
        elapsed += dt
        if elapsed - pairSwitchAt >= secondsPerPair {
            pairSwitchAt = elapsed
            currentPairIdx = (currentPairIdx + 1) % pairs.count
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        size = targetSize
        let pair = pairs[currentPairIdx]

        // Smooth crossfade between pairs near the boundary.
        let timeIntoPair = elapsed - pairSwitchAt
        let fadeDur: Double = 0.6
        let fadeAlpha: Double
        if timeIntoPair < fadeDur {
            fadeAlpha = timeIntoPair / fadeDur
        } else if timeIntoPair > secondsPerPair - fadeDur {
            fadeAlpha = (secondsPerPair - timeIntoPair) / fadeDur
        } else {
            fadeAlpha = 1.0
        }

        // Two background halves.
        let mid = targetSize.width / 2
        ctx.setFillColor(pair.leftBg)
        ctx.fill(CGRect(x: 0, y: 0, width: mid, height: targetSize.height))
        ctx.setFillColor(pair.rightBg)
        ctx.fill(CGRect(x: mid, y: 0, width: mid, height: targetSize.height))

        // Optional midline divider for clean split.
        if !hideMidline {
            ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.4))
            ctx.setLineWidth(1.5)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: mid, y: 0))
            ctx.addLine(to: CGPoint(x: mid, y: targetSize.height))
            ctx.strokePath()
        }

        // Two identical gray patches.
        let patchY = (targetSize.height - patchSize) / 2
        let leftPatchX = (mid - patchSize) / 2
        let rightPatchX = mid + (mid - patchSize) / 2

        ctx.setFillColor(neutralGray)
        ctx.fill(CGRect(x: leftPatchX, y: patchY, width: patchSize, height: patchSize))
        ctx.fill(CGRect(x: rightPatchX, y: patchY, width: patchSize, height: patchSize))

        // Fade overlay during pair transitions.
        if fadeAlpha < 1.0 {
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: CGFloat(1.0 - fadeAlpha)))
            ctx.fill(CGRect(origin: .zero, size: targetSize))
        }

        if showLabel {
            drawLabel(pair.label, in: ctx, size: targetSize)
        }
    }

    private func drawLabel(_ text: String, in ctx: CGContext, size targetSize: CGSize) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let textSize = str.size()
        let pad: CGFloat = 12
        let bgRect = CGRect(
            x: (targetSize.width - textSize.width - pad * 2) / 2,
            y: 22,
            width: textSize.width + pad * 2,
            height: textSize.height + pad
        )
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.65))
        let path = CGPath(roundedRect: bgRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        str.draw(at: CGPoint(x: bgRect.minX + pad, y: bgRect.minY + pad / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}
