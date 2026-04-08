import Accelerate
import Foundation
#if arch(arm64)
import MLX

// MARK: - Utility Functions

nonisolated func concatenate(_ arrays: [MLXArray], axis: Int) -> MLXArray {
    return MLX.concatenated(arrays, axis: axis)
}

nonisolated func abs(_ x: MLXArray) -> MLXArray {
    return MLX.abs(x)
}

nonisolated func pow(_ x: MLXArray, _ exp: Float) -> MLXArray {
    return MLX.pow(x, exp)
}

nonisolated func pow(_ base: Float, _ exp: MLXArray) -> MLXArray {
    return MLX.pow(base, exp)
}

nonisolated func log(_ x: MLXArray) -> MLXArray {
    return MLX.log(x)
}

nonisolated func log10(_ x: Float) -> Float {
    return Foundation.log10(x)
}

nonisolated func log10(_ x: MLXArray) -> MLXArray {
    return MLX.log(x) / MLX.log(MLXArray(10.0))
}

nonisolated func cos(_ x: MLXArray) -> MLXArray {
    return MLX.cos(x)
}

nonisolated func matmul(_ a: MLXArray, _ b: MLXArray) -> MLXArray {
    return MLX.matmul(a, b)
}

// MARK: - MLXArray Extensions

extension MLXArray {
    nonisolated func std(axes: [Int]? = nil, keepDims: Bool = false) -> MLXArray {
        let meanVal =
            axes != nil ? self.mean(axes: axes!, keepDims: true) : self.mean(keepDims: true)
        let variance =
            axes != nil
            ? ((self - meanVal) * (self - meanVal)).mean(axes: axes!, keepDims: keepDims)
            : ((self - meanVal) * (self - meanVal)).mean(keepDims: keepDims)
        return MLX.sqrt(variance)
    }

    nonisolated func reversed(axes: [Int]) -> MLXArray {
        // For 1D reversal on axis 0
        let indices = MLXArray((0..<self.shape[0]).reversed())
        return self[indices]
    }

    nonisolated static func linspace(_ start: Float, _ end: Float, count: Int) -> MLXArray {
        let step = (end - start) / Float(count - 1)
        let values = (0..<count).map { start + Float($0) * step }
        return MLXArray(values)
    }

    nonisolated static func stacked(_ arrays: [MLXArray], axis: Int) -> MLXArray {
        return MLX.stacked(arrays, axis: axis)
    }
}
#endif
