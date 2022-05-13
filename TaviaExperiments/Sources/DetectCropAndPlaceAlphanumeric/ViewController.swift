import ARKit
import SwiftUI
import UIKit

class CropAlphanumericImageProcessor {
    private var request: VNRecognizeTextRequest?
    private var results: [VNRecognizedTextObservation]?
    private var currentFrame: ARFrame?

    func setup() {
        request = VNRecognizeTextRequest(completionHandler: completionHandler)
    }

    private func completionHandler(request: VNRequest, error: Error?) {
        guard error == nil else { return }
        self.results = request.results as? [VNRecognizedTextObservation]
    }

    var processing: Bool {
        return currentFrame != nil
    }

    func perform(
        frame: ARFrame, viewportSize: CGSize, interfaceOrientation: UIInterfaceOrientation,
        searchingText: String
    )
        -> UIImage?
    {
        guard currentFrame == nil else { return nil }
        currentFrame = frame
        do {
            defer { currentFrame = nil }
            guard let ciImage = screenImage(viewportSize, interfaceOrientation) else { return nil }
            guard let request = request else { return nil }
            try VNImageRequestHandler(ciImage: ciImage).perform([request])
            guard let results = results else { return nil }
            for result in results {
                guard let candidate = result.topCandidates(1).first else { continue }
                let seen = candidate.string.lowercased()
                if let range = seen.range(of: searchingText.lowercased()),
                    let boundingBox = try? candidate.boundingBox(for: range)?.boundingBox
                {
                    let cropped = cropImage(ciImage, boundingBox)
                    return convertToUIImage(cropped)
                }
            }
        } catch {
            print("Error: \(error)")
        }
        return nil
    }

    private func screenImage(_ viewportSize: CGSize, _ interfaceOrientation: UIInterfaceOrientation)
        -> CIImage?
    {
        guard let frame = currentFrame else { return nil }
        let transform = screenImageTransform(frame, viewportSize, interfaceOrientation)
        let buffer = frame.capturedImage
        return CIImage(cvPixelBuffer: buffer).transformed(by: transform)
    }

    private func screenImageTransform(
        _ frame: ARFrame, _ viewportSize: CGSize, _ interfaceOrientation: UIInterfaceOrientation
    ) -> CGAffineTransform {
        let buffer = frame.capturedImage
        let imageSize = CGSize(
            width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let flipIfPortrait: CGAffineTransform
        if interfaceOrientation.isPortrait {
            flipIfPortrait = CGAffineTransform
                .identity
                .concatenating(CGAffineTransform(scaleX: -1, y: -1))
                .concatenating(CGAffineTransform(translationX: 1, y: 1))
        } else {
            flipIfPortrait = CGAffineTransform.identity
        }
        return CGAffineTransform
            .identity
            .concatenating(
                CGAffineTransform(scaleX: 1.0 / imageSize.width, y: 1.0 / imageSize.height)
            )
            .concatenating(flipIfPortrait)
            .concatenating(
                frame.displayTransform(for: interfaceOrientation, viewportSize: viewportSize)
            )
            .concatenating(CGAffineTransform(scaleX: viewportSize.width, y: viewportSize.height))
    }

    private func cropImage(_ ciImage: CIImage, _ boundingBox: CGRect) -> CIImage {
        let transform = CGAffineTransform
            .identity
            .concatenating(
                CGAffineTransform(scaleX: ciImage.extent.width, y: ciImage.extent.height)
            )
            .concatenating(
                CGAffineTransform(translationX: ciImage.extent.minX, y: ciImage.extent.minY))
        return ciImage.cropped(to: boundingBox.applying(transform))
    }

    private func convertToUIImage(_ ciImage: CIImage) -> UIImage? {
        let ciContext = CIContext(options: nil)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage.init(cgImage: cgImage)
    }
}

protocol CropAlphanumericViewControllerDelegate: AnyObject {
    func cropAlphanumericViewController(
        _ vc: CropAlphanumericViewController, didRecognize image: UIImage)
}

class CropAlphanumericViewController: UIViewController, ARSessionDelegate {
    private let updateQueue = DispatchQueue(
        label: "com.example.TaviaExperiments.serialSceneKitQueue")
    private let visionQueue = DispatchQueue(label: "com.example.TaviaExperiments.serialVisionQueue")
    private let sceneView = ARSCNView()
    private var imageProcessor: CropAlphanumericImageProcessor?
    var delegate: CropAlphanumericViewControllerDelegate?
    var searchingText: String?
    var foundImage: UIImage?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(sceneView)
        sceneView.frame = CGRect(origin: .zero, size: view.bounds.size)
        sceneView.session.delegate = self
        sceneView.debugOptions = [.showFeaturePoints, .showWorldOrigin]

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(placeImage))
        sceneView.addGestureRecognizer(tapGesture)

        imageProcessor = CropAlphanumericImageProcessor()
        imageProcessor?.setup()
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

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard self.foundImage == nil else { return }
        guard let imageProcessor = imageProcessor, !imageProcessor.processing else { return }
        guard let interfaceOrientation = sceneView.window?.windowScene?.interfaceOrientation else {
            return
        }
        guard let searchingText = searchingText else { return }
        let viewportSize = sceneView.bounds.size
        let currentFrame = frame
        visionQueue.async { [weak self] in
            guard
                !imageProcessor.processing,
                let uiImage = imageProcessor.perform(
                    frame: currentFrame,
                    viewportSize: viewportSize,
                    interfaceOrientation: interfaceOrientation,
                    searchingText: searchingText)
            else { return }
            if let self = self {
                self.foundImage = uiImage
                self.delegate?.cropAlphanumericViewController(self, didRecognize: uiImage)
            }
        }
    }

    @objc private func placeImage() {
        guard let camera = sceneView.pointOfView else { return }
        guard let uiImage = foundImage else { return }
        let imageNode = makeImageNode(uiImage)
        let position = SCNVector3(0.0, 0.0, -1.0)
        imageNode.position = camera.convertPosition(position, to: nil)
        imageNode.eulerAngles = camera.eulerAngles
        sceneView.prepare(
            [imageNode],
            completionHandler: { [weak self] _ in
                guard let self = self else { return }
                self.sceneView.scene.rootNode.addChildNode(imageNode)
            })
    }

    private func makeImageNode(_ image: UIImage) -> SCNNode {
        let scale: CGFloat = 0.25
        let width = scale
        let height = image.size.height * scale / image.size.width
        let imagePlane: SCNPlane = SCNPlane(width: width, height: height)
        imagePlane.firstMaterial?.diffuse.contents = image
        imagePlane.firstMaterial?.isDoubleSided = true
        let imageNode = SCNNode(geometry: imagePlane)
        let node = SCNNode()
        node.addChildNode(imageNode)
        return node
    }
}

// MARK: SwiftUI
struct CropAlphanumericViewControllerRepresentable: UIViewControllerRepresentable {
    @Binding var found: Bool
    let searchingText: String

    typealias UIViewControllerType = CropAlphanumericViewController

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> CropAlphanumericViewController {
        let vc = CropAlphanumericViewController()
        vc.delegate = context.coordinator
        vc.searchingText = searchingText
        return vc
    }

    func updateUIViewController(
        _ uiViewController: CropAlphanumericViewController, context: Context
    ) {
        let text = searchingText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text == "" {
            uiViewController.searchingText = nil
        } else {
            uiViewController.searchingText = text
        }
    }

    class Coordinator: NSObject, CropAlphanumericViewControllerDelegate {
        let parent: CropAlphanumericViewControllerRepresentable

        init(_ parent: CropAlphanumericViewControllerRepresentable) {
            self.parent = parent
        }

        func cropAlphanumericViewController(
            _ vc: CropAlphanumericViewController, didRecognize image: UIImage
        ) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.found = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

public struct ContentView: View {
    @State private var found: Bool = false
    @State private var searchingText: String = "harajuku"

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            CropAlphanumericViewControllerRepresentable(
                found: $found, searchingText: searchingText
            )
            .edgesIgnoringSafeArea(.all)
            VStack(alignment: .leading) {
                Text(statusLabel)
                    .font(.footnote)
                    .padding()
                    .background { Color(UIColor.systemBackground).opacity(0.5) }
                    .padding(.leading)
                TextField("search", text: $searchingText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
            }
        }
    }

    private var statusLabel: String {
        if found {
            return "\"\(searchingText)\" found"
        } else {
            return "searching \"\(searchingText)\""
        }
    }
}
