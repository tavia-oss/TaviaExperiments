import ARKit
import ColorHelper
import CoreImage.CIFilterBuiltins
import SwiftUI
import TransformHelper
import UIKit

struct HSBColor {
    private(set) var hue: CGFloat = 0
    private(set) var saturation: CGFloat = 0
    private(set) var brightness: CGFloat = 0

    init?(uiColor: UIColor) {
        let converted = uiColor.getHue(
            &hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        if !converted { return nil }
    }

    init?(color: Color) {
        self.init(uiColor: UIColor(color))
    }

    init?(cgColor: CGColor) {
        self.init(uiColor: UIColor(cgColor: cgColor))
    }

    func isAlmost(_ that: HSBColor) -> Bool {
        let hueOffsets: [CGFloat] = [-1.0, 0.0, 1.0]
        var result = true
        result = result && abs(saturation - that.saturation) <= 0.1
        result = result && abs(brightness - that.brightness) <= 0.1
        result = result && hueOffsets.contains { return abs(hue + $0 - that.hue) <= 0.1 }
        return result
    }
}

struct RGBColor {
    private(set) var red: CGFloat = 0
    private(set) var green: CGFloat = 0
    private(set) var blue: CGFloat = 0

    init?(color: Color) {
        let converted = UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: nil)
        if !converted { return nil }
    }
}

enum ColorClassificationMethod: String, CaseIterable {
    case majority = "Majority of discrete points"
    case ciPixellate = "Result of CIPixellate"
    case ciAreaAverage = "Result of CIAreaAverage"
}

protocol ColorClassifier {
    func classify(ciImage: CIImage) -> CGColor?
}

struct MajorityColorClassifier: ColorClassifier {
    private let ciContext = CIContext(options: nil)

    func classify(ciImage: CIImage) -> CGColor? {
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        let matrixSize = 10
        let unitWidth = cgImage.width / matrixSize
        let unitHeight = cgImage.height / matrixSize
        let colorHelper = ColorHelper(cgImage: cgImage)
        var colors = [(CGColor, HSBColor)]()
        for xi in 0..<10 {
            for yi in 0..<10 {
                let x = xi * unitWidth + unitWidth / 2
                let y = yi * unitHeight + unitHeight / 2
                if let cgColor = colorHelper?.pixelColor(x: x, y: y),
                    let hsbColor = HSBColor(cgColor: cgColor)
                {
                    colors.append((cgColor, hsbColor))
                }
            }
        }
        guard matrixSize * matrixSize / 2 <= colors.count else { return nil }
        let threshold = colors.count / 2 + 1
        for (cgColor, hsbColor) in colors {
            let count = colors.lazy.filter { hsbColor.isAlmost($0.1) }.count
            if threshold <= count {
                return cgColor
            }
        }
        return nil
    }
}

struct PixellateColorClassifier: ColorClassifier {
    private let ciContext = CIContext(options: nil)

    func classify(ciImage: CIImage) -> CGColor? {
        let filter = CIFilter.pixellate()
        filter.setDefaults()
        filter.inputImage = ciImage
        filter.scale = Float(max(ciImage.extent.width, ciImage.extent.height))
        guard
            let outputImage = filter.outputImage,
            let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent)
        else { return nil }
        let colorHelper = ColorHelper(cgImage: cgImage)
        return colorHelper?.pixelColor(x: cgImage.width / 2, y: cgImage.height / 2)
    }
}

struct AreaAverageColorClassifier: ColorClassifier {
    private let ciContext = CIContext(options: nil)

    func classify(ciImage: CIImage) -> CGColor? {
        let filter = CIFilter.areaAverage()
        filter.setDefaults()
        filter.inputImage = ciImage
        filter.extent = ciImage.extent
        guard
            let outputImage = filter.outputImage,
            let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent)
        else { return nil }
        let colorHelper = ColorHelper(cgImage: cgImage)
        return colorHelper?.pixelColor(x: 0, y: 0)
    }
}

protocol ViewControllerDelegate: AnyObject {
    func viewController(_ vc: ViewController, didClassify color: UIColor?)
}

class ViewController: UIViewController, ARSessionDelegate {
    private let updateQueue = DispatchQueue(
        label: "com.example.TaviaExperiments.serialSceneKitQueue")
    private let sceneView = ARSCNView()
    private let selectionLayer = CAShapeLayer()
    private var selectionRect = CGRect(origin: .zero, size: CGSize(width: 256, height: 256))
    var colorClassificationMethod: ColorClassificationMethod
    var searchingColor: UIColor
    var delegate: ViewControllerDelegate

    init(
        colorClassificationMethod: ColorClassificationMethod, searchingColor: UIColor,
        delegate: ViewControllerDelegate
    ) {
        self.colorClassificationMethod = colorClassificationMethod
        self.searchingColor = searchingColor
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(sceneView)
        sceneView.frame = CGRect(origin: .zero, size: view.bounds.size)
        sceneView.layer.addSublayer(selectionLayer)
        selectionLayer.frame = CGRect(origin: .zero, size: sceneView.bounds.size)

        sceneView.session.delegate = self
        sceneView.autoenablesDefaultLighting = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        resetTracking()
        setupRectLayer()
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

    private func setupRectLayer() {
        selectionRect.size = CGSize(width: 256, height: 256)
        selectionRect.origin = CGPoint(
            x: selectionLayer.bounds.midX - selectionRect.width / 2,
            y: selectionLayer.bounds.midY - selectionRect.height / 2)
        selectionLayer.path = UIBezierPath(rect: selectionRect).cgPath
        selectionLayer.strokeColor = UIColor.white.cgColor
        selectionLayer.fillColor = nil
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let foundColor = pickColor() else {
            delegate.viewController(self, didClassify: nil)
            return
        }
        delegate.viewController(self, didClassify: foundColor)
        if let searchingHSBColor = HSBColor(uiColor: searchingColor),
            let foundHSBColor = HSBColor(uiColor: foundColor),
            searchingHSBColor.isAlmost(foundHSBColor)
        {
            let location = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
            placeObject(location, foundColor)
        }
    }

    private func pickColor() -> UIColor? {
        guard
            let frame = sceneView.session.currentFrame,
            let interfaceOrientation = sceneView.window?.windowScene?.interfaceOrientation
        else { return nil }
        let viewportSize = sceneView.bounds.size
        let transform = TransformHelper.screenTransform(frame, viewportSize, interfaceOrientation)
        let ciImage = CIImage(cvPixelBuffer: frame.capturedImage)
            .transformed(by: transform)
            .cropped(to: selectionRect)
        let colorClassifier: ColorClassifier
        switch colorClassificationMethod {
        case .majority:
            colorClassifier = MajorityColorClassifier()
        case .ciPixellate:
            colorClassifier = PixellateColorClassifier()
        case .ciAreaAverage:
            colorClassifier = AreaAverageColorClassifier()
        }
        guard let cgColor = colorClassifier.classify(ciImage: ciImage) else { return nil }
        return UIColor(cgColor: cgColor)
    }

    private func placeObject(_ location: CGPoint, _ color: UIColor) {
        guard
            let query = sceneView.raycastQuery(
                from: location, allowing: .estimatedPlane, alignment: .any),
            let result = sceneView.session.raycast(query).first
        else { return }
        let node = SCNNode()
        let size: CGFloat = 0.02
        node.geometry = SCNBox(width: size, height: size, length: size, chamferRadius: size / 10)
        let material = SCNMaterial()
        material.diffuse.contents = color
        node.geometry?.materials = [material]
        sceneView.scene.rootNode.addChildNode(node)
        node.simdWorldTransform = result.worldTransform
        self.updateQueue.async {
            let anchor = ARAnchor(transform: node.simdWorldTransform)
            self.sceneView.session.add(anchor: anchor)
        }
    }
}

// MARK: SwiftUI
struct ViewControllerRepresentable: UIViewControllerRepresentable {
    let colorClassificationMethod: ColorClassificationMethod
    let searchingColor: Color
    @Binding var foundColor: Color?

    typealias UIViewControllerType = ViewController

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> ViewController {
        return ViewController(
            colorClassificationMethod: colorClassificationMethod,
            searchingColor: UIColor(searchingColor), delegate: context.coordinator)
    }

    func updateUIViewController(_ uiViewController: ViewController, context: Context) {
        uiViewController.colorClassificationMethod = colorClassificationMethod
        uiViewController.searchingColor = UIColor(searchingColor)
    }

    class Coordinator: NSObject, ViewControllerDelegate {
        let parent: ViewControllerRepresentable

        init(_ parent: ViewControllerRepresentable) {
            self.parent = parent
        }

        func viewController(_ vc: ViewController, didClassify color: UIColor?) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.foundColor = color.map({ Color($0) })
            }
        }
    }
}

public struct ContentView: View {
    @State private var colorClassificationMethod: ColorClassificationMethod
    @State private var searchingColor: Color
    @State private var foundColor: Color?

    public init() {
        colorClassificationMethod = .majority
        let taviaOrange = Color(.sRGB, red: Double(237) / 255, green: Double(110) / 255, blue: 0)
        searchingColor = taviaOrange
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            ViewControllerRepresentable(
                colorClassificationMethod: colorClassificationMethod,
                searchingColor: searchingColor, foundColor: $foundColor
            ).edgesIgnoringSafeArea(.all)
            HStack(alignment: .top) {
                colorInspector("searching:", searchingColor)
                    .frame(width: 75)
                Divider()
                colorInspector("found:", foundColor)
                    .frame(width: 75)
                Spacer()
                VStack(alignment: .trailing) {
                    methodMenu
                    Spacer()
                    ColorPicker("Change color", selection: $searchingColor, supportsOpacity: false)
                }
                .frame(width: 120)
            }
            .font(.footnote)
            .padding()
            .background { Color(UIColor.systemBackground).opacity(0.5) }
            .frame(height: 210)
        }
    }

    private func colorInspector(_ label: String, _ color: Color?) -> some View {
        var rgbColor: RGBColor?
        var hsbColor: HSBColor?
        if let color = color {
            rgbColor = RGBColor(color: color)
            hsbColor = HSBColor(color: color)
        }
        return VStack(alignment: .leading) {
            Text(label)
            RoundedRectangle(cornerRadius: 3, style: .circular)
                .fill(color ?? .clear)
                .frame(width: 22, height: 22)
            Divider()
            Text("R: \(format(rgbColor?.red))")
            Text("G: \(format(rgbColor?.green))")
            Text("B: \(format(rgbColor?.blue))")
            Divider()
            Text("H: \(format(hsbColor?.hue))")
            Text("S: \(format(hsbColor?.saturation))")
            Text("B: \(format(hsbColor?.brightness))")
        }
    }

    private func format(_ x: CGFloat?) -> String {
        guard let x = x else { return "-" }
        return String(format: "%.4f", Double(x))
    }

    private var methodMenu: some View {
        VStack(alignment: .leading) {
            Text("method: \(colorClassificationMethod.rawValue)")
            Menu("Change method") {
                ForEach(ColorClassificationMethod.allCases, id: \.rawValue) { method in
                    Button(action: { colorClassificationMethod = method }) {
                        if method == colorClassificationMethod {
                            Label(method.rawValue, systemImage: "checkmark")
                        } else {
                            Text(method.rawValue)
                        }
                    }
                }
            }
        }
    }
}
