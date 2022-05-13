import ARKit
import SwiftUI
import UIKit

public enum PlaceMode {
    case screenCenter
    case tappedLocation
}

class PlaceImageViewController: UIViewController {
    let sceneView = ARSCNView()
    let images: [UIImage] = [
        "image1", "image2", "image3",
    ].compactMap { UIImage.init(named: $0, in: .module, with: nil) }
    let updateQueue = DispatchQueue(label: "com.example.TaviaExperiments.serialSceneKitQueue")

    var placeMode: PlaceMode = .screenCenter

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(sceneView)
        sceneView.frame = CGRect(origin: .zero, size: view.bounds.size)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(placeImage))
        sceneView.addGestureRecognizer(tapGesture)

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
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    @objc private func placeImage(_ sender: UITapGestureRecognizer) {
        guard sender.state == .ended else { return }
        let location: CGPoint
        switch placeMode {
        case .screenCenter:
            location = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        case .tappedLocation:
            location = sender.location(in: sceneView)
        }
        guard
            let query = sceneView.raycastQuery(
                from: location, allowing: .estimatedPlane, alignment: .any),
            let result = sceneView.session.raycast(query).first
        else { return }
        guard let image = images.randomElement() else { return }
        let imageNode = makeImageNode(image)
        sceneView.prepare(
            [imageNode],
            completionHandler: { [weak self] _ in
                guard let self = self else { return }
                self.sceneView.scene.rootNode.addChildNode(imageNode)
                imageNode.simdWorldTransform = result.worldTransform
                self.updateQueue.async {
                    let anchor = ARAnchor(transform: imageNode.simdWorldTransform)
                    self.sceneView.session.add(anchor: anchor)
                }
            })
    }

    private func makeImageNode(_ image: UIImage) -> SCNNode {
        let scale: CGFloat = 0.5
        let width = scale
        let height = image.size.height * scale / image.size.width
        let imagePlane: SCNPlane = SCNPlane(width: width, height: height)
        imagePlane.firstMaterial?.diffuse.contents = image
        imagePlane.firstMaterial?.isDoubleSided = true
        let imageNode = SCNNode(geometry: imagePlane)
        imageNode.eulerAngles.x = -.pi / 2
        let node = SCNNode()
        node.addChildNode(imageNode)
        return node
    }
}

// MARK: SwiftUI
struct PlaceImageViewControllerRepresentable: UIViewControllerRepresentable {
    typealias UIViewControllerType = PlaceImageViewController

    let placeMode: PlaceMode

    func makeUIViewController(context: Context) -> PlaceImageViewController {
        let vc = PlaceImageViewController()
        vc.placeMode = placeMode
        return vc
    }

    func updateUIViewController(_ uiViewController: PlaceImageViewController, context: Context) {}
}

public struct PlaceImageView: View {
    public let placeMode: PlaceMode

    public init(placeMode: PlaceMode) {
        self.placeMode = placeMode
    }

    public var body: some View {
        PlaceImageViewControllerRepresentable(placeMode: placeMode)
            .edgesIgnoringSafeArea(.all)
    }
}
