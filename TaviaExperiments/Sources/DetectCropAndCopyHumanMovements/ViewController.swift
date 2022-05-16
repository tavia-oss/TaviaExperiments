import ARKit
import MetalKit
import SwiftUI

class ViewController: UIViewController, MTKViewDelegate, UIGestureRecognizerDelegate {
    private let sceneView = ARSCNView()
    private let mtkView = MTKView()
    private var renderer: Renderer?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(sceneView)
        sceneView.frame = CGRect(origin: .zero, size: view.bounds.size)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        sceneView.addSubview(mtkView)
        mtkView.frame = CGRect(origin: CGPoint(x: -200, y: 0), size: sceneView.bounds.size)
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtkView.backgroundColor = .clear

        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = self

        renderer = Renderer(session: sceneView.session, mtkView: mtkView)
        renderer?.drawRectResized(
            size: mtkView.drawableSize,
            interfaceOrientation: sceneView.window?.windowScene?.interfaceOrientation)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(panHandler))
        panGesture.delegate = self
        sceneView.addGestureRecognizer(panGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(pinchHandler))
        pinchGesture.delegate = self
        sceneView.addGestureRecognizer(pinchGesture)

        let rotationGesture = UIRotationGestureRecognizer(
            target: self, action: #selector(rotationHandler))
        rotationGesture.delegate = self
        sceneView.addGestureRecognizer(rotationGesture)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        resetTracking()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        sceneView.session.pause()
    }

    private func resetTracking() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = [.personSegmentation]
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer?.drawRectResized(
            size: size, interfaceOrientation: sceneView.window?.windowScene?.interfaceOrientation)
    }

    func draw(in view: MTKView) {
        renderer?.update()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }

    @objc
    private func panHandler(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: mtkView)
        mtkView.transform = mtkView.transform.translatedBy(x: translation.x, y: translation.y)
        gesture.setTranslation(.zero, in: mtkView)
    }

    @objc
    private func pinchHandler(_ gesture: UIPinchGestureRecognizer) {
        mtkView.transform = mtkView.transform.scaledBy(x: gesture.scale, y: gesture.scale)
        gesture.scale = 1
    }

    @objc
    private func rotationHandler(_ gesture: UIRotationGestureRecognizer) {
        mtkView.transform = mtkView.transform.rotated(by: gesture.rotation)
        gesture.rotation = 0
    }
}

// MARK: SwiftUI
struct ViewControllerRepresentable: UIViewControllerRepresentable {
    typealias UIViewControllerType = ViewController

    func makeUIViewController(context: Context) -> ViewController {
        return ViewController()
    }

    func updateUIViewController(_ uiViewController: ViewController, context: Context) {}
}

public struct ContentView: View {
    public init() {}

    public var body: some View {
        ViewControllerRepresentable()
            .edgesIgnoringSafeArea(.all)
    }
}
