import AppKit
import CoreImage
import QuartzCore
import ScreenCaptureKit

// MARK: - Glitch overlay (one per screen)

final class GlitchWindow: NSWindow {
    let host = CALayer()
    let displayID: CGDirectDisplayID

    init(screen: NSScreen) {
        displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let v = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        v.wantsLayer = true
        v.layer?.addSublayer(host)
        host.frame = v.bounds
        contentView = v
    }
}

final class GlitchEngine {
    private var windows: [GlitchWindow] = []
    private var timer: Timer?
    private var endTime = Date()
    private var intensity = 0.5
    private var shots: [CGDirectDisplayID: (full: CGImage, red: CGImage, cyan: CGImage)] = [:]
    private let ci = CIContext()
    private var busy = false

    init() {
        rebuildWindows()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.rebuildWindows() }
    }

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map(GlitchWindow.init)
    }

    /// strength: 0…1
    func trigger(strength: Double) {
        guard !busy else { intensity = max(intensity, strength); endTime = Date() + 0.3 + 0.9 * intensity; return }
        busy = true
        intensity = strength
        capture { [weak self] in self?.run() }
    }

    // Grab the current screen contents so the glitch tears the real desktop apart.
    // Falls back to a synthetic glitch when Screen Recording permission isn't granted.
    private func capture(_ done: @escaping () -> Void) {
        shots.removeAll()
        guard CGPreflightScreenCaptureAccess() else { return done() }
        Task { @MainActor in
            if let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) {
                for d in content.displays {
                    let cfg = SCStreamConfiguration()
                    let scale = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == d.displayID }?.backingScaleFactor ?? 2
                    // Half resolution is plenty for a glitch and keeps it snappy.
                    cfg.width = Int(Double(d.width) * scale / 2)
                    cfg.height = Int(Double(d.height) * scale / 2)
                    cfg.showsCursor = false
                    let filter = SCContentFilter(display: d, excludingWindows: [])
                    if let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) {
                        shots[d.displayID] = (img, channel(img, r: 1, g: 0, b: 0), channel(img, r: 0, g: 1, b: 1))
                    }
                }
            }
            done()
        }
    }

    private func channel(_ img: CGImage, r: CGFloat, g: CGFloat, b: CGFloat) -> CGImage {
        let f = CIFilter(name: "CIColorMatrix")!
        f.setValue(CIImage(cgImage: img), forKey: kCIInputImageKey)
        f.setValue(CIVector(x: r, y: 0, z: 0, w: 0), forKey: "inputRVector")
        f.setValue(CIVector(x: 0, y: g, z: 0, w: 0), forKey: "inputGVector")
        f.setValue(CIVector(x: 0, y: 0, z: b, w: 0), forKey: "inputBVector")
        return ci.createCGImage(f.outputImage!, from: CIImage(cgImage: img).extent) ?? img
    }

    private func run() {
        endTime = Date() + 0.3 + 0.9 * intensity
        windows.forEach { $0.orderFrontRegardless() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.frame() }
        frame()
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        for w in windows { w.host.sublayers?.forEach { $0.removeFromSuperlayer() }; w.orderOut(nil) }
        shots.removeAll()
        busy = false
    }

    private func frame() {
        let remaining = endTime.timeIntervalSinceNow
        guard remaining > 0 else { return finish() }
        // Fade the chaos out over the last stretch, with occasional "clean" frames for a stutter feel.
        let k = intensity * min(1, remaining / 0.35)
        let calm = Double.random(in: 0...1) < 0.15
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for w in windows { draw(into: w, k: calm ? 0 : k) }
        CATransaction.commit()
    }

    private func draw(into w: GlitchWindow, k: Double) {
        let host = w.host
        host.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard k > 0.02 else { return }
        let b = host.bounds
        let W = b.width, H = b.height

        if let shot = shots[w.displayID] {
            // Base: real screenshot torn into horizontally displaced slices.
            var y: CGFloat = 0
            while y < H {
                let h = CGFloat.random(in: 4...max(6, H * 0.12))
                let torn = Double.random(in: 0...1) < 0.35 + 0.5 * k
                let dx = torn ? CGFloat.random(in: -1...1) * W * 0.12 * k : 0
                let s = CALayer()
                s.contents = shot.full
                s.contentsGravity = .resize
                s.contentsRect = CGRect(x: 0, y: y / H, width: 1, height: min(h, H - y) / H)
                s.frame = CGRect(x: dx, y: y, width: W, height: min(h, H - y))
                host.addSublayer(s)
                y += h
            }
            // Chromatic aberration: red and cyan ghosts pulled apart.
            let off = CGFloat(8 + 40 * k)
            for (img, dx) in [(shot.red, off), (shot.cyan, -off)] {
                let l = CALayer()
                l.contents = img
                l.contentsGravity = .resize
                l.frame = b.offsetBy(dx: dx * CGFloat.random(in: 0.5...1), dy: CGFloat.random(in: -3...3))
                l.compositingFilter = "screenBlendMode"
                l.opacity = Float(0.35 + 0.4 * k)
                host.addSublayer(l)
            }
        } else {
            // No screen access: tint + noise slices over the live desktop.
            for _ in 0..<Int(10 + 30 * k) {
                let s = CALayer()
                let h = CGFloat.random(in: 2...H * 0.06)
                s.frame = CGRect(x: CGFloat.random(in: -W * 0.1...W * 0.3), y: .random(in: 0...H), width: W * .random(in: 0.3...1.1), height: h)
                s.backgroundColor = NSColor(calibratedHue: [0.83, 0.5, 0.33, 0.0].randomElement()!, saturation: 1, brightness: 1, alpha: 0.5).cgColor
                s.compositingFilter = ["differenceBlendMode", "screenBlendMode", "colorDodgeBlendMode"].randomElement()!
                host.addSublayer(s)
            }
        }

        // Corrupted macroblocks.
        for _ in 0..<Int(4 + 26 * k) {
            let bl = CALayer()
            let sz = CGFloat.random(in: 16...140)
            bl.frame = CGRect(x: .random(in: 0...W), y: .random(in: 0...H), width: sz * .random(in: 1...4), height: sz)
            let hue = [0.83, 0.5, 0.33, 0.95].randomElement()!
            bl.backgroundColor = NSColor(calibratedHue: hue, saturation: 1, brightness: 1, alpha: .random(in: 0.4...0.9)).cgColor
            bl.compositingFilter = Bool.random() ? "differenceBlendMode" : nil
            host.addSublayer(bl)
        }

        // Scanlines.
        let scan = CAReplicatorLayer()
        scan.frame = b
        let line = CALayer()
        line.frame = CGRect(x: 0, y: 0, width: W, height: 1)
        line.backgroundColor = NSColor.black.withAlphaComponent(0.35 * k).cgColor
        scan.addSublayer(line)
        scan.instanceCount = Int(H / 3)
        scan.instanceTransform = CATransform3DMakeTranslation(0, 3, 0)
        host.addSublayer(scan)

        // Occasional full-screen invert flash on hard slaps.
        if k > 0.6, Double.random(in: 0...1) < 0.12 {
            let f = CALayer()
            f.frame = b
            f.backgroundColor = NSColor.white.cgColor
            f.compositingFilter = "differenceBlendMode"
            host.addSublayer(f)
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let accel = Accelerometer()
    var engine: GlitchEngine!
    var status: NSStatusItem!
    var enabled = true
    var slaps = 0
    let countItem = NSMenuItem(title: "Slaps: 0", action: nil, keyEquivalent: "")
    let sensitivities: [(String, Double)] = [("Low", 0.6), ("Medium", 0.35), ("High", 0.18)]

    func applicationDidFinishLaunching(_ n: Notification) {
        engine = GlitchEngine()
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "bolt.horizontal.fill", accessibilityDescription: "SlapGlitch")
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Enabled", action: #selector(toggle(_:)), keyEquivalent: "")
        toggle.state = .on
        menu.addItem(toggle)
        menu.addItem(countItem)
        menu.addItem(.separator())
        let sens = NSMenuItem(title: "Sensitivity", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (i, (name, _)) in sensitivities.enumerated() {
            let it = NSMenuItem(title: name, action: #selector(setSensitivity(_:)), keyEquivalent: "")
            it.tag = i
            it.state = i == 1 ? .on : .off
            sub.addItem(it)
        }
        sens.submenu = sub
        menu.addItem(sens)
        menu.addItem(NSMenuItem(title: "Test Glitch", action: #selector(test), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Screen Recording Settings…", action: #selector(openPrivacy), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SlapGlitch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { $0.target = $0.action == #selector(NSApplication.terminate(_:)) ? nil : self }
        sub.items.forEach { $0.target = self }
        status.menu = menu

        guard Accelerometer.isAvailable(), accel.start() else {
            let a = NSAlert()
            a.messageText = "No accelerometer found"
            a.informativeText = "SlapGlitch needs an Apple Silicon MacBook (M2 or later) with the SPU motion sensor."
            a.runModal()
            NSApp.terminate(nil)
            return
        }
        accel.onSlap = { [weak self] g in
            guard let self, self.enabled else { return }
            self.slaps += 1
            self.countItem.title = "Slaps: \(self.slaps)"
            self.engine.trigger(strength: min(1, 0.25 + g / 1.5))
        }
        if CommandLine.arguments.contains("--demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.test() }
        }
    }

    @objc func toggle(_ i: NSMenuItem) { enabled.toggle(); i.state = enabled ? .on : .off }
    @objc func setSensitivity(_ i: NSMenuItem) {
        accel.threshold = sensitivities[i.tag].1
        i.menu?.items.forEach { $0.state = $0 === i ? .on : .off }
    }
    @objc func test() { engine.trigger(strength: 0.8) }
    @objc func openPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
