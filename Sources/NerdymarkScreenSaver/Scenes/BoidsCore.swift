import Foundation
import CoreGraphics

/// Reynolds boids: alignment, cohesion, separation. Shared by fish, bug, and
/// fishtank scenes — only the rendering differs. The simulation is O(n²)
/// which is fine for a few hundred boids; if we ever need more we'd switch
/// to a spatial hash.
final class BoidSimulation {
    struct Boid {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
    }

    var boids: [Boid] = []
    var bounds: CGSize = .zero

    // Tunable weights per scene.
    var alignWeight: Double = 0.05
    var cohesionWeight: Double = 0.005
    var separationWeight: Double = 0.05
    var visionRadius: Double = 60
    var separationRadius: Double = 18
    var maxSpeed: Double = 90
    var minSpeed: Double = 30

    init(count: Int, bounds: CGSize) {
        self.bounds = bounds
        spawn(count: count)
    }

    func spawn(count: Int) {
        boids = (0..<count).map { _ in
            let angle = Double.random(in: 0..<(2.0 * Double.pi))
            return Boid(
                x: Double.random(in: 0...Double(bounds.width)),
                y: Double.random(in: 0...Double(bounds.height)),
                vx: cos(angle) * maxSpeed * 0.5,
                vy: sin(angle) * maxSpeed * 0.5
            )
        }
    }

    func tick(dt: Double) {
        let n = boids.count
        guard n > 0 else { return }
        let visionR2 = visionRadius * visionRadius
        let separationR2 = separationRadius * separationRadius
        var newBoids = boids
        for i in 0..<n {
            let me = boids[i]
            var avgVX = 0.0, avgVY = 0.0
            var avgX = 0.0, avgY = 0.0
            var sepX = 0.0, sepY = 0.0
            var neighbors = 0

            for j in 0..<n where j != i {
                let other = boids[j]
                let dx = other.x - me.x
                let dy = other.y - me.y
                let d2 = dx * dx + dy * dy
                if d2 > visionR2 { continue }
                avgVX += other.vx
                avgVY += other.vy
                avgX += other.x
                avgY += other.y
                neighbors += 1
                if d2 < separationR2 {
                    sepX -= dx
                    sepY -= dy
                }
            }

            var nvx = me.vx
            var nvy = me.vy
            if neighbors > 0 {
                let invN = 1.0 / Double(neighbors)
                nvx += (avgVX * invN - me.vx) * alignWeight
                nvy += (avgVY * invN - me.vy) * alignWeight
                nvx += (avgX * invN - me.x) * cohesionWeight
                nvy += (avgY * invN - me.y) * cohesionWeight
            }
            nvx += sepX * separationWeight
            nvy += sepY * separationWeight

            // Clamp speed.
            let speed = sqrt(nvx * nvx + nvy * nvy)
            if speed > maxSpeed {
                nvx = nvx / speed * maxSpeed
                nvy = nvy / speed * maxSpeed
            } else if speed < minSpeed && speed > 0 {
                nvx = nvx / speed * minSpeed
                nvy = nvy / speed * minSpeed
            }

            // Soft wall avoidance — turn boids back toward center near edges.
            let margin = 60.0
            let turnForce = 30.0 * dt
            if me.x < margin { nvx += turnForce }
            if me.x > Double(bounds.width) - margin { nvx -= turnForce }
            if me.y < margin { nvy += turnForce }
            if me.y > Double(bounds.height) - margin { nvy -= turnForce }

            newBoids[i].vx = nvx
            newBoids[i].vy = nvy
            newBoids[i].x = me.x + nvx * dt
            newBoids[i].y = me.y + nvy * dt

            // Hard wrap if anything escaped (e.g., on resize).
            if newBoids[i].x < -50 { newBoids[i].x = Double(bounds.width) + 50 }
            if newBoids[i].x > Double(bounds.width) + 50 { newBoids[i].x = -50 }
            if newBoids[i].y < -50 { newBoids[i].y = Double(bounds.height) + 50 }
            if newBoids[i].y > Double(bounds.height) + 50 { newBoids[i].y = -50 }
        }
        boids = newBoids
    }
}
