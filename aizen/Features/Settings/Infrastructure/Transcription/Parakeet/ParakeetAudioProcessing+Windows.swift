import Accelerate
import Foundation
#if arch(arm64)
import MLX

// MARK: - Window Functions

nonisolated func getWindow(_ windowType: String, length: Int, dtype: DType) throws -> MLXArray {
    switch windowType.lowercased() {
    case "hanning", "hann":
        return hanningWindow(length: length, dtype: dtype)
    case "hamming":
        return hammingWindow(length: length, dtype: dtype)
    case "blackman":
        return blackmanWindow(length: length, dtype: dtype)
    case "bartlett":
        return bartlettWindow(length: length, dtype: dtype)
    default:
        throw ParakeetError.audioProcessingError("Unsupported window type: \(windowType)")
    }
}

nonisolated private func hanningWindow(length: Int, dtype: DType) -> MLXArray {
    let n = Float(length)
    let indices = MLXArray(0..<length).asType(.float32)
    let window = 0.5 * (1.0 - cos(2.0 * Float.pi * indices / (n - 1)))
    return window.asType(dtype)
}

nonisolated private func hammingWindow(length: Int, dtype: DType) -> MLXArray {
    let n = Float(length)
    let indices = MLXArray(0..<length).asType(.float32)
    let window = 0.54 - 0.46 * cos(2.0 * Float.pi * indices / (n - 1))
    return window.asType(dtype)
}

nonisolated private func blackmanWindow(length: Int, dtype: DType) -> MLXArray {
    let n = Float(length)
    let indices = MLXArray(0..<length).asType(.float32)
    let a0: Float = 0.42
    let a1: Float = 0.5
    let a2: Float = 0.08
    let window =
        a0 - a1 * cos(2.0 * Float.pi * indices / (n - 1)) + a2
        * cos(4.0 * Float.pi * indices / (n - 1))
    return window.asType(dtype)
}

nonisolated private func bartlettWindow(length: Int, dtype: DType) -> MLXArray {
    let n = Float(length)
    let indices = MLXArray(0..<length).asType(.float32)
    let window = 1.0 - abs((indices - (n - 1) / 2.0) / ((n - 1) / 2.0))
    return window.asType(dtype)
}
#endif
