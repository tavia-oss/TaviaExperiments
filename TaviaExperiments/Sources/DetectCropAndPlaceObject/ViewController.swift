import ARKit
import SwiftUI
import TransformHelper

struct RecognizedObject {
    let label: String
    let confidence: Float
    let boundingBox: CGRect
}

class ImageProcessor {
    private var request: VNCoreMLRequest?
    private var currentImage: CIImage?
    var processing: Bool {
        return currentImage != nil
    }

    init() {
        guard
            let modelDescriptionURL = Bundle.module.url(
                forResource: "YOLOv3Tiny", withExtension: "mlmodel")
        else {
            print("Model file was not found")
            return
        }
        guard let compiledModelURL = try? MLModel.compileModel(at: modelDescriptionURL) else {
            print("MLModel.compileModel failed")
            return
        }
        guard let model = try? VNCoreMLModel(for: MLModel(contentsOf: compiledModelURL)) else {
            print("VNCoreMLModel.init failed")
            return
        }
        request = VNCoreMLRequest(model: model)
        request?.imageCropAndScaleOption = .centerCrop
        request?.usesCPUOnly = false
    }

    func perform(ciImage: CIImage) async throws -> [String: RecognizedObject]? {
        guard currentImage == nil else { return nil }
        currentImage = ciImage
        defer { currentImage = nil }
        guard let request = request else { return nil }
        let requestHandler = VNImageRequestHandler(ciImage: ciImage)
        try requestHandler.perform([request])
        guard
            let objectObservations = request.results?.compactMap({
                $0 as? VNRecognizedObjectObservation
            }),
            !objectObservations.isEmpty
        else { return nil }
        let result: [String: RecognizedObject] = objectObservations.reduce([:]) {
            partialResult, objectObservation in
            let topClassification = objectObservation.labels[0]
            let recognizedObject = RecognizedObject(
                label: topClassification.identifier,
                confidence: topClassification.confidence,
                boundingBox: objectObservation.boundingBox)
            return partialResult.merging([recognizedObject.label: recognizedObject]) {
                $0.confidence < $1.confidence ? $1 : $0
            }
        }
        return result
    }
}

enum PlaceMode: String, CaseIterable, Identifiable {
    case inSpace = "in space"
    case onWallOrFloor = "on wall/floor"

    var id: String { rawValue }
}

protocol ViewControllerDelegate: AnyObject {
    func viewController(_ vc: ViewController, didCapture image: UIImage)
}

class ViewController: UIViewController, ARSessionDelegate {
    private let updateQueue = DispatchQueue(
        label: "com.example.TaviaExperiments.serialSceneKitQueue")
    private let sceneView = ARSCNView()
    private let imageProcessor = ImageProcessor()
    private let ciContext = CIContext(options: nil)
    private var foundObjectImage: UIImage?
    var delegate: ViewControllerDelegate?
    var placeMode: PlaceMode?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(sceneView)
        sceneView.frame = CGRect(origin: .zero, size: view.bounds.size)
        sceneView.session.delegate = self

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapHandler))
        sceneView.addGestureRecognizer(tapGesture)
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
        guard
            foundObjectImage == nil,
            !imageProcessor.processing,
            let frame = sceneView.session.currentFrame,
            let interfaceOrientation = sceneView.window?.windowScene?.interfaceOrientation
        else { return }
        let viewportSize = sceneView.bounds.size
        let transform = TransformHelper.screenTransform(frame, viewportSize, interfaceOrientation)
        let buffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: buffer)
            .transformed(by: transform)
            .cropped(to: CGRect(origin: .zero, size: sceneView.bounds.size))
        Task {
            let confidenceThreshold: Float = 0.9
            guard
                let recognizedObjects = (try? await imageProcessor.perform(ciImage: ciImage)),
                let recognizedObject = recognizedObjects.first(where: {
                    confidenceThreshold <= $0.value.confidence
                })
            else { return }
            print(recognizedObject)
            let transform = CGAffineTransform(
                scaleX: ciImage.extent.width, y: ciImage.extent.height)
            let boundingBox = recognizedObject.value.boundingBox.applying(transform)
            let cropped = ciImage.cropped(to: boundingBox)
            guard let cgImage = ciContext.createCGImage(cropped, from: cropped.extent) else {
                return
            }
            guard foundObjectImage == nil else { return }
            foundObjectImage = UIImage.init(cgImage: cgImage)
            if let uiImage = foundObjectImage {
                delegate?.viewController(self, didCapture: uiImage)
            }
        }
    }

    @objc private func tapHandler(_ sender: UITapGestureRecognizer) {
        guard sender.state == .ended else { return }
        guard let placeMode = placeMode else { return }
        guard let uiImage = foundObjectImage else { return }
        let imageNode = makeImageNode(uiImage, placeMode)
        switch placeMode {
        case .inSpace:
            placeObjectInSpace(imageNode)
        case .onWallOrFloor:
            placeObjectOnWallOrFloor(imageNode)
        }
    }

    private func placeObjectInSpace(_ imageNode: SCNNode) {
        guard let camera = sceneView.pointOfView else { return }
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

    private func placeObjectOnWallOrFloor(_ imageNode: SCNNode) {
        let location = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        guard
            let query = sceneView.raycastQuery(
                from: location, allowing: .estimatedPlane, alignment: .any),
            let result = sceneView.session.raycast(query).first
        else { return }
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

    private func makeImageNode(_ image: UIImage, _ placeMode: PlaceMode) -> SCNNode {
        let scale: CGFloat = 0.25
        let width = scale
        let height = image.size.height * scale / image.size.width
        let imagePlane: SCNPlane = SCNPlane(width: width, height: height)
        imagePlane.firstMaterial?.diffuse.contents = image
        imagePlane.firstMaterial?.isDoubleSided = true
        let imageNode = SCNNode(geometry: imagePlane)
        if placeMode == .onWallOrFloor {
            imageNode.eulerAngles.x = -.pi / 2
        }
        let node = SCNNode()
        node.addChildNode(imageNode)
        return node
    }
}

// MARK: SwiftUI
struct ViewControllerRepresentable: UIViewControllerRepresentable {
    typealias UIViewControllerType = ViewController

    @Binding var image: UIImage?
    let placeMode: PlaceMode

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> ViewController {
        let vc = ViewController()
        vc.delegate = context.coordinator
        vc.placeMode = placeMode
        return vc
    }

    func updateUIViewController(_ uiViewController: ViewController, context: Context) {
        uiViewController.placeMode = placeMode
    }

    class Coordinator: NSObject, ViewControllerDelegate {
        let parent: ViewControllerRepresentable

        init(_ parent: ViewControllerRepresentable) {
            self.parent = parent
        }

        func viewController(_ vc: ViewController, didCapture image: UIImage) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.image = image
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

public struct ContentView: View {
    @State private var image: UIImage?
    @State private var placeMode: PlaceMode

    public init() {
        placeMode = .inSpace
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ViewControllerRepresentable(image: $image, placeMode: placeMode)
                .edgesIgnoringSafeArea(.all)
            VStack(alignment: .trailing) {
                if let image = image, let thumbSize = calcThumbSize(image: image) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .border(.white)
                        .frame(width: thumbSize.width, height: thumbSize.height)
                        .padding(.bottom)
                }
                HStack {
                    Text("Place image")
                        .font(.footnote)
                    Picker("PlaceMode", selection: $placeMode) {
                        ForEach(PlaceMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding()
        }
    }

    private func calcThumbSize(image: UIImage) -> CGSize? {
        let width: CGFloat = image.size.width
        let height: CGFloat = image.size.height
        if width <= 0 || height <= 0 {
            return nil
        }
        let longSide: CGFloat = 200
        if width <= longSide, height <= longSide {
            return CGSize(width: width, height: height)
        }
        if width < height {
            return CGSize(width: width / height * longSide, height: longSide)
        } else {
            return CGSize(width: longSide, height: height / width * longSide)
        }
    }
}
