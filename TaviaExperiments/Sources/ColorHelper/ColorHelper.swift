import CoreGraphics

public struct ColorHelper {
    private let cgImage: CGImage
    private let data: UnsafePointer<UInt8>
    private let rgbIndices: (Int, Int, Int)

    public init?(cgImage: CGImage) {
        guard
            validate(cgImage),
            let cfData = cgImage.dataProvider?.data,
            let bytePtr = CFDataGetBytePtr(cfData),
            let rgbIndices = getRGBIndices(cgImage.bitmapInfo)
        else { return nil }
        self.cgImage = cgImage
        self.data = bytePtr
        self.rgbIndices = rgbIndices
    }

    public func pixelColor(x: Int, y: Int) -> CGColor? {
        guard 0..<cgImage.width ~= x, 0..<cgImage.height ~= y else { return nil }
        let pixelOffset = y * cgImage.bytesPerRow + x * cgImage.bitsPerPixel / 8
        let red: UInt8 = data[pixelOffset + rgbIndices.0]
        let green: UInt8 = data[pixelOffset + rgbIndices.1]
        let blue: UInt8 = data[pixelOffset + rgbIndices.2]
        return .init(
            red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255,
            alpha: 1.0)
    }
}

private func validate(_ cgImage: CGImage) -> Bool {
    guard let model = cgImage.colorSpace?.model, model == .rgb else { return false }
    return cgImage.bitsPerPixel == 24 || cgImage.bitsPerPixel == 32
}

private func getRGBIndices(_ bitmapInfo: CGBitmapInfo) -> (Int, Int, Int)? {
    let alphaRawValue = bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue
    guard let alphaInfo = CGImageAlphaInfo(rawValue: alphaRawValue) else { return nil }
    var rgbaIndices = [Int]()
    switch alphaInfo {
    case .none:
        rgbaIndices = [0, 1, 2]
    case .premultipliedFirst, .first, .noneSkipFirst:
        rgbaIndices = [1, 2, 3, 0]
    default:
        rgbaIndices = [0, 1, 2, 3]
    }
    if bitmapInfo.contains(.byteOrder32Little) {
        rgbaIndices.reverse()
    }
    if rgbaIndices.count >= 3 {
        return (rgbaIndices[0], rgbaIndices[1], rgbaIndices[2])
    } else {
        return nil
    }
}
