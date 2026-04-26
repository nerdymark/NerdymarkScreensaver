import CoreGraphics

/// Shared palette + bitmap-render helper used by the plasma family scenes
/// (PlasmaScene's logic predates this and stays self-contained).
enum PlasmaPalette {
    static let allNames = ["Sunset", "Ocean", "Neon", "Mono", "Lava", "Cosmic", "Acid"]

    static func make(named name: String) -> [UInt32] {
        switch name {
        case "Ocean":
            return gradient([(0,(10,20,50)),(64,(20,90,180)),(128,(60,200,230)),(192,(150,240,250)),(255,(10,20,50))])
        case "Neon":
            return gradient([(0,(255,0,128)),(85,(0,255,200)),(170,(255,240,0)),(255,(255,0,128))])
        case "Mono":
            return gradient([(0,(0,0,0)),(128,(255,255,255)),(255,(0,0,0))])
        case "Lava":
            return gradient([(0,(20,0,0)),(80,(140,15,0)),(180,(255,90,15)),(230,(255,210,80)),(255,(255,255,200))])
        case "Cosmic":
            return gradient([(0,(5,0,30)),(80,(60,20,160)),(160,(180,80,220)),(220,(255,200,255)),(255,(10,0,30))])
        case "Acid":
            return gradient([(0,(0,30,0)),(100,(20,180,30)),(180,(180,255,30)),(255,(255,255,200))])
        default: // Sunset
            return gradient([(0,(10,0,30)),(64,(180,30,80)),(128,(255,130,50)),(192,(255,230,130)),(255,(10,0,30))])
        }
    }

    static func gradient(_ stops: [(Int, (UInt8, UInt8, UInt8))]) -> [UInt32] {
        var pal = [UInt32](repeating: 0, count: 256)
        let sorted = stops.sorted { $0.0 < $1.0 }
        for i in 0..<256 {
            var lower = sorted.first!
            var upper = sorted.last!
            for s in sorted {
                if s.0 <= i { lower = s }
                if s.0 >= i { upper = s; break }
            }
            let span = max(1, upper.0 - lower.0)
            let frac = Double(i - lower.0) / Double(span)
            let r = UInt32(Double(lower.1.0) + (Double(upper.1.0) - Double(lower.1.0)) * frac)
            let g = UInt32(Double(lower.1.1) + (Double(upper.1.1) - Double(lower.1.1)) * frac)
            let b = UInt32(Double(lower.1.2) + (Double(upper.1.2) - Double(lower.1.2)) * frac)
            pal[i] = (0xFF << 24) | (r << 16) | (g << 8) | b
        }
        return pal
    }
}

/// Reusable low-res ARGB bitmap that scales up to a target context. The
/// pixel buffer lifetime matches the helper's; callers fill `pixels`
/// directly and then call `present(in:size:)`.
final class PaletteBitmap {
    private(set) var width: Int = 0
    private(set) var height: Int = 0
    private(set) var pixels: UnsafeMutablePointer<UInt32>?
    private var capacity: Int = 0
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    init(width w: Int, height h: Int) {
        resize(width: w, height: h)
    }

    deinit {
        pixels?.deallocate()
    }

    func resize(width w: Int, height h: Int) {
        guard w > 0, h > 0 else { return }
        if w * h > capacity {
            pixels?.deallocate()
            pixels = UnsafeMutablePointer<UInt32>.allocate(capacity: w * h)
            capacity = w * h
        }
        width = w
        height = h
    }

    /// Draw the buffer scaled to fill `size` in the target context.
    func present(in ctx: CGContext, size: CGSize, smooth: Bool = false) {
        guard let buffer = pixels, width > 0, height > 0 else { return }
        let bytesPerRow = width * 4
        let bytesTotal = bytesPerRow * height
        guard let provider = CGDataProvider(
            dataInfo: nil, data: buffer, size: bytesTotal,
            releaseData: { _, _, _ in }
        ) else { return }
        guard let image = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil,
            shouldInterpolate: smooth, intent: .defaultIntent
        ) else { return }
        ctx.interpolationQuality = smooth ? .medium : .none
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
    }
}
