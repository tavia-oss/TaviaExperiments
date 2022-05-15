import ARKit
import SwiftUI
import UIKit

class PlaceVideoViewController: UIViewController {
    let sceneView = ARSCNView()
    let videoURLs: [URL] = [
        "video1", "video2", "video3",
    ].compactMap { Bundle.module.url(forResource: $0, withExtension: "mp4") }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(sceneView)
        sceneView.frame = CGRect(origin: .zero, size: view.bounds.size)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(placeVideo))
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

    @objc private func placeVideo() {
        let screenCenter = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        guard
            let query = sceneView.raycastQuery(
                from: screenCenter, allowing: .estimatedPlane, alignment: .any),
            let result = sceneView.session.raycast(query).first
        else { return }
        guard let videoURL = videoURLs.randomElement() else { return }
        let videoNode = makeVideoNode(videoURL)
        sceneView.scene.rootNode.addChildNode(videoNode)
        videoNode.simdWorldTransform = result.worldTransform
    }

    private func makeVideoNode(_ videoURL: URL) -> SCNNode {
        let videoPlayer = AVPlayer(url: videoURL)
        let videoWidth: CGFloat = 1920
        let videoHeight: CGFloat = 1080
        let videoScene = SKScene(size: CGSize(width: videoWidth, height: videoHeight))
        let videoNode = SKVideoNode(avPlayer: videoPlayer)
        videoNode.position = CGPoint(x: videoScene.size.width / 2, y: videoScene.size.height / 2)
        videoNode.size = videoScene.size
        videoNode.yScale = -1.0
        videoNode.play()
        videoScene.addChild(videoNode)
        let videoPlane = SCNPlane(width: 0.5, height: 0.5 * videoHeight / videoWidth)
        videoPlane.firstMaterial?.diffuse.contents = videoScene
        videoPlane.firstMaterial?.isDoubleSided = true
        let innerNode = SCNNode(geometry: videoPlane)
        innerNode.eulerAngles.x = -.pi / 2
        let node = SCNNode()
        node.addChildNode(innerNode)
        return node
    }
}

// MARK: SwiftUI
struct PlaceVideoViewControllerRepresentable: UIViewControllerRepresentable {
    typealias UIViewControllerType = PlaceVideoViewController

    func makeUIViewController(context: Context) -> PlaceVideoViewController {
        return PlaceVideoViewController()
    }

    func updateUIViewController(_ uiViewController: PlaceVideoViewController, context: Context) {}
}

public struct PlaceVideoView: View {
    public init() {}

    public var body: some View {
        PlaceVideoViewControllerRepresentable()
            .edgesIgnoringSafeArea(.all)
    }
}
