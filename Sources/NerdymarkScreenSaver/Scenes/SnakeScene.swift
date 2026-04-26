import Cocoa
import CoreGraphics

/// Auto-playing Snake. The snake uses A* to path toward food; if no path
/// exists (boxed in by its own body) it falls back to "follow the longest
/// safe direction" so it doesn't immediately die when the board is crowded.
/// Resets when it dies. Cell grid auto-fits the screen.
final class SnakeScene: DemoScene {
    static let identifier = "snake"
    static let displayName = "Snake (AI)"

    static let options: [SceneOption] = [
        .slider(key: "cellSize", label: "Cell Size", min: 10, max: 60, defaultValue: 24, format: "%.0f px"),
        .slider(key: "stepsPerSecond", label: "Speed", min: 5, max: 60, defaultValue: 24, format: "%.0f cells/s"),
        .choice(key: "snakeColor", label: "Snake Color",
                choices: ["Cyan", "Green", "Magenta", "Amber", "Rainbow"],
                defaultValue: "Cyan"),
        .toggle(key: "trail", label: "Glowing trail", defaultValue: true),
    ]

    // MARK: - State

    private var size: CGSize = .zero
    private var cellSize: CGFloat
    private var stepsPerSecond: Double
    private let snakeColorName: String
    private let drawTrail: Bool

    private var cols: Int = 0
    private var rows: Int = 0

    private struct Cell: Hashable {
        let x: Int
        let y: Int
    }

    private var snake: [Cell] = []
    private var direction: Cell = Cell(x: 1, y: 0)
    private var food: Cell = Cell(x: 0, y: 0)
    private var score: Int = 0
    private var stepAccumulator: TimeInterval = 0

    // MARK: - Init

    init(size: CGSize, settings: SceneSettings) {
        self.size = size
        self.cellSize = CGFloat(settings.double("cellSize", default: 24))
        self.stepsPerSecond = settings.double("stepsPerSecond", default: 24)
        self.snakeColorName = settings.string("snakeColor", default: "Cyan")
        self.drawTrail = settings.bool("trail", default: true)
        rebuildBoard(for: size)
    }

    // MARK: - DemoScene

    func resize(_ newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        rebuildBoard(for: newSize)
    }

    func tick(dt: TimeInterval) {
        stepAccumulator += dt
        let stepInterval = 1.0 / max(1, stepsPerSecond)
        while stepAccumulator >= stepInterval {
            stepAccumulator -= stepInterval
            step()
        }
    }

    func draw(in ctx: CGContext, size targetSize: CGSize) {
        if Int(targetSize.width) != Int(size.width) || Int(targetSize.height) != Int(size.height) {
            resize(targetSize)
        }

        // Background — slightly lighter than pure black so dark snakes are still visible.
        ctx.setFillColor(CGColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: targetSize))

        // Center the grid in the view (board may be smaller than the view).
        let boardWidth = CGFloat(cols) * cellSize
        let boardHeight = CGFloat(rows) * cellSize
        let originX = (targetSize.width - boardWidth) / 2
        let originY = (targetSize.height - boardHeight) / 2

        // Faint grid dots for atmosphere.
        ctx.setFillColor(CGColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1))
        let dot: CGFloat = 1.5
        for y in 0..<rows {
            for x in 0..<cols {
                let cx = originX + CGFloat(x) * cellSize + cellSize/2 - dot/2
                let cy = originY + CGFloat(y) * cellSize + cellSize/2 - dot/2
                ctx.fill(CGRect(x: cx, y: cy, width: dot, height: dot))
            }
        }

        // Food — pulsing red dot.
        let foodRect = cellRect(food, originX: originX, originY: originY).insetBy(dx: cellSize * 0.18, dy: cellSize * 0.18)
        ctx.setFillColor(CGColor(red: 1, green: 0.25, blue: 0.35, alpha: 1))
        ctx.fillEllipse(in: foodRect)

        // Snake body — tail to head, colored by progress for "trail" feel.
        let total = snake.count
        for (i, segment) in snake.enumerated() {
            let progress = total > 1 ? Double(i) / Double(total - 1) : 1.0
            let color = colorForSnakeSegment(progress: progress, headIndex: total - 1, segmentIndex: i)
            let rect = cellRect(segment, originX: originX, originY: originY)
                .insetBy(dx: cellSize * 0.08, dy: cellSize * 0.08)
            ctx.setFillColor(color)
            let path = CGPath(roundedRect: rect, cornerWidth: cellSize * 0.2, cornerHeight: cellSize * 0.2, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()

            // Optional glow halo around head for "trail" mode.
            if drawTrail && i == total - 1 {
                let halo = rect.insetBy(dx: -cellSize * 0.5, dy: -cellSize * 0.5)
                let haloColor = color.copy(alpha: 0.18) ?? color
                ctx.setFillColor(haloColor)
                ctx.fillEllipse(in: halo)
            }
        }
    }

    // MARK: - Drawing helpers

    private func cellRect(_ c: Cell, originX: CGFloat, originY: CGFloat) -> CGRect {
        return CGRect(
            x: originX + CGFloat(c.x) * cellSize,
            y: originY + CGFloat(c.y) * cellSize,
            width: cellSize,
            height: cellSize
        )
    }

    private func colorForSnakeSegment(progress: Double, headIndex: Int, segmentIndex: Int) -> CGColor {
        let isHead = segmentIndex == headIndex
        switch snakeColorName {
        case "Green":
            return CGColor(red: 0.2 + 0.4 * progress, green: 0.95, blue: 0.35, alpha: isHead ? 1 : 0.9 * progress + 0.4)
        case "Magenta":
            return CGColor(red: 0.95, green: 0.15, blue: 0.6 + 0.3 * progress, alpha: isHead ? 1 : 0.9 * progress + 0.4)
        case "Amber":
            return CGColor(red: 1, green: 0.55 + 0.3 * progress, blue: 0.1, alpha: isHead ? 1 : 0.9 * progress + 0.4)
        case "Rainbow":
            // Distribute hues along the body.
            let hue = CGFloat(progress)
            return NSColor(hue: hue, saturation: 0.85, brightness: 1.0, alpha: isHead ? 1 : 0.9 * progress + 0.4).cgColor
        default: // Cyan
            return CGColor(red: 0.15, green: 0.85, blue: 0.95 - 0.2 * progress, alpha: isHead ? 1 : 0.9 * progress + 0.4)
        }
    }

    // MARK: - Game logic

    private func rebuildBoard(for newSize: CGSize) {
        cols = max(8, Int(newSize.width / cellSize))
        rows = max(8, Int(newSize.height / cellSize))
        reset()
    }

    private func reset() {
        let cx = cols / 2
        let cy = rows / 2
        snake = [
            Cell(x: cx - 2, y: cy),
            Cell(x: cx - 1, y: cy),
            Cell(x: cx,     y: cy),
        ]
        direction = Cell(x: 1, y: 0)
        score = 0
        placeFood()
    }

    private func placeFood() {
        // Random empty cell. If board is full (you won, somehow), reset.
        let snakeSet = Set(snake)
        let empty = (0..<rows).flatMap { y in (0..<cols).map { Cell(x: $0, y: y) } }
            .filter { !snakeSet.contains($0) }
        guard let pick = empty.randomElement() else {
            reset()
            return
        }
        food = pick
    }

    private func step() {
        // Plan next direction with A*.
        let next = chooseNextStep()
        let head = snake.last!
        let newHead = Cell(x: head.x + next.x, y: head.y + next.y)

        // Death conditions: wall or self-collision (excluding tail since it'll move).
        if newHead.x < 0 || newHead.x >= cols || newHead.y < 0 || newHead.y >= rows {
            reset(); return
        }
        let bodyToCheck = snake.dropFirst()  // tail moves out of newHead's way unless we just ate
        let willEat = newHead == food
        let collisionSet: Set<Cell> = willEat ? Set(snake) : Set(bodyToCheck)
        if collisionSet.contains(newHead) {
            reset(); return
        }

        snake.append(newHead)
        direction = next
        if willEat {
            score += 1
            placeFood()
        } else {
            snake.removeFirst()
        }
    }

    /// Try to A* to food. If unreachable or unsafe, take the longest-survival
    /// direction (greedy: pick the move that keeps the most empty squares
    /// reachable from the new head).
    private func chooseNextStep() -> Cell {
        let head = snake.last!
        let body = Set(snake.dropFirst())  // tail will move away

        if let path = aStar(from: head, to: food, blocked: body), path.count > 1 {
            let next = path[1]
            return Cell(x: next.x - head.x, y: next.y - head.y)
        }

        // Fallback: pick the direction whose new cell has the most reachable squares.
        let candidates: [Cell] = [Cell(x: 1, y: 0), Cell(x: -1, y: 0), Cell(x: 0, y: 1), Cell(x: 0, y: -1)]
            .filter { d in
                // Don't reverse into self.
                return !(d.x == -direction.x && d.y == -direction.y)
            }

        var best = direction
        var bestScore = -1
        for d in candidates {
            let cand = Cell(x: head.x + d.x, y: head.y + d.y)
            if cand.x < 0 || cand.x >= cols || cand.y < 0 || cand.y >= rows { continue }
            if body.contains(cand) { continue }
            let reach = floodFill(from: cand, blocked: Set(snake))
            if reach > bestScore {
                bestScore = reach
                best = d
            }
        }
        return best
    }

    // MARK: - Pathfinding

    private func neighbors(of c: Cell) -> [Cell] {
        return [
            Cell(x: c.x + 1, y: c.y),
            Cell(x: c.x - 1, y: c.y),
            Cell(x: c.x, y: c.y + 1),
            Cell(x: c.x, y: c.y - 1),
        ].filter { $0.x >= 0 && $0.x < cols && $0.y >= 0 && $0.y < rows }
    }

    private func aStar(from start: Cell, to goal: Cell, blocked: Set<Cell>) -> [Cell]? {
        struct Node { let cell: Cell; let f: Int }
        var gScore: [Cell: Int] = [start: 0]
        var cameFrom: [Cell: Cell] = [:]
        var open: [Node] = [Node(cell: start, f: heuristic(start, goal))]

        while !open.isEmpty {
            // Pop min-f. Linear scan is fine for typical board sizes (<5000 cells).
            var minIdx = 0
            for i in 1..<open.count where open[i].f < open[minIdx].f { minIdx = i }
            let current = open.remove(at: minIdx).cell
            if current == goal {
                var path = [current]
                var c = current
                while let prev = cameFrom[c] {
                    path.append(prev)
                    c = prev
                }
                return path.reversed()
            }
            for n in neighbors(of: current) where !blocked.contains(n) {
                let tentative = (gScore[current] ?? Int.max) + 1
                if tentative < (gScore[n] ?? Int.max) {
                    gScore[n] = tentative
                    cameFrom[n] = current
                    let f = tentative + heuristic(n, goal)
                    if let idx = open.firstIndex(where: { $0.cell == n }) {
                        open[idx] = Node(cell: n, f: f)
                    } else {
                        open.append(Node(cell: n, f: f))
                    }
                }
            }
        }
        return nil
    }

    private func heuristic(_ a: Cell, _ b: Cell) -> Int {
        return abs(a.x - b.x) + abs(a.y - b.y)
    }

    private func floodFill(from start: Cell, blocked: Set<Cell>) -> Int {
        if blocked.contains(start) { return 0 }
        var visited: Set<Cell> = [start]
        var stack: [Cell] = [start]
        while let c = stack.popLast() {
            for n in neighbors(of: c) where !blocked.contains(n) && !visited.contains(n) {
                visited.insert(n)
                stack.append(n)
            }
        }
        return visited.count
    }
}
