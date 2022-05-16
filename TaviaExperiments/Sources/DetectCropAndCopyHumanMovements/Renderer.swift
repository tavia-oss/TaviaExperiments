import ARKit
import CoreGraphics
import MetalKit

private let kMaxBuffersInFlight: Int = 3

private let kImagePlaneVertexData: [Float] = [
    -1.0, -1.0, 0.0, 1.0,
    1.0, -1.0, 1.0, 1.0,
    -1.0, 1.0, 0.0, 0.0,
    1.0, 1.0, 1.0, 0.0,
]

private func createTextureCache(_ device: MTLDevice) -> CVMetalTextureCache? {
    var textureCache: CVMetalTextureCache? = nil
    CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    return textureCache
}

private func createPipelineState(_ device: MTLDevice, _ pixelFormat: MTLPixelFormat)
    -> MTLRenderPipelineState?
{
    guard
        let defaultLibrary = try? device.makeDefaultLibrary(bundle: Bundle.module),
        let vertexFunction = defaultLibrary.makeFunction(name: "vertexShader"),
        let fragmentFunction = defaultLibrary.makeFunction(name: "fragmentShader")
    else { return nil }
    let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
    pipelineStateDescriptor.vertexFunction = vertexFunction
    pipelineStateDescriptor.fragmentFunction = fragmentFunction
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = pixelFormat
    return try? device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
}

class Renderer {
    private let inFlightSemaphore = DispatchSemaphore(value: kMaxBuffersInFlight)
    private let session: ARSession
    private let mtkView: MTKView
    private let device: MTLDevice
    private let capturedImageTextureCache: CVMetalTextureCache
    private let matteGenerator: ARMatteGenerator
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var interfaceOrientation: UIInterfaceOrientation = .portrait
    private var viewportSize: CGSize = CGSize()
    private var viewportSizeDidChange: Bool = false
    private var imagePlaneVertexBuffer: MTLBuffer?
    private var scenePlaneVertexBuffer: MTLBuffer?
    private var capturedImageTextureY: CVMetalTexture?
    private var capturedImageTextureCbCr: CVMetalTexture?
    private var sceneColorTexture: MTLTexture?
    private var alphaTexture: MTLTexture?

    init?(session: ARSession, mtkView: MTKView) {
        self.session = session
        self.mtkView = mtkView
        guard
            let device = mtkView.device,
            let textureCache = createTextureCache(device),
            let commandQueue = device.makeCommandQueue(),
            let pipelineState = createPipelineState(device, mtkView.colorPixelFormat),
            let currentDrawable = mtkView.currentDrawable
        else { return nil }
        self.device = device
        self.capturedImageTextureCache = textureCache
        self.matteGenerator = ARMatteGenerator(device: device, matteResolution: .half)
        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        let imagePlaneVertexDataCount = kImagePlaneVertexData.count * MemoryLayout<Float>.size
        imagePlaneVertexBuffer = device.makeBuffer(
            bytes: kImagePlaneVertexData, length: imagePlaneVertexDataCount, options: [])
        scenePlaneVertexBuffer = device.makeBuffer(
            bytes: kImagePlaneVertexData, length: imagePlaneVertexDataCount, options: [])
        let colorDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: mtkView.colorPixelFormat,
            width: currentDrawable.texture.width,
            height: currentDrawable.texture.height,
            mipmapped: false)
        colorDesc.usage = MTLTextureUsage(
            rawValue: MTLTextureUsage.renderTarget.rawValue | MTLTextureUsage.shaderRead.rawValue)
        sceneColorTexture = device.makeTexture(descriptor: colorDesc)
    }

    func drawRectResized(size: CGSize, interfaceOrientation: UIInterfaceOrientation?) {
        viewportSize = size
        if let interfaceOrientation = interfaceOrientation {
            self.interfaceOrientation = interfaceOrientation
        }
        viewportSizeDidChange = true
    }

    func update() {
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let renderPassDescriptor = mtkView.currentRenderPassDescriptor!
        let currentDrawable = mtkView.currentDrawable!
        updateImagePlaneIfNeeded()
        var texturesRef = [capturedImageTextureY, capturedImageTextureCbCr]
        commandBuffer.addCompletedHandler { [weak self] commandBuffer in
            self?.inFlightSemaphore.signal()
            texturesRef.removeAll()
        }
        updateTextures(commandBuffer: commandBuffer)
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPassDescriptor)
        {
            if let textureY = capturedImageTextureY,
                let textureCbCr = capturedImageTextureCbCr,
                let sceneColorTexture = sceneColorTexture,
                let alphaTexture = alphaTexture
            {
                renderEncoder.setRenderPipelineState(pipelineState)
                renderEncoder.setVertexBuffer(imagePlaneVertexBuffer, offset: 0, index: 0)
                renderEncoder.setVertexBuffer(scenePlaneVertexBuffer, offset: 0, index: 1)
                renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureY), index: 0)
                renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureCbCr), index: 1)
                renderEncoder.setFragmentTexture(sceneColorTexture, index: 2)
                renderEncoder.setFragmentTexture(alphaTexture, index: 3)
                renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            renderEncoder.endEncoding()
        }
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }

    private func updateTextures(commandBuffer: MTLCommandBuffer) {
        guard let frame = session.currentFrame else { return }
        let buffer = frame.capturedImage
        if CVPixelBufferGetPlaneCount(buffer) < 2 { return }
        capturedImageTextureY = createTexture(buffer, .r8Unorm, 0)
        capturedImageTextureCbCr = createTexture(buffer, .rg8Unorm, 1)
        alphaTexture = matteGenerator.generateMatte(from: frame, commandBuffer: commandBuffer)
    }

    private func createTexture(
        _ buffer: CVPixelBuffer, _ pixelFormat: MTLPixelFormat, _ planeIndex: Int
    ) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(buffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(buffer, planeIndex)
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, capturedImageTextureCache, buffer, nil, pixelFormat, width, height, planeIndex,
            &texture)
        if status != kCVReturnSuccess { texture = nil }
        return texture
    }

    private func updateImagePlaneIfNeeded() {
        if !viewportSizeDidChange { return }
        guard
            let frame = session.currentFrame,
            let imagePlaneVertexBuffer = imagePlaneVertexBuffer,
            let scenePlaneVertexBuffer = scenePlaneVertexBuffer
        else { return }
        viewportSizeDidChange = false
        let displayToCameraTransform = frame.displayTransform(
            for: interfaceOrientation, viewportSize: viewportSize
        ).inverted()
        let imagePlaneVertexData = imagePlaneVertexBuffer.contents().assumingMemoryBound(
            to: Float.self)
        let scenePlaneVertexData = scenePlaneVertexBuffer.contents().assumingMemoryBound(
            to: Float.self)
        for index in 0...3 {
            let textureCoordIndex = 4 * index + 2
            let textureCoord = CGPoint(
                x: CGFloat(kImagePlaneVertexData[textureCoordIndex]),
                y: CGFloat(kImagePlaneVertexData[textureCoordIndex + 1]))
            let transformedCoord = textureCoord.applying(displayToCameraTransform)
            imagePlaneVertexData[textureCoordIndex] = Float(transformedCoord.x)
            imagePlaneVertexData[textureCoordIndex + 1] = Float(transformedCoord.y)
            scenePlaneVertexData[textureCoordIndex] = kImagePlaneVertexData[textureCoordIndex]
            scenePlaneVertexData[textureCoordIndex + 1] =
                kImagePlaneVertexData[textureCoordIndex + 1]
        }
    }
}
