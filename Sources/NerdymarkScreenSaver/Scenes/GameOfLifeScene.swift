import Cocoa

/// Conway's Game of Life. Toroidal wrap (cells on the edge "see" the
/// opposite edge as neighbors) so the simulation never runs into a wall.
/// When the population stagnates or oscillates indefinitely we re-seed.
final class GameOfLifeScene: DemoScene {
    static let identifier = "game_of_life"
    static let displayName = "Conway's Life"

    static let options: [SceneOption] = [
        .slider(key: "cellSize", label: "Cell Size", min: 4, max: 32, defaultValue: 10, format: "%.0f px"),
        .slider(key: "stepsPerSecond", label: "Speed", min: 2, max: 30, defaultValue: 12, format: "%.0f gen/s"),
        .slider(key: "density", label: "Initial Density", min: 0.1, max: 0.6, defaultValue: 0.28, format: "%.0f%%"),
        .choice(key: "color", label: "Color",
                choices: ["Cyan", "Amber", "Magenta", "Lime"],
                defaultValue: "Cyan"),
        .toggle(key: "fadeTrails", label: "Fade dying cells", defaultValue: true),
    ]

    private var size: CGSize = .zero
    private var cellSize: CGFloat
    private var stepsPerSecond: Double
    private var density: Double
    private let colorName: String
    private let fadeTrails: Bool

    private var cols: Int = 0
    private var rows: Int = 0
    private var grid: [UInt8] = []     // 1 alive, 0 dead
    private var fade: [UInt8] = []     // 0..255, decays each step (visual trail)
    private var stepAccum: TimeInterval = 0

    // Stagnation detection: hash recent generations; if we've seen the same
    // state within last N gens, reseed.
    private var recentHashes: [UInt64] = []
    private var generationsSinceReseed = 0

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.cellSize = CGFloat(settings.double("cellSize", default: 10))
        self.stepsPerSecond = settings.double("stepsPerSecond", default: 12)
        self.density = settings.double("density", default: 0.28)
        self.colorName = settings.string("color", default: "Cyan")
        self.fadeTrails = settings.bool("fadeTrails", default: true)
        rebuild()
    }

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        rebuild()
    }

    func tick(dt: TimeInterval) {
        stepAccum += dt
        let interval = 1.0 / max(1, stepsPerSecond)
        while stepAccum >= interval {
            stepAccum -= interval
            stepGeneration()
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }
        ctx.setFillColor(CGColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        let baseColor = colorComponents()
        let originX = (targetSize.width - CGFloat(cols) * cellSize) / 2
        let originY = (targetSize.height - CGFloat(rows) * cellSize) / 2

        for y in 0..<rows {
            for x in 0..<cols {
                let i = y * cols + x
                let alive = grid[i] == 1
                let f = fadeTrails ? fade[i] : (alive ? 255 : 0)
                if !alive && f == 0 { continue }
                let alpha = alive ? 1.0 : (Double(f) / 255.0) * 0.6
                let color = CGColor(red: baseColor.r, green: baseColor.g, blue: baseColor.b, alpha: CGFloat(alpha))
                ctx.setFillColor(color)
                let rect = CGRect(
                    x: originX + CGFloat(x) * cellSize,
                    y: originY + CGFloat(y) * cellSize,
                    width: cellSize, height: cellSize
                ).insetBy(dx: max(0.5, cellSize * 0.08), dy: max(0.5, cellSize * 0.08))
                ctx.fill(rect)
            }
        }
    }

    // MARK: - Generation

    private func stepGeneration() {
        var next = grid
        for y in 0..<rows {
            for x in 0..<cols {
                let n = liveNeighbors(x: x, y: y)
                let i = y * cols + x
                let alive = grid[i] == 1
                if alive {
                    next[i] = (n == 2 || n == 3) ? 1 : 0
                    if next[i] == 0 { fade[i] = 220 }   // just died
                } else {
                    next[i] = (n == 3) ? 1 : 0
                }
            }
        }
        // Decay trail.
        if fadeTrails {
            for i in 0..<fade.count {
                fade[i] = fade[i] > 12 ? fade[i] - 12 : 0
            }
        }
        grid = next
        generationsSinceReseed += 1

        // Reseed on stagnation: same state seen recently OR every 600 gens.
        let h = hashGrid()
        if recentHashes.contains(h) || generationsSinceReseed > 600 {
            seed()
            return
        }
        recentHashes.append(h)
        if recentHashes.count > 12 { recentHashes.removeFirst() }
    }

    private func liveNeighbors(x: Int, y: Int) -> Int {
        var count = 0
        for dy in -1...1 {
            for dx in -1...1 where !(dx == 0 && dy == 0) {
                let nx = (x + dx + cols) % cols
                let ny = (y + dy + rows) % rows
                count += Int(grid[ny * cols + nx])
            }
        }
        return count
    }

    private func hashGrid() -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for v in grid {
            h ^= UInt64(v)
            h &*= 0x100000001b3
        }
        return h
    }

    // MARK: - Build

    private func rebuild() {
        cols = max(8, Int(size.width / cellSize))
        rows = max(8, Int(size.height / cellSize))
        grid = [UInt8](repeating: 0, count: cols * rows)
        fade = [UInt8](repeating: 0, count: cols * rows)
        seed()
    }

    private func seed() {
        for i in grid.indices {
            grid[i] = Double.random(in: 0...1) < density ? 1 : 0
        }
        recentHashes.removeAll()
        generationsSinceReseed = 0
    }

    private func colorComponents() -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch colorName {
        case "Amber":   return (1.0, 0.65, 0.10)
        case "Magenta": return (0.95, 0.20, 0.85)
        case "Lime":    return (0.55, 1.0, 0.20)
        default:        return (0.20, 0.95, 1.0)
        }
    }
}
