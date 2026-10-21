import AppKit
import QuartzCore

/// "Broken matrix" mode: the first slap kills parts of the LCD panel — dead column drivers,
/// a rainbow band, dead rows — as a still image that stays until repaired. Further slaps do nothing.
final class MatrixEngine {
    private var windows: [GlitchWindow] = []
    private(set) var broken = false

    init() {
        rebuildWindows()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.rebuildWindows() }
    }

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map(GlitchWindow.init)
        broken = false
    }

    /// strength: 0…1. Damages the screen under the mouse, once.
    func hit(strength: Double) {
        guard !broken else { return }
        let mouse = NSEvent.mouseLocation
        guard let w = windows.first(where: { $0.frame.contains(mouse) }) ?? windows.first else { return }
        broken = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        w.host.addSublayer(damage(in: w.host.bounds, k: strength))
        CATransaction.commit()
        w.orderFrontRegardless()
    }

    func repair() {
        for w in windows { w.host.sublayers?.forEach { $0.removeFromSuperlayer() }; w.orderOut(nil) }
        broken = false
    }

    // MARK: Damage

    private static let neon: [NSColor] = [
        NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1), NSColor(srgbRed: 0, green: 1, blue: 1, alpha: 1),
        NSColor(srgbRed: 0, green: 1, blue: 0.2, alpha: 1), NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1),
        NSColor(srgbRed: 1, green: 0, blue: 0.2, alpha: 1), NSColor(srgbRed: 0.2, green: 0.3, blue: 1, alpha: 1),
        .white, .black,
    ]

    private func damage(in b: CGRect, k: Double) -> CALayer {
        let root = CALayer()
        root.frame = b
        let W = b.width, H = b.height
        let cx = CGFloat.random(in: W * 0.1...W * 0.9)

        // Dead column drivers: clusters of thin coloured vertical lines.
        for _ in 0..<Int.random(in: 1...(2 + Int(3 * k))) {
            let cluster = stripes(width: Int.random(in: 12...Int(40 + 160 * k)), smooth: false)
            let l = CALayer()
            l.contents = cluster
            l.contentsGravity = .resize
            l.magnificationFilter = .nearest
            let h = Double.random(in: 0...1) < 0.6 ? H : H * .random(in: 0.3...0.9)
            l.frame = CGRect(x: cx + .random(in: -W * 0.2...W * 0.2), y: Bool.random() ? H - h : 0,
                             width: CGFloat(cluster.width), height: h)
            root.addSublayer(l)
        }

        // Rainbow gradient band from a failing column driver.
        let rainbow = CALayer()
        rainbow.contents = stripes(width: 64, smooth: true)
        rainbow.contentsGravity = .resize
        rainbow.frame = CGRect(x: cx + .random(in: -200...200), y: 0, width: .random(in: 30...(60 + 160 * k)), height: H)
        rainbow.opacity = 0.85
        root.addSublayer(rainbow)

        // Dead rows: thin full-width lines.
        for _ in 0..<Int.random(in: 2...(3 + Int(6 * k))) {
            let l = CALayer()
            l.frame = CGRect(x: 0, y: .random(in: 0...H), width: W, height: .random(in: 1...3))
            l.backgroundColor = Self.neon.randomElement()!.cgColor
            root.addSublayer(l)
        }
        return root
    }

    /// A 1px-tall strip image of coloured columns; stretched vertically by the layer.
    private func stripes(width: Int, smooth: Bool) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if smooth {
            let start = CGFloat.random(in: 0...1)
            for x in 0..<width {
                let hue = (start + CGFloat(x) / CGFloat(width)).truncatingRemainder(dividingBy: 1)
                ctx.setFillColor(NSColor(calibratedHue: hue, saturation: 1, brightness: 1, alpha: 1).cgColor)
                ctx.fill(CGRect(x: x, y: 0, width: 1, height: 1))
            }
        } else {
            var x = 0
            while x < width {
                let w = Int.random(in: 1...3)
                // Gaps let the desktop show between dead columns.
                if Double.random(in: 0...1) < 0.7 {
                    ctx.setFillColor(Self.neon.randomElement()!.cgColor)
                    ctx.fill(CGRect(x: x, y: 0, width: w, height: 1))
                }
                x += w + Int.random(in: 0...3)
            }
        }
        return ctx.makeImage()!
    }
}
