import AppKit
import SceneKit

/// Halloween mode: a 3D zombie sprints out from deep inside the screen and lunges at you,
/// rendered over the live desktop with a transparent background.
/// Model: "Animated Zombie" by Quaternius (CC BY 3.0), via poly.pizza. Baked with tools/convert_zombie.py.
final class ScareEngine {
    private var window: NSWindow?
    private var view: SCNView?
    private var playing = false
    private let modelURL = Bundle.main.url(forResource: "zombie", withExtension: "usdz")

    // Timing matches the baked clip: 4 run cycles (~2.5 s), then a ~0.7 s arms-out grab.
    private let runTime = 2.5
    private let lungeTime = 0.45

    var available: Bool { modelURL != nil }

    func trigger() {
        guard let modelURL, !playing,
              let scene = try? SCNScene(url: modelURL, options: nil) else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        playing = true

        // The model is Z-up; stand it up. It faces +Z, i.e. towards the camera.
        let zombie = SCNNode()
        scene.rootNode.childNodes.forEach(zombie.addChildNode)
        zombie.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(zombie)

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 60
        cam.camera?.zNear = 0.5
        scene.rootNode.addChildNode(cam)
        light(scene)

        // Feet on a floor below eye level, far down the "inside" of the screen.
        zombie.position = SCNVector3(0, -6, -100)
        zombie.runAction(.sequence([
            .move(to: SCNVector3(0, -6, -16), duration: runTime),
            // Leap: the snarling face fills the screen.
            .move(to: SCNVector3(0.3, -6.1, -3.1), duration: lungeTime),
            .wait(duration: 0.3),
            .run { [weak self] _ in DispatchQueue.main.async { self?.finish() } },
        ]))

        let v = SCNView(frame: NSRect(origin: .zero, size: screen.frame.size))
        v.scene = scene
        v.pointOfView = cam
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.isPlaying = true
        v.rendersContinuously = true
        view = v

        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.setFrame(screen.frame, display: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.contentView = v
        w.orderFrontRegardless()
        window = w
    }

    /// Low, cold key light from below plus a red rim from behind: classic horror lighting.
    private func light(_ scene: SCNScene) {
        func add(_ type: SCNLight.LightType, _ color: NSColor, _ intensity: CGFloat, at p: SCNVector3?) {
            let n = SCNNode()
            n.light = SCNLight()
            n.light?.type = type
            n.light?.color = color
            n.light?.intensity = intensity
            if let p { n.position = p; n.look(at: SCNVector3(0, -2, -20)) }
            scene.rootNode.addChildNode(n)
        }
        add(.ambient, NSColor(srgbRed: 0.35, green: 0.45, blue: 0.4, alpha: 1), 250, at: nil)
        add(.directional, NSColor(srgbRed: 0.75, green: 1, blue: 0.8, alpha: 1), 1100, at: SCNVector3(0, -8, 10))
        add(.directional, NSColor(srgbRed: 1, green: 0.15, blue: 0.1, alpha: 1), 900, at: SCNVector3(4, 6, -60))
    }

    private func finish() {
        view?.isPlaying = false
        window?.orderOut(nil)
        window = nil
        view = nil
        playing = false
    }
}
