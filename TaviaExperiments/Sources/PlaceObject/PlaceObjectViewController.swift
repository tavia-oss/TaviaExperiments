import ARKit
import SwiftUI
import UIKit

class PlaceObjectViewController: UIViewController {
    let sceneView = ARSCNView()
    let colors: [UIColor] = [
        (255, 75, 0),  // red
        (255, 241, 0),  // yellow
        (3, 175, 122),  // green
        (0, 90, 255),  // blue
        (77, 196, 255),  // skyblue
        (255, 128, 130),  // pink
        (246, 170, 0),  // orange
        (153, 0, 153),  // purple
        (128, 64, 0),  // brown
        (255, 255, 255),  // white
        (200, 200, 203),  // lightgray
        (132, 145, 158),  // gray
        (0, 0, 0),  // black
    ].map { (r, g, b) in UIColor.init(red: r, green: g, blue: b, alpha: 1.0) }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(sceneView)
        sceneView.frame = CGRect(origin: .zero, size: view.bounds.size)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(placeObject))
        sceneView.addGestureRecognizer(tapGesture)

        sceneView.autoenablesDefaultLighting = true
        sceneView.debugOptions = [.showFeaturePoints, .showWorldOrigin]
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
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    @objc private func placeObject() {
        guard let color = colors.randomElement() else { return }
        guard let camera = sceneView.pointOfView else { return }
        let node = SCNNode()
        let size: CGFloat = 0.15
        node.geometry = SCNBox(width: size, height: size, length: size, chamferRadius: size / 10)
        let material = SCNMaterial()
        material.diffuse.contents = color
        node.geometry?.materials = [material]
        let position = SCNVector3(0.0, 0.0, -0.5)
        node.position = camera.convertPosition(position, to: nil)
        node.eulerAngles = camera.eulerAngles
        sceneView.scene.rootNode.addChildNode(node)
    }
}

// MARK: SwiftUI
struct PlaceObjectViewControllerRepresentable: UIViewControllerRepresentable {
    typealias UIViewControllerType = PlaceObjectViewController

    func makeUIViewController(context: Context) -> PlaceObjectViewController {
        return PlaceObjectViewController()
    }

    func updateUIViewController(_ uiViewController: PlaceObjectViewController, context: Context) {}
}

public struct PlaceObjectView: View {
    public init() {}

    public var body: some View {
        PlaceObjectViewControllerRepresentable()
            .edgesIgnoringSafeArea(.all)
    }
}
