import Foundation

/// A tightly packed, immutable, 8-bit grayscale analysis frame.
/// Callers retain full-resolution image data separately for export.
public struct GrayFrame: Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case invalidDimensions
        case pixelCountMismatch(expected: Int, actual: Int)
    }

    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) throws {
        let product = width.multipliedReportingOverflow(by: height)
        guard width > 0, height > 0, !product.overflow else {
            throw ValidationError.invalidDimensions
        }
        guard pixels.count == product.partialValue else {
            throw ValidationError.pixelCountMismatch(expected: product.partialValue, actual: pixels.count)
        }
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}
