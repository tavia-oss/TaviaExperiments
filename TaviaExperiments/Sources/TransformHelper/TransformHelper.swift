import ARKit

public struct TransformHelper {
    public static func screenTransform(
        _ frame: ARFrame, _ viewportSize: CGSize, _ interfaceOrientation: UIInterfaceOrientation
    ) -> CGAffineTransform {
        let buffer = frame.capturedImage
        let imageSize = CGSize(
            width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let filpIfPortrait: CGAffineTransform
        if interfaceOrientation.isPortrait {
            filpIfPortrait = CGAffineTransform
                .identity
                .concatenating(CGAffineTransform(scaleX: -1, y: -1))
                .concatenating(CGAffineTransform(translationX: 1, y: 1))
        } else {
            filpIfPortrait = CGAffineTransform.identity
        }
        return CGAffineTransform
            .identity
            .concatenating(
                CGAffineTransform(scaleX: 1.0 / imageSize.width, y: 1.0 / imageSize.height)
            )
            .concatenating(filpIfPortrait)
            .concatenating(
                frame.displayTransform(for: interfaceOrientation, viewportSize: viewportSize)
            )
            .concatenating(CGAffineTransform(scaleX: viewportSize.width, y: viewportSize.height))
    }
}
