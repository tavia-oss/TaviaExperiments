import ARKit
import GifHelper
import SwiftUI
import UIKit

class PlaceGifViewController: UIViewController {
    let sceneView = ARSCNView()
    let gifNames: [String] = ["anime1", "anime2", "anime3"]
    let updateQueue = DispatchQueue(label: "com.example.TaviaExperiments.serialSceneKitQueue")

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(sceneView)
        sceneView.frame = CGRect(origin: .zero, size: view.bounds.size)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(placeGif))
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

    @objc private func placeGif() {
        let screenCenter = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        guard
            let query = sceneView.raycastQuery(
                from: screenCenter, allowing: .estimatedPlane, alignment: .any),
            let result = sceneView.session.raycast(query).first
        else { return }
        guard let name = gifNames.randomElement() else { return }
        let imageNode = makeImageNode(name)
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

    private func makeImageNode(_ name: String) -> SCNNode {
        let scale: CGFloat = 0.5
        let gifPlane = SCNPlane(width: scale, height: scale)
        let gifImage = UIImage.gifImageWithName(name, in: .module)
        let gifImageView = UIImageView(image: gifImage)
        gifPlane.firstMaterial?.diffuse.contents = gifImageView
        gifPlane.firstMaterial?.isDoubleSided = true
        let gifNode = SCNNode(geometry: gifPlane)
        gifNode.eulerAngles.x = -.pi / 2
        let node = SCNNode()
        node.addChildNode(gifNode)
        return node
    }
}

// MARK: SwiftUI
struct PlaceGifViewControllerRepresentable: UIViewControllerRepresentable {
    typealias UIViewControllerType = PlaceGifViewController

    func makeUIViewController(context: Context) -> PlaceGifViewController {
        return PlaceGifViewController()
    }

    func updateUIViewController(_ uiViewController: PlaceGifViewController, context: Context) {}
}

public struct PlaceGifView: View {
    public init() {}

    public var body: some View {
        PlaceGifViewControllerRepresentable()
            .edgesIgnoringSafeArea(.all)
    }
}
